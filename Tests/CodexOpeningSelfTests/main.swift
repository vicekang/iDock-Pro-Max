import Foundation
import AVFoundation

struct CodexBridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@main struct OpeningTests {
    static func pcm(_ value: Int16, samples: Int) -> Data {
        var result = Data()
        for _ in 0..<samples {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { result.append(contentsOf: $0) }
        }
        return result
    }
    @MainActor static func main() async throws {
        let template = pcm(1000, samples: 640), answer = pcm(2000, samples: 320)
        var playback = CodexOpeningPlayback()
        playback.prepare(template)
        precondition(playback.nextFrame() == nil, "No audio before telephone media is ready")
        precondition(playback.receiveModel(answer) == nil)
        playback.mediaReady()
        var mixed = Data()
        while let frame = playback.nextFrame() { mixed.append(frame) }
        precondition(mixed == template + answer, "Template precedes the complete buffered answer without overlap")
        precondition(playback.receiveModel(answer) == answer, "No extra scheduler in the steady-state path")
        playback.prepare(template); _ = playback.receiveModel(answer)
        playback.replaceOpening(pcm(3000, samples: 160)); playback.mediaReady()
        var replaced = Data()
        while let frame = playback.nextFrame() { replaced.append(frame) }
        precondition(replaced.prefix(960) == pcm(3000, samples: 160) + answer, "Changing the recording notice cannot discard an early reply")
        playback.prepare(template); _ = playback.receiveModel(answer)
        playback.discardInterruptedReply(); playback.mediaReady()
        var interrupted = Data()
        while let frame = playback.nextFrame() { interrupted.append(frame) }
        precondition(interrupted == template, "Interrupted AI audio is not replayed after the template")
        playback.prepare(template); _ = playback.receiveModel(answer); playback.stop()
        precondition(playback.nextFrame() == nil && playback.receiveModel(answer) == nil)
        playback.prepare(Data()); playback.mediaReady()
        precondition(playback.phase == .live, "Disabled/missing opening preserves direct AI audio")
        playback.prepare(template)
        _ = playback.receiveModel(pcm(2000, samples: 8_000 * 33))
        precondition(playback.overflowed, "Model output backlog is bounded")

        var input = CodexEarlyInput()
        input.append(Data(repeating: 0, count: 100_000)); input.append(answer)
        var replayed = Data()
        while let frame = input.nextFrame() { replayed.append(frame) }
        precondition(replayed.suffix(answer.count) == answer && replayed.count <= answer.count + 1600,
                     "First caller words survive startup without replaying seconds of silence")
        input.append(answer); input.reset(); precondition(input.nextFrame() == nil)
        input.append(pcm(1000, samples: 8_000 * 9)); precondition(input.overflowed)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("opening-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.wav")
        let waveform = (0..<8_000).map { Int16(sin(Double($0) * 2 * .pi * 440 / 8_000) * 10_000) }
        let tone = waveform.reduce(into: Data()) { data, value in
            var le = value.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        try CodexOpeningDecoder.wave(Data(repeating: 0, count: 16_000) + tone + Data(repeating: 0, count: 16_000)).write(to: source)
        let decoded = try CodexOpeningDecoder.decode(source)
        precondition(decoded.count > 16_000 && decoded.count < 20_000, "Trim leading/trailing silence while preserving speech padding")
        let silent = root.appendingPathComponent("silent.wav")
        try CodexOpeningDecoder.wave(Data(repeating: 0, count: 16_000)).write(to: silent)
        do { _ = try CodexOpeningDecoder.decode(silent); fatalError("Silence should be rejected") } catch {}
        let long = root.appendingPathComponent("long.wav")
        try CodexOpeningDecoder.wave(Data(repeating: 0, count: 21 * 16_000)).write(to: long)
        do { _ = try CodexOpeningDecoder.decode(long); fatalError("Long clips should be rejected") } catch {}

        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let defaults = UserDefaults(suiteName: "opening-test-\(UUID())")!
        let storage = root.appendingPathComponent("private")
        let library = CodexOpeningAudio(directory: storage, defaults: defaults, resources: resources)
        precondition(library.clip(recording: true)!.duration > library.clip(recording: false)!.duration)
        let originalDefault = library.clip(recording: false)!.pcm
        library.importFile(source)
        while library.importing { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.customName != nil && library.lastError == nil)
        precondition(FileManager.default.fileExists(atPath: source.path), "Source recording is preserved")
        let mode = try FileManager.default.attributesOfItem(atPath: storage.appendingPathComponent("custom.wav").path)[.posixPermissions] as? Int
        precondition(mode == 0o600)
        let customWithout = library.clip(recording: false)!.pcm
        library.customIncludesRecordingNotice = true
        precondition(library.clip(recording: true)!.pcm == customWithout)
        library.importFile(silent)
        while library.importing { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.clip(recording: false)!.pcm == customWithout, "Failed import preserves the previous valid recording")
        let boundary = root.appendingPathComponent("boundary.wav")
        try CodexOpeningDecoder.wave(pcm(1000, samples: 20 * 8_000)).write(to: boundary)
        library.importFile(boundary)
        while library.importing { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.lastError == nil)
        let reloaded = CodexOpeningAudio(directory: storage, defaults: defaults, resources: resources)
        precondition(reloaded.customName != nil && reloaded.clip(recording: false)!.duration > 20,
                     "An accepted 20-second recording remains available after relaunch with its protective padding")
        library.useDefault(); precondition(library.clip(recording: false)!.pcm == originalDefault)
        library.setEnabled(false); precondition(library.clip(recording: false) == nil)
        print("Opening tests passed: ordered audio, media gate, interruption, cancellation, bounded queues, early caller speech, decoder validation, private import, fallback and recording notices.")
    }
}
