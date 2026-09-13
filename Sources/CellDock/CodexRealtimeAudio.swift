import AppKit
import Foundation
import WebKit

/// WebKit provides the same WebRTC media transport used by Codex Desktop.
/// Only modem PCM enters the outgoing track; no Mac microphone is requested.
@MainActor
final class CodexRealtimeAudio: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onStage: ((String) -> Void)?
    private var audioWindow: NSPanel?
    var onOffer: ((String) -> Void)?
    var onPCM: ((Data) -> Void)?
    var onConnected: (() -> Void)?
    var onError: ((String) -> Void)?
    private var webView: WKWebView?
    private var loaded = false

    func start() {
        stop()
        let controller = WKUserContentController()
        controller.add(self, name: "phoneAudio")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // This is a telephone media service, including while the owner's screen
        // is locked. Never allow an inactive WebKit page to suspend its JS graph.
        configuration.preferences.inactiveSchedulingPolicy = .none
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 2, height: 2), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        // A rendering surface keeps WebKit's live media graph running while
        // CellDock is in the menu bar. It never becomes key or handles input.
        let panel = NSPanel(contentRect: NSRect(x: -100, y: -100, width: 2, height: 2),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true; panel.alphaValue = 0.01
        panel.contentView = view; panel.orderFrontRegardless(); audioWindow = panel
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://localhost/"))
    }

    func stop() {
        loaded = false
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "phoneAudio")
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        audioWindow?.close(); audioWindow = nil
    }

    func acceptAnswer(_ sdp: String) {
        invoke("await phone.answer(sdp)", arguments: ["sdp": sdp])
    }

    func receive(_ data: Data) {
        guard loaded, !data.isEmpty else { return }
        invoke("phone.input(pcm)", arguments: ["pcm": data.base64EncodedString()])
    }

    private func invoke(_ body: String, arguments: [String: Any]) {
        guard let view = webView else { return }
        view.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { [weak self, weak view] result in
            guard let self, let view, self.webView === view else { return }
            if case .failure(let error) = result { self.onError?(error.localizedDescription) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "stage": onStage?(body["stage"] as? String ?? "")
        case "offer": loaded = true; if let sdp = body["sdp"] as? String { onOffer?(sdp) }
        case "pcm": if let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded) { onPCM?(data) }
        case "connected": onConnected?()
        case "error": onError?(body["message"] as? String ?? "实时音频连接失败。")
        default: break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onError?("实时音频进程已退出。")
    }

    private static let page = #"""
    <!doctype html><meta charset="utf-8"><script>
    const send = value => window.webkit.messageHandlers.phoneAudio.postMessage(value);
    const fail = error => send({type:'error', message:String(error?.message || error)});
    window.addEventListener('unhandledrejection', event => fail(event.reason));
    window.addEventListener('error', event => fail(event.message));
    const worklet = `
    class PhonePCM extends AudioWorkletProcessor {
      constructor() {
        super(); this.ring=new Float32Array(3200); this.read=0; this.write=0; this.count=0;
        this.phase=0; this.previous=0; this.current=0; this.sum=0; this.n=0;
        this.frame=new Int16Array(160); this.used=0;
        this.port.onmessage=({data}) => {
          const bytes=new Uint8Array(data);
          const pcm=new DataView(data);
          for(let i=0;i+1<bytes.length;i+=2) {
            if(this.count===this.ring.length) { this.read=(this.read+1)%this.ring.length; this.count--; }
            this.ring[this.write]=pcm.getInt16(i,true)/32768;
            this.write=(this.write+1)%this.ring.length; this.count++;
          }
        };
      }
      process(inputs, outputs) {
        const output=outputs[0][0], input=inputs[0]?.[0];
        const ratio=sampleRate/8000;
        for(let i=0;i<output.length;i++) {
          if(this.phase<=0) {
            this.previous=this.current;
            this.current=this.count ? this.ring[this.read] : 0;
            if(this.count) { this.read=(this.read+1)%this.ring.length; this.count--; }
            this.phase+=ratio;
          }
          output[i]=this.previous+(this.current-this.previous)*(1-this.phase/ratio); this.phase--;
          this.sum+=input?.[i] || 0; this.n++;
          if(this.n>=ratio) {
            this.frame[this.used++]=Math.max(-32768,Math.min(32767,Math.round(this.sum/this.n*32768)));
            this.sum=0; this.n=0;
            if(this.used===160) {
              this.port.postMessage(this.frame.buffer,[this.frame.buffer]); this.frame=new Int16Array(160); this.used=0;
            }
          }
        }
        return true;
      }
    }
    registerProcessor('phone-pcm',PhonePCM);`;
    window.phone = {
      async start() {
        this.context=new AudioContext({sampleRate:48000}); send({type:'stage',stage:'context:'+this.context.state});
        const url=URL.createObjectURL(new Blob([worklet],{type:'text/javascript'}));
        await this.context.audioWorklet.addModule(url); URL.revokeObjectURL(url); send({type:'stage',stage:'worklet-loaded'});
        this.node=new AudioWorkletNode(this.context,'phone-pcm',{numberOfInputs:1,numberOfOutputs:1,outputChannelCount:[1]});
        this.node.port.onmessage=({data}) => {
          const bytes=new Uint8Array(data); let text='';
          for(const b of bytes) text+=String.fromCharCode(b);
          send({type:'pcm',data:btoa(text)});
        };
        const output=this.context.createMediaStreamDestination(); this.node.connect(output);
        this.pc=new RTCPeerConnection({iceServers:[]});
        this.pc.addTrack(output.stream.getAudioTracks()[0],output.stream);
        this.pc.createDataChannel('oai-events');
        this.pc.ontrack=event => {
          this.remote=this.context.createMediaStreamSource(new MediaStream([event.track]));
          this.remote.connect(this.node);
        };
        this.pc.onconnectionstatechange=()=>{
          if(this.pc.connectionState==='connected' && !this.connected) { this.connected=true; send({type:'connected'}); }
          if(this.pc.connectionState==='failed') fail('WebRTC 音频连接失败');
          if(this.pc.connectionState==='disconnected') {
            setTimeout(()=>{if(this.pc?.connectionState==='disconnected') fail('WebRTC 音频连接中断');},8000);
          }
        };
        await this.context.resume(); send({type:'stage',stage:'context-resumed'});
        await this.pc.setLocalDescription(await this.pc.createOffer());
        if(this.pc.iceGatheringState!=='complete') await new Promise((resolve,reject)=>{
          const timeout=setTimeout(()=>reject(Error('音频网络准备超时')),10000);
          this.pc.onicegatheringstatechange=()=>{if(this.pc.iceGatheringState==='complete'){clearTimeout(timeout);resolve();}};
        });
        send({type:'offer',sdp:this.pc.localDescription.sdp});
      },
      async answer(sdp) { await this.pc.setRemoteDescription({type:'answer',sdp}); },
      input(pcm) { const data=Uint8Array.from(atob(pcm),c=>c.charCodeAt(0)).buffer; this.node.port.postMessage(data,[data]); }
    };
    phone.start().catch(fail);
    </script>
    """#
}
