import Foundation

/// The signed-in Codex app-server owns authentication and GPT-Live sessions.
/// WebRTC carries telephone audio directly, including turn taking and interruption.
@MainActor
final class CodexPhoneAgent {
    var onStatus: ((String) -> Void)?
    var onTranscript: ((String, String) -> Void)?
    var onPCM: ((Data) -> Void)?
    var onFailure: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onStage: ((String) -> Void)?
    var onInterruption: (() -> Void)?
    private let codex = CodexConversation()
    private let audio = CodexRealtimeAudio()
    private var generation = UUID()
    private var startupDeadline: DispatchWorkItem?
    private var connected = false
    private var requestedGreeting: String?
    private var didRequestGreeting = false
    private var earlyInput = CodexEarlyInput()
    private var inputFeeder: Timer?
    private(set) var active = false
    private(set) var status = "待机"

    func start(instructions: String, greeting: String, deferGreeting: Bool = false,
               prerecordedOpening: String? = nil) {
        stop(); active = true
        requestedGreeting = deferGreeting || prerecordedOpening != nil ? nil : greeting
        let current = generation
        setStatus("正在连接 Codex 原生语音")
        let openingPrompt: String
        if let prerecordedOpening {
            openingPrompt = "本机正在通过电话播放预录开场白，已经介绍 AI 助理身份并询问来意。" +
                "你不要重复开场白，不要主动出声确认，不要说好的或请稍等。等待来电者说话后直接回应其来意。" +
                "对方在开场录音期间说话也要听取。开场录音文字供理解：\(prerecordedOpening)"
        } else {
            openingPrompt = "先准备音频并保持安静。收到电话接通通知时才说开场白。开场白：" + greeting
        }
        let prompt = instructions + "\n这是通过 4G 模块连接的电话。直接听取对方音频并用声音自然回答，允许对方打断。你没有电脑操作工具。" + openingPrompt
        audio.onPCM = { [weak self] data in
            guard let self, self.active, self.generation == current else { return }
            self.onPCM?(data)
        }
        audio.onError = { [weak self] message in self?.fail(message, generation: current) }
        audio.onInterruption = { [weak self] in
            guard let self, self.active, self.generation == current else { return }
            self.onInterruption?()
        }
        audio.onStage = { [weak self] stage in
            guard let self, self.active, self.generation == current else { return }
            self.onStage?(stage)
        }
        audio.onConnected = { [weak self] in
            guard let self, self.active, self.generation == current else { return }
            self.startupDeadline?.cancel(); self.startupDeadline = nil
            self.connected = true
            self.setStatus("Codex 原生语音通话中")
            self.sendGreetingIfReady()
            self.drainEarlyInput(generation: current)
            self.onConnected?()
        }
        audio.onOffer = { [weak self] sdp in
            guard let self, self.active, self.generation == current else { return }
            self.codex.startRealtime(sdp: sdp, instructions: prompt) { [weak self] result in
                if case .failure(let error) = result { self?.fail(error.localizedDescription, generation: current) }
            }
        }
        codex.onConnectionError = { [weak self] error in self?.fail(error.localizedDescription, generation: current) }
        codex.onRealtimeEvent = { [weak self] method, params in
            guard let self, self.active, self.generation == current else { return }
            switch method {
            case "thread/realtime/sdp":
                if let sdp = params["sdp"] as? String { self.audio.acceptAnswer(sdp) }
            case "thread/realtime/transcript/done":
                if let text = params["text"] as? String, !text.isEmpty {
                    let role = params["role"] as? String ?? "user"
                    self.onTranscript?(role == "assistant" ? "assistant" : "caller", text)
                }
            case "thread/realtime/error": self.fail(params["message"] as? String ?? "Codex 语音连接失败。", generation: current)
            case "thread/realtime/closed": self.fail("Codex 语音会话已结束。", generation: current)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.fail("Codex 原生语音连接超时。", generation: current) }
        startupDeadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 55, execute: timeout)
        codex.start(instructions: instructions) { [weak self] result in
            guard let self, self.active, self.generation == current else { return }
            switch result {
            case .failure(let error): self.fail(error.localizedDescription, generation: current)
            case .success: self.audio.start()
            }
        }
    }

    func stop() {
        active = false; generation = UUID()
        startupDeadline?.cancel(); startupDeadline = nil
        connected = false; requestedGreeting = nil; didRequestGreeting = false
        inputFeeder?.invalidate(); inputFeeder = nil; earlyInput.reset()
        audio.stop(); codex.onRealtimeEvent = nil; codex.onConnectionError = nil
        codex.stop(); setStatus("待机")
    }

    func activate(greeting: String, prerecorded: Bool) {
        guard active, !prerecorded else { return }
        requestedGreeting = greeting; sendGreetingIfReady()
    }

    private func sendGreetingIfReady() {
        guard connected, !didRequestGreeting, let requestedGreeting else { return }
        didRequestGreeting = true
        codex.appendRealtimeText("电话已经接通。请说：\(requestedGreeting)。然后等对方说话。")
    }

    func receive(_ pcm: Data) {
        guard active else { return }
        if connected, inputFeeder == nil { audio.receive(pcm); return }
        let hadOverflow = earlyInput.overflowed
        earlyInput.append(pcm)
        if !hadOverflow, earlyInput.overflowed { onStage?("caller-startup-buffer-overflow") }
    }

    private func drainEarlyInput(generation current: UUID) {
        guard earlyInput.hasSpeech else { earlyInput.reset(); return }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active, self.generation == current else { return }
                if let frame = self.earlyInput.nextFrame() { self.audio.receive(frame) }
                if self.earlyInput.isEmpty {
                    self.inputFeeder?.invalidate(); self.inputFeeder = nil; self.earlyInput.reset()
                }
            }
        }
        inputFeeder = timer; RunLoop.main.add(timer, forMode: .common)
    }

    func testCodex(_ text: String, instructions: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !active else { completion(.failure(CodexBridgeError("通话期间不能运行诊断。"))); return }
        codex.start(instructions: instructions) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): self.codex.stop(); completion(.failure(error))
            case .success:
                self.codex.respond(to: text) { result in self.codex.stop(); completion(result) }
            }
        }
    }

    private func fail(_ message: String, generation current: UUID) {
        guard active, generation == current else { return }
        stop(); setStatus(message); onFailure?(message)
    }
    private func setStatus(_ value: String) { status = value; onStatus?(value) }
}
