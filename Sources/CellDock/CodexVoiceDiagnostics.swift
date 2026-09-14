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
    private var openingPlayback = CodexOpeningPlayback()
    private var openingTimer: Timer?
    private var outputPCM = Data()
    private var startedAt: TimeInterval = 0
    private var firstOutputAt: TimeInterval?
    private var connectedAt: TimeInterval?

    func run(pcm: Data?, opening: CodexOpeningClip? = nil, voice: CodexPhoneVoice = .automatic,
             completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard finish == nil else { completion(.failure(CodexBridgeError("语音测试正在运行。"))); return }
        generation = UUID(); let current = generation
        finish = completion; samples = 0; audibleSamples = 0; transcripts = []; connected = false
        input = pcm ?? Data()
        startedAt = ProcessInfo.processInfo.systemUptime; firstOutputAt = nil; connectedAt = nil; outputPCM.removeAll()
        openingPlayback.prepare(opening?.pcm ?? Data()); openingPlayback.mediaReady()
        if opening != nil {
            let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.finish != nil, self.generation == current else { return }
                    if let frame = self.openingPlayback.nextFrame() { self.captureOutput(frame) }
                    if self.openingPlayback.phase == .live { self.openingTimer?.invalidate(); self.openingTimer = nil }
                }
            }
            openingTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        let hasInput = !input.isEmpty
        agent.onPCM = { [weak self] data in
            guard let self else { return }
            if let frame = self.openingPlayback.receiveModel(data) { self.captureOutput(frame) }
            self.samples += data.count / 2
            data.withUnsafeBytes { bytes in
                for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                    let value = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                    if abs(Int(value)) > 128 { self.audibleSamples += 1 }
                }
            }
        }
        agent.onTranscript = { [weak self] role, text in self?.transcripts.append(["role": role, "text": text]) }
        agent.onInterruption = { [weak self] in self?.openingPlayback.discardInterruptedReply() }
        agent.onFailure = { [weak self] error in self?.complete(.failure(CodexBridgeError(error))) }
        agent.onConnected = { [weak self] in
            guard let self else { return }
            self.connected = true
            self.connectedAt = ProcessInfo.processInfo.systemUptime
            // Let the greeting finish before feeding the synthetic test phrase.
            let inputDelay = opening.map { max(0.2, self.startedAt + $0.duration + 0.3 - ProcessInfo.processInfo.systemUptime) } ?? 5
            DispatchQueue.main.asyncAfter(deadline: .now() + inputDelay) { [weak self] in
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
                guard (opening != nil && !hasInput) || self.audibleSamples > 400 else { self.complete(.failure(CodexBridgeError("语音已连接，但未收到可听的回复。"))); return }
                if hasInput && !self.transcripts.contains(where: { $0["role"] == "caller" }) {
                    self.complete(.failure(CodexBridgeError("收到声音，但测试语音未产生转写。"))); return
                }
                var result: [String: Any] = ["backend": "codex-gpt-live-webrtc", "connected": self.connected,
                    "sampleRate": 8000, "voice": voice.rawValue, "receivedSamples": self.samples, "audibleSamples": self.audibleSamples,
                    "transcripts": self.transcripts]
                if let opening {
                    result["openingSeconds"] = opening.duration
                    result["firstOutputSeconds"] = self.firstOutputAt.map { $0 - self.startedAt } ?? -1
                    result["voiceConnectedSeconds"] = self.connectedAt.map { $0 - self.startedAt } ?? -1
                    result["outputPCM8k"] = self.outputPCM.base64EncodedString()
                    result["physicalTelephoneTest"] = false
                }
                self.complete(.success(result))
            }
        }
        let deadline = DispatchWorkItem { [weak self] in self?.complete(.failure(CodexBridgeError("原生语音测试超时。"))) }
        timeout = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 65, execute: deadline)
        agent.start(instructions: "这是隔离的音频自检，并未接通真实电话。你是 AI 电话助理。用中文简短对话；听到预约要求时复述预约时间。不要调用工具。",
                    greeting: "你好，Codex 原生语音已连接。", prerecordedOpening: opening?.text, voice: voice)
    }

    private func captureOutput(_ pcm: Data) {
        if firstOutputAt == nil, CodexOpeningPlayback.hasVoice(pcm) { firstOutputAt = ProcessInfo.processInfo.systemUptime }
        if outputPCM.count + pcm.count <= 65 * 16_000 { outputPCM.append(pcm) }
    }

    private func complete(_ result: Result<[String: Any], Error>) {
        guard let callback = finish else { return }
        generation = UUID(); finish = nil; timeout?.cancel(); timeout = nil; feeder?.invalidate(); feeder = nil
        openingTimer?.invalidate(); openingTimer = nil; openingPlayback.stop(); outputPCM.removeAll()
        agent.stop(); input.removeAll(); callback(result)
    }
}
