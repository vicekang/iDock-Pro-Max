import Foundation

/// Telephone PCM16, mono, 8 kHz. One output owner prevents a saved greeting
/// and a live model reply from talking over each other. No modem I/O here.
struct CodexOpeningPlayback {
    enum Phase: String { case stopped, waitingForMedia, template, queuedReply, live }
    private(set) var phase: Phase = .stopped
    private var opening = Data()
    private var reply = Data()
    private let maximumReplyBytes = 32 * 16_000
    private(set) var overflowed = false

    mutating func prepare(_ pcm: Data) {
        stop(); opening = pcm; phase = .waitingForMedia
    }
    mutating func mediaReady() {
        guard phase == .waitingForMedia else { return }
        phase = opening.isEmpty ? (reply.isEmpty ? .live : .queuedReply) : .template
    }
    mutating func replaceOpening(_ pcm: Data) {
        guard phase == .waitingForMedia else { return }
        opening = pcm
    }
    mutating func discardInterruptedReply() {
        reply.removeAll()
        if phase == .queuedReply { phase = .live }
    }
    /// Live frames bypass the startup scheduler entirely.
    mutating func receiveModel(_ pcm: Data) -> Data? {
        guard phase != .stopped, pcm.count % 2 == 0 else { return nil }
        if phase == .live { return pcm }
        if reply.isEmpty, !Self.hasVoice(pcm) { return nil }
        guard reply.count + pcm.count <= maximumReplyBytes else {
            overflowed = true; return nil
        }
        reply.append(pcm); return nil
    }
    /// The caller paces these 20 ms frames; never enqueue a whole recording in
    /// VoiceAudioService's 400 ms ring, which would discard its beginning.
    mutating func nextFrame() -> Data? {
        guard phase == .template || phase == .queuedReply else { return nil }
        var frame = Data()
        if phase == .template {
            let count = min(320, opening.count)
            frame.append(opening.prefix(count)); opening.removeFirst(count)
            if opening.isEmpty { phase = .queuedReply }
        }
        if phase == .queuedReply, frame.count < 320 {
            let count = min(320 - frame.count, reply.count)
            frame.append(reply.prefix(count)); reply.removeFirst(count)
        }
        if phase == .queuedReply, reply.isEmpty { phase = .live }
        if frame.isEmpty { return nil }
        if frame.count < 320 { frame.append(Data(repeating: 0, count: 320 - frame.count)) }
        return frame
    }
    mutating func stop() {
        phase = .stopped; opening.removeAll(); reply.removeAll(); overflowed = false
    }
    static func hasVoice(_ pcm: Data) -> Bool {
        pcm.withUnsafeBytes { raw in
            for index in stride(from: 0, to: raw.count - 1, by: 2) {
                let value = Int16(bitPattern: UInt16(raw[index]) | UInt16(raw[index + 1]) << 8)
                if abs(Int(value)) > 128 { return true }
            }
            return false
        }
    }
}

/// Preserve a caller's first words while WebRTC connects. Silence before the
/// first word is bounded; replay is paced rather than flooding the WebRTC ring.
struct CodexEarlyInput {
    private var bytes = Data()
    private(set) var hasSpeech = false
    private(set) var overflowed = false
    var isEmpty: Bool { bytes.isEmpty }
    mutating func append(_ pcm: Data) {
        guard pcm.count % 2 == 0 else { return }
        hasSpeech = hasSpeech || CodexOpeningPlayback.hasVoice(pcm)
        bytes.append(pcm)
        let limit = hasSpeech ? 8 * 16_000 : 1_600
        if bytes.count > limit {
            if hasSpeech { overflowed = true }
            bytes.removeFirst(bytes.count - limit)
        }
    }
    mutating func nextFrame() -> Data? {
        // Catch up only across silence; never accelerate or truncate speech.
        while bytes.count > 1_600, !CodexOpeningPlayback.hasVoice(Data(bytes.prefix(320))) {
            bytes.removeFirst(320)
        }
        guard !bytes.isEmpty else { return nil }
        let count = min(320, bytes.count)
        let frame = Data(bytes.prefix(count)); bytes.removeFirst(count)
        return frame
    }
    mutating func reset() { bytes.removeAll(); hasSpeech = false; overflowed = false }
}
