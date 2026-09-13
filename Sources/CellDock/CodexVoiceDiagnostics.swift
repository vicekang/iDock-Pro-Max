import Foundation

/// Exercises the shipping WebRTC bridge without dialing or recording a microphone.
@MainActor
final class CodexVoiceDiagnostics {
    private var generation = UUID()
    private let agent = CodexPhoneAgent()
    private var finish: ((Result<[String: Any], Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var feeder: Timer?
    private var samples = 0
    private var audibleSamples = 0
    private var transcripts: [[String: String]] = []
    private var input = Data()
    private var connected = false

    func run(pcm: Data?, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard finish == nil else { completion(.failure(CodexBridgeError("语音测试正在运行。"))); return }
        generation = UUID(); let current = generation
        finish = completion; samples = 0; audibleSamples = 0; transcripts = []; connected = false
        input = pcm ?? Data()
        let hasInput = !input.isEmpty
        agent.onPCM = { [weak self] data in
            guard let self else { return }
            self.samples += data.count / 2
            data.withUnsafeBytes { bytes in
                for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                    let value = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                    if abs(Int(value)) > 128 { self.audibleSamples += 1 }
                }
            }
        }
        agent.onTranscript = { [weak self] role, text in self?.transcripts.append(["role": role, "text": text]) }
        agent.onFailure = { [weak self] error in self?.complete(.failure(CodexBridgeError(error))) }
        agent.onConnected = { [weak self] in
            guard let self else { return }
            self.connected = true
            // Let the greeting finish before feeding the synthetic test phrase.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.finish != nil, self.generation == current else { return }
                self.feeder = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.finish != nil, self.generation == current else { return }
                        let count = min(320, self.input.count)
                        var frame = Data(self.input.prefix(count)); self.input.removeFirst(count)
                        if frame.count < 320 { frame.append(Data(repeating: 0, count: 320 - frame.count)) }
                        self.agent.receive(frame)
                    }
                }
            }
            let duration = max(15, Double(self.input.count) / 16000 + 18)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.finish != nil, self.generation == current else { return }
                guard self.audibleSamples > 400 else { self.complete(.failure(CodexBridgeError("语音已连接，但未收到可听的回复。"))); return }
                if hasInput && !self.transcripts.contains(where: { $0["role"] == "caller" }) {
                    self.complete(.failure(CodexBridgeError("收到声音，但测试语音未产生转写。"))); return
                }
                self.complete(.success(["backend": "codex-gpt-live-webrtc", "connected": self.connected,
                    "sampleRate": 8000, "receivedSamples": self.samples, "audibleSamples": self.audibleSamples,
                    "transcripts": self.transcripts]))
            }
        }
        let deadline = DispatchWorkItem { [weak self] in self?.complete(.failure(CodexBridgeError("原生语音测试超时。"))) }
        timeout = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 65, execute: deadline)
        agent.start(instructions: "这是隔离的音频自检，并未接通真实电话。你是 AI 电话助理。用中文简短对话；听到预约要求时复述预约时间。不要调用工具。",
                    greeting: "你好，Codex 原生语音已连接。")
    }

    private func complete(_ result: Result<[String: Any], Error>) {
        guard let callback = finish else { return }
        generation = UUID(); finish = nil; timeout?.cancel(); timeout = nil; feeder?.invalidate(); feeder = nil
        agent.stop(); input.removeAll(); callback(result)
    }
}
