import Foundation

@main
struct ArchiveTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("call-archive-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = CodexCallArchive(directory: root)
        let first = UUID(), second = UUID()
        archive.begin(id: first, number: "test-incoming", direction: "incoming", recordingRequested: true)
        archive.append(callID: first, role: "caller", text: "第一通的内容")
        archive.finish(callID: first)
        archive.begin(id: second, number: "test-outgoing", direction: "outgoing", recordingRequested: false, ownerTask: "仅询问明天下午三点的会议安排")
        archive.append(callID: second, role: "assistant", text: "第二通的内容")
        archive.recordFailure(callID: second, message: "simulated failure")
        // Simulate process death: reload before the second call is finished.
        let reloaded = CodexCallArchive(directory: root)
        precondition(reloaded.calls.count == 2)
        let finished = reloaded.calls.first { $0.id == first }!
        let recovered = reloaded.calls.first { $0.id == second }!
        precondition(!finished.interrupted && finished.transcript.count == 1)
        precondition(finished.transcript[0].text == "第一通的内容")
        precondition(recovered.interrupted && recovered.endedAt != nil)
        precondition(finished.ownerTask == nil && recovered.ownerTask == "仅询问明天下午三点的会议安排")
        precondition(recovered.transcript[0].text == "第二通的内容" && recovered.failure == "simulated failure")
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int
        let filePermissions = try FileManager.default.attributesOfItem(atPath: reloaded.fileURL(for: recovered).path)[.posixPermissions] as? Int
        precondition(directoryPermissions == 0o700 && filePermissions == 0o600)
        reloaded.delete(finished)
        let afterDeletion = CodexCallArchive(directory: root)
        precondition(afterDeletion.calls.count == 1 && afterDeletion.calls[0].id == second)
        let bad = root.appendingPathComponent(UUID().uuidString + ".json")
        try Data("invalid json".utf8).write(to: bad)
        let damaged = CodexCallArchive(directory: root)
        precondition(damaged.calls.count == 1 && damaged.lastError != nil)
        let blockedRoot = root.appendingPathComponent("file-not-directory")
        try Data().write(to: blockedRoot)
        let blocked = CodexCallArchive(directory: blockedRoot)
        blocked.begin(id: UUID(), number: "test", direction: "incoming", recordingRequested: true)
        precondition(blocked.lastError != nil)
        print("Call archive tests passed: incremental persistence, restart recovery, call isolation, privacy, deletion, corrupt file and disk failure.")
    }
}
