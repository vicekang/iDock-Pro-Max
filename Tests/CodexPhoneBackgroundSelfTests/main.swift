import AppKit
import Foundation

@main struct BackgroundTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phone-background-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var begins: [ProcessInfo.ActivityOptions] = []
        var ends = 0
        let service = CodexPhoneBackground(fileURL: root.appendingPathComponent("state.json"),
            beginActivity: { options, _ in begins.append(options); return NSObject() },
            endActivity: { _ in ends += 1 })
        precondition(CodexPhoneBackgroundMode.desired(running: false, autoAnswer: true, modulePresent: true,
                                                     callActive: true, diagnosticActive: true) == .off)
        precondition(CodexPhoneBackgroundMode.desired(running: true, autoAnswer: true, modulePresent: false,
                                                     callActive: false, diagnosticActive: false) == .off)
        service.update(.desired(running: true, autoAnswer: true, modulePresent: true,
                                callActive: false, diagnosticActive: false))
        service.update(.standby)
        precondition(begins.count == 1 && ends == 0)
        precondition(begins[0].contains(.idleSystemSleepDisabled))
        precondition(!begins[0].contains(.idleDisplaySleepDisabled) && !begins[0].contains(.latencyCritical))
        service.update(.call)
        precondition(begins.count == 2 && ends == 1 && begins[1].contains(.latencyCritical))
        service.update(.desired(running: true, autoAnswer: false, modulePresent: true,
                                callActive: true, diagnosticActive: false))
        precondition(service.mode == .call && begins.count == 2)
        service.update(.off)
        precondition(ends == 2 && service.snapshot["activityHeld"] as? Bool == false)
        service.tick(modulePresent: true, callPhase: "idle", uptime: 100)
        service.tick(modulePresent: true, callPhase: "incoming", uptime: 104)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("state.json"))) as! [String: Any]
        precondition(saved["largestPollGapSeconds"] as? Double == 4)
        let events = saved["events"] as! [[String: Any]]
        precondition(events.contains { $0["type"] as? String == "poll.delayed" })
        precondition(events.contains { $0["type"] as? String == "call.incoming" })
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("state.json").path)
        precondition(attrs[.posixPermissions] as? Int == 0o600)

        // Validate that the real Foundation activity registers an OS assertion,
        // and that stopping releases it. This does not keep the display awake.
        func assertions() throws -> String {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "assertions"]; process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let real = CodexPhoneBackground(fileURL: root.appendingPathComponent("actual.json"))
        real.update(.standby)
        let held = try assertions()
        let pidMarker = "pid \(ProcessInfo.processInfo.processIdentifier)("
        precondition(held.split(separator: "\n").contains { $0.contains(pidMarker) && $0.contains("CellDock automatic telephone answering") })
        real.stop()
        let released = try assertions()
        precondition(!released.split(separator: "\n").contains { $0.contains(pidMarker) && $0.contains("CellDock automatic telephone answering") })
        print("Phone background tests passed: scoped sleep assertion, release on stop/disconnect, call priority, display sleep allowed, durable heartbeat diagnostics.")
    }
}
