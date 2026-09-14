import Foundation

struct CodexBridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Controlled transport boundaries; the production agent lifecycle is compiled above.
@MainActor final class CodexConversation {
    static var last: CodexConversation!
    var onConnectionError: ((Error) -> Void)?
    var onRealtimeEvent: ((String, [String: Any]) -> Void)?
    var texts: [String] = []
    var realtimeVoices: [String?] = []
    init() { Self.last = self }
    func start(instructions: String, completion: @escaping (Result<Void, Error>) -> Void) { completion(.success(())) }
    func startRealtime(sdp: String, instructions: String, voice: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        realtimeVoices.append(voice); completion(.success(()))
    }
    func appendRealtimeText(_ text: String) { texts.append(text) }
    func respond(to: String, completion: @escaping (Result<String, Error>) -> Void) { completion(.success("ok")) }
    func stop() {}
}

@MainActor final class CodexRealtimeAudio {
    static var last: CodexRealtimeAudio!
    var onPCM: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onInterruption: (() -> Void)?
    var onStage: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onOffer: ((String) -> Void)?
    var received = Data()
    init() { Self.last = self }
    func start() {}
    func stop() {}
    func acceptAnswer(_ sdp: String) {}
    func receive(_ pcm: Data) { received.append(pcm) }
}

@main struct Tests {
    @MainActor static func main() async throws {
        precondition(CodexPhoneVoice(rawValue: "coral") == nil && CodexPhoneVoice(rawValue: "shimmer") == nil,
                     "V2-only voices must not be offered for a V3 telephone session")
        let agent = CodexPhoneAgent()
        let audio = CodexRealtimeAudio.last!, codex = CodexConversation.last!
        agent.start(instructions: "test", greeting: "hello", deferGreeting: true, voice: .juniper)
        audio.onOffer?("test sdp")
        precondition(codex.realtimeVoices.count == 1 && codex.realtimeVoices[0] == "juniper", "The selected voice must reach the actual realtime request")
        let staleConnection = audio.onConnected!
        audio.onConnected?()
        precondition(codex.texts.isEmpty, "prewarming must not speak before telephone activation")
        agent.activate(greeting: "hello", prerecorded: false)
        agent.activate(greeting: "hello", prerecorded: false)
        precondition(codex.texts.count == 1, "one greeting per call")
        agent.stop()
        agent.start(instructions: "test", greeting: "next", deferGreeting: true)
        audio.onOffer?("next sdp")
        precondition(codex.realtimeVoices.count == 2 && codex.realtimeVoices[1] == nil, "Default voice must omit the override, without leaking the previous call's selection")
        agent.activate(greeting: "next", prerecorded: false)
        staleConnection()
        precondition(codex.texts.count == 1, "an old connection must not activate a new call")
        audio.onConnected?()
        precondition(codex.texts.count == 2, "connection after activation sends greeting once")
        agent.stop()

        agent.start(instructions: "test", greeting: "ignored", deferGreeting: true, prerecordedOpening: "saved introduction")
        let speech = Data(repeating: 12, count: 960)
        agent.receive(speech)
        precondition(audio.received.isEmpty, "caller speech waits for the transport")
        audio.onConnected?()
        agent.activate(greeting: "ignored", prerecorded: true)
        precondition(codex.texts.count == 2, "local opening must not trigger a duplicate AI greeting")
        try await Task.sleep(nanoseconds: 180_000_000)
        precondition(audio.received == speech, "the first caller words survive connection startup in order")
        let beforeStop = audio.received
        agent.stop(); agent.receive(speech)
        try await Task.sleep(nanoseconds: 60_000_000)
        precondition(audio.received == beforeStop, "stopped calls cannot feed buffered audio")

        agent.start(instructions: "test", greeting: "hello", deferGreeting: true)
        var failureCount = 0, outputCount = 0
        agent.onFailure = { _ in failureCount += 1 }
        agent.onPCM = { _ in outputCount += 1 }
        let latePCM = audio.onPCM!
        audio.onError?("connection failed")
        latePCM(speech)
        precondition(!agent.active && failureCount == 1 && outputCount == 0, "startup failure cancels late audio")
        print("Codex agent lifecycle passed: prewarm/activation order, one greeting, stale callbacks, prerecorded handoff, early speech and failure cancellation.")
    }
}
