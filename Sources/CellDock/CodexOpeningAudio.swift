import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

struct CodexOpeningClip {
    let pcm: Data
    let name: String
    let text: String
    var duration: Double { Double(pcm.count) / 16_000 }
}

enum CodexOpeningDecoder {
    static func decode(_ url: URL, maximumDuration: Double = 20) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 25_000_000 else { throw CodexBridgeError("请选择小于 25 MB 的音频文件。") }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration >= 0.3, duration <= maximumDuration, format.channelCount <= 8,
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(duration * 8_000)) + 1_024) else {
            throw CodexBridgeError("开场录音需要 0.3–20 秒，建议 3–8 秒。")
        }
        try file.read(into: input)
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error, let values = output.floatChannelData?[0], output.frameLength > 0 else {
            throw CodexBridgeError("无法转换这段录音，请尝试 WAV、M4A 或 MP3。")
        }
        let samples = (0..<Int(output.frameLength)).map { values[$0].isFinite ? values[$0] : 0 }
        guard let first = samples.firstIndex(where: { abs($0) > 0.004 }),
              let last = samples.lastIndex(where: { abs($0) > 0.004 }) else {
            throw CodexBridgeError("录音中没有检测到可听声音。")
        }
        let start = max(0, first - 320), end = min(samples.count, last + 321)
        let peak = samples[start..<end].map { abs($0) }.max() ?? 1
        let gain = min(2, 0.85 / max(peak, 0.001))
        // A short preroll protects the first syllable from UAC's activation flush.
        var pcm = Data(repeating: 0, count: 640)
        for value in samples[start..<end] {
            var sample = Int16(max(-1, min(1, value * gain)) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        pcm.append(Data(repeating: 0, count: 640))
        return pcm
    }

    static func wave(_ pcm: Data) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + pcm.count)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(8_000))
        number(UInt32(16_000)); number(UInt16(2)); number(UInt16(16)); text("data")
        number(UInt32(pcm.count)); data.append(pcm); return data
    }
}

@MainActor
final class CodexOpeningAudio: ObservableObject {
    static let defaultText = "您好，我是机主的 AI 电话助理。请问有什么可以帮您转达？"
    @Published private(set) var enabled: Bool
    @Published private(set) var customName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var importing = false
    private var customPCM: Data?
    private var defaultPCM: Data?
    private var noticePCM: Data?
    private var player: AVAudioPlayer?
    private let directory: URL
    private let defaults: UserDefaults

    init(directory: URL, defaults: UserDefaults = .standard, resources: URL? = Bundle.main.resourceURL) {
        self.directory = directory; self.defaults = defaults
        enabled = defaults.object(forKey: "codexBridge.openingEnabled") as? Bool ?? true
        if let resources {
            defaultPCM = try? CodexOpeningDecoder.decode(resources.appendingPathComponent("CallOpening/greeting.wav"))
            noticePCM = try? CodexOpeningDecoder.decode(resources.appendingPathComponent("CallOpening/recording-notice.wav"))
        }
        let custom = directory.appendingPathComponent("custom.wav")
        if FileManager.default.fileExists(atPath: custom.path) {
            // The private copy can include 80 ms of padding beyond the imported 20 s limit.
            do { customPCM = try CodexOpeningDecoder.decode(custom, maximumDuration: 21); customName = "我的开场录音" }
            catch { lastError = "自定义录音无法读取，将使用默认开场白。" }
        }
    }
    var customText: String {
        get { defaults.string(forKey: "codexBridge.openingText") ?? "" }
        set { objectWillChange.send(); defaults.set(String(newValue.prefix(2_000)), forKey: "codexBridge.openingText") }
    }
    var customIncludesRecordingNotice: Bool {
        get { defaults.bool(forKey: "codexBridge.openingIncludesRecordingNotice") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "codexBridge.openingIncludesRecordingNotice") }
    }
    var displayName: String { customName ?? "默认中文开场白" }
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: "codexBridge.openingEnabled")
    }
    func clip(recording: Bool) -> CodexOpeningClip? {
        guard enabled, let greeting = customPCM ?? defaultPCM else { return nil }
        let needsNotice = recording && !(customPCM != nil && customIncludesRecordingNotice)
        // If the required notice is unavailable, use the existing AI greeting.
        if needsNotice && noticePCM == nil { return nil }
        let pcm = (needsNotice ? noticePCM ?? Data() : Data()) + greeting
        let text = (needsNotice ? "本次通话会录音并保存文字。" : "") +
            (customPCM == nil ? Self.defaultText : customText)
        return CodexOpeningClip(pcm: pcm, name: displayName, text: text)
    }
    func chooseFile() {
        guard !importing else { return }
        let panel = NSOpenPanel()
        panel.title = "选择接通后播放的开场录音"
        panel.message = "建议 3–8 秒，包含 AI 助理身份和询问来意。音频会保存到本机，原文件可以移动。"
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.importFile(url) }
        }
    }
    func importFile(_ url: URL) {
        guard !importing else { return }
        importing = true; lastError = nil
        Task {
            do {
                let pcm = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try CodexOpeningDecoder.decode(url)
                }.value
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let destination = directory.appendingPathComponent("custom.wav")
                try CodexOpeningDecoder.wave(pcm).write(to: destination, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                customPCM = pcm; customName = "我的开场录音"
                customText = ""; customIncludesRecordingNotice = false; setEnabled(true)
            } catch { lastError = error.localizedDescription }
            importing = false
        }
    }
    func useDefault() {
        player?.stop()
        do {
            let url = directory.appendingPathComponent("custom.wav")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            customPCM = nil; customName = nil; customText = ""; customIncludesRecordingNotice = false
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }
    func preview(recording: Bool) {
        if player?.isPlaying == true { player?.stop(); return }
        guard let clip = clip(recording: recording) else { lastError = "没有可用的开场音频。"; return }
        do {
            player = try AVAudioPlayer(data: CodexOpeningDecoder.wave(clip.pcm))
            player?.prepareToPlay(); player?.play(); lastError = nil
        } catch { lastError = error.localizedDescription }
    }
    func stopPreview() { player?.stop() }
}
