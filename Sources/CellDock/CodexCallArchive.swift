import Combine
import Foundation

struct CodexCallTranscript: Identifiable, Codable, Equatable {
    var id = UUID()
    let timestamp: Date
    let role: String
    let text: String
}

struct CodexArchivedCall: Identifiable, Codable, Equatable {
    let id: UUID
    let number: String
    let direction: String
    let startedAt: Date
    var endedAt: Date?
    var interrupted = false
    var recordingRequested: Bool
    var failure: String?
    var ownerTask: String?
    var transcript: [CodexCallTranscript] = []
}

/// One atomic, private file per call. Transcript events are saved as they arrive,
/// independent of the rolling RPC event buffer and the audio encoder.
@MainActor
final class CodexCallArchive: ObservableObject {
    static let shared = CodexCallArchive(directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CellDock/CodexBridge/Calls", isDirectory: true))

    @Published private(set) var calls: [CodexArchivedCall] = []
    @Published private(set) var lastError: String?
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.pathExtension == "json" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil {
                do {
                    var call = try decoder.decode(CodexArchivedCall.self, from: Data(contentsOf: url))
                    guard url.lastPathComponent == call.id.uuidString + ".json" else { continue }
                    if call.endedAt == nil {
                        call.interrupted = true
                        call.endedAt = call.transcript.last?.timestamp ?? call.startedAt
                        persist(call)
                    }
                    calls.append(call)
                } catch { lastError = "部分通话文字记录无法读取：\(error.localizedDescription)" }
            }
            calls.sort { $0.startedAt > $1.startedAt }
        } catch { lastError = "无法打开通话文字记录：\(error.localizedDescription)" }
    }

    func begin(id: UUID, number: String, direction: String, recordingRequested: Bool, ownerTask: String? = nil, at date: Date = Date()) {
        guard !calls.contains(where: { $0.id == id }) else { return }
        let call = CodexArchivedCall(id: id, number: number, direction: direction, startedAt: date,
                                    recordingRequested: recordingRequested, ownerTask: ownerTask)
        calls.insert(call, at: 0); persist(call)
    }

    func append(callID: UUID, role: String, text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = calls.firstIndex(where: { $0.id == callID }) else { return }
        calls[index].transcript.append(CodexCallTranscript(timestamp: date, role: role, text: text))
        persist(calls[index])
    }

    func recordFailure(callID: UUID, message: String) {
        guard let index = calls.firstIndex(where: { $0.id == callID }) else { return }
        calls[index].failure = message; persist(calls[index])
    }

    func finish(callID: UUID, interrupted: Bool = false, at date: Date = Date()) {
        guard let index = calls.firstIndex(where: { $0.id == callID }) else { return }
        calls[index].endedAt = date; calls[index].interrupted = interrupted
        persist(calls[index])
    }

    func fileURL(for call: CodexArchivedCall) -> URL {
        directory.appendingPathComponent(call.id.uuidString + ".json")
    }

    func delete(_ call: CodexArchivedCall) {
        guard call.endedAt != nil else { return }
        do {
            try FileManager.default.removeItem(at: fileURL(for: call))
            calls.removeAll { $0.id == call.id }
        } catch { lastError = "无法删除文字记录：\(error.localizedDescription)" }
    }

    private func persist(_ call: CodexArchivedCall) {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = fileURL(for: call)
            try encoder.encode(call).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastError = nil
        } catch { lastError = "文字记录保存失败：\(error.localizedDescription)" }
    }
}
