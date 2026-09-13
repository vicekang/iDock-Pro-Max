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
    private let codex = CodexConversation()
    private let audio = CodexRealtimeAudio()
    private var generation = UUID()
    private var startupDeadline: DispatchWorkItem?
    private(set) var active = false
    private(set) var status = "待机"

    func start(instructions: String, greeting: String) {
        stop(); active = true
        let current = generation
        setStatus("正在连接 Codex 原生语音")
        let prompt = instructions + "\n这是通过 4G 模块接通的真实电话。直接听取对方音频并用声音自然回答，允许对方打断。你没有电脑操作工具。开场说：" + greeting
        audio.onPCM = { [weak self] data in
            guard let self, self.active, self.generation == current else { return }
            self.onPCM?(data)
        }
        audio.onError = { [weak self] message in self?.fail(message, generation: current) }
        audio.onStage = { [weak self] stage in
            guard let self, self.active, self.generation == current else { return }
            self.onStage?(stage)
        }
        audio.onConnected = { [weak self] in
            guard let self, self.active, self.generation == current else { return }
            self.startupDeadline?.cancel(); self.startupDeadline = nil
            self.setStatus("Codex 原生语音通话中")
            self.codex.appendRealtimeText("电话已经接通，请说开场白，然后等对方说话。")
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
        audio.stop(); codex.onRealtimeEvent = nil; codex.onConnectionError = nil
        codex.stop(); setStatus("待机")
    }

    func receive(_ pcm: Data) { if active { audio.receive(pcm) } }

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
