import AVFoundation
import Foundation

enum CallRecordingSelfTestFailure: Error {
    case failed(String)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CallRecordingSelfTestFailure.failed(message) }
}

let namingDate = Date(timeIntervalSince1970: 1_712_926_896)
let namingTimeZone = TimeZone(secondsFromGMT: 0)!
try expect(
    CallRecordingStore.recordingFileName(
        localNumber: "+86 138 0013 8000",
        remoteNumber: "+10086",
        startedAt: namingDate,
        timeZone: namingTimeZone
    ) == "8613800138000_10086_2024-04-12-130136.m4a",
    "recording file name did not include the local number, remote number, and timestamp"
)
try expect(
    CallRecordingStore.recordingFileName(
        localNumber: nil,
        remoteNumber: "12/34",
        startedAt: namingDate,
        timeZone: namingTimeZone
    ) == "unknown-local-number_12-34_2024-04-12-130136.m4a",
    "recording file name fallback or sanitization was incorrect"
)

let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CellDock-recording-test-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

let outputURL = temporaryDirectory.appendingPathComponent("stereo.m4a")
let startedAt = Date()
let frameCount = 8_000
let localSamples = (0 ..< frameCount).map { frame -> Int16 in
    let value = sin(Double(frame) * 2 * .pi * 440 / 8_000)
    return Int16(value * 8_000)
}
let remoteSamples = (0 ..< frameCount).map { frame -> Int16 in
    let value = sin(Double(frame) * 2 * .pi * 660 / 8_000)
    return Int16(value * 6_000)
}
let localPCM = localSamples.withUnsafeBytes { Data($0) }
let remotePCM = remoteSamples.withUnsafeBytes { Data($0) }

try CallRecordingCapture.shared.start(
    id: UUID(),
    startedAt: startedAt,
    outputURL: outputURL
)
CallRecordingCapture.shared.appendUplink(localPCM, at: startedAt)
CallRecordingCapture.shared.appendDownlink(remotePCM, at: startedAt)

let semaphore = DispatchSemaphore(value: 0)
var finalResult: Result<CallRecordingCapture.FinalizedCapture, Error>?
CallRecordingCapture.shared.stop { result in
    finalResult = result
    semaphore.signal()
}
guard semaphore.wait(timeout: .now() + 10) == .success else {
    throw CallRecordingSelfTestFailure.failed("recording finalization timed out")
}
let finalized = try finalResult!.get()
try expect(FileManager.default.fileExists(atPath: finalized.outputURL.path), "M4A file was not created")
try expect(abs(finalized.duration - 1) < 0.05, "unexpected recording duration")
try expect(!finalized.isIncomplete, "complete PCM input was marked incomplete")

let audioFile = try AVAudioFile(forReading: finalized.outputURL)
try expect(audioFile.fileFormat.channelCount == 2, "recording was not stereo")
try expect(audioFile.length > 0, "recording contained no readable audio frames")

var waveformResult: Result<CallRecordingWaveformData, Error>?
CallRecordingWaveformLoader.shared.load(url: finalized.outputURL, sampleCount: 240) {
    waveformResult = $0
}
let waveformDeadline = Date().addingTimeInterval(10)
while waveformResult == nil, Date() < waveformDeadline {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
guard let waveformResult else {
    throw CallRecordingSelfTestFailure.failed("waveform extraction timed out")
}
let waveform = try waveformResult.get()
try expect(waveform.remote.count == 240, "remote waveform bin count was incorrect")
try expect(waveform.local.count == 240, "local waveform bin count was incorrect")
try expect(waveform.remote.contains(where: { $0 > 0 }), "remote waveform was empty")
try expect(waveform.local.contains(where: { $0 > 0 }), "local waveform was empty")

print("Call recording self-tests passed (stereo M4A finalization and dual-channel waveform).")

// AI uplink is intermittent on UAC. A pause must not move the next answer
// earlier in the recording, or place it over the caller's preceding utterance.
let gapURL = temporaryDirectory.appendingPathComponent("gap.m4a")
try CallRecordingCapture.shared.start(id: UUID(), startedAt: startedAt, outputURL: gapURL)
CallRecordingCapture.shared.appendUplink(localPCM, at: startedAt)
CallRecordingCapture.shared.appendUplink(localPCM, at: startedAt.addingTimeInterval(2))
CallRecordingCapture.shared.appendDownlink(remotePCM, at: startedAt)
let gapSemaphore = DispatchSemaphore(value: 0)
var gapResult: Result<CallRecordingCapture.FinalizedCapture, Error>?
CallRecordingCapture.shared.stop { gapResult = $0; gapSemaphore.signal() }
try expect(gapSemaphore.wait(timeout: .now() + 10) == .success, "gap recording timed out")
let gapCapture = try gapResult!.get()
try expect(abs(gapCapture.duration - 3) < 0.05, "AI pauses were compressed")
let gapFile = try AVAudioFile(forReading: gapURL)
let gapBuffer = AVAudioPCMBuffer(pcmFormat: gapFile.processingFormat, frameCapacity: AVAudioFrameCount(gapFile.length))!
try gapFile.read(into: gapBuffer)
let samples = gapBuffer.floatChannelData![1]
let silenceEnergy = (10_000..<14_000).map { abs(samples[$0]) }.reduce(0, +)
let speechEnergy = (18_000..<22_000).map { abs(samples[$0]) }.reduce(0, +)
try expect(speechEnergy > 20 && silenceEnergy < speechEnergy * 0.02, "recorded AI pause was not silent")
let permissions = try FileManager.default.attributesOfItem(atPath: gapURL.path)[.posixPermissions] as? Int
try expect(permissions == 0o600, "recording permissions were not private")
print("AI recording pause alignment and file privacy tests passed.")
