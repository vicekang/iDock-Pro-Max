import AppKit
import Combine
import Foundation

enum CodexPhoneBackgroundMode: String {
    case off, standby, call

    static func desired(running: Bool, autoAnswer: Bool, modulePresent: Bool,
                        callActive: Bool, diagnosticActive: Bool) -> Self {
        guard running else { return .off }
        if callActive || diagnosticActive { return .call }
        return autoAnswer && modulePresent ? .standby : .off
    }

    var options: ProcessInfo.ActivityOptions {
        switch self {
        case .off: return []
        case .standby: return [.userInitiated]
        case .call: return [.userInitiated, .latencyCritical]
        }
    }
}

/// A scoped activity, released when auto-answer stops, the module is removed,
/// or the bridge exits. Does not change pmset, disable screen locking, keep the
/// display on, or override lid-close / explicit system sleep.
@MainActor
final class CodexPhoneBackground: ObservableObject {
    @Published private(set) var mode: CodexPhoneBackgroundMode = .off
    @Published private(set) var lastError: String?
    var onWake: (() -> Void)?
    private var activity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var lastPollUptime: TimeInterval?
    private var lastSaveUptime: TimeInterval = 0
    private var largestPollGap: TimeInterval = 0
    private var recentEvents: [[String: Any]] = []
    private var modulePresent: Bool?
    private var callPhase = ""
    private var radioState: [String: String] = [:]
    private let fileURL: URL
    private let beginActivity: (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
    private let endActivity: (NSObjectProtocol) -> Void

    init(fileURL: URL,
         beginActivity: @escaping (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol = {
             ProcessInfo.processInfo.beginActivity(options: $0, reason: $1)
         },
         endActivity: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        self.fileURL = fileURL; self.beginActivity = beginActivity; self.endActivity = endActivity
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            recentEvents = Array((saved["events"] as? [[String: Any]] ?? []).suffix(100))
        }
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for (name, kind) in [(NSWorkspace.willSleepNotification, "system.willSleep"),
                             (NSWorkspace.didWakeNotification, "system.didWake"),
                             (NSWorkspace.screensDidSleepNotification, "display.didSleep"),
                             (NSWorkspace.screensDidWakeNotification, "display.didWake"),
                             (NSWorkspace.sessionDidResignActiveNotification, "session.inactive"),
                             (NSWorkspace.sessionDidBecomeActiveNotification, "session.active")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.note(kind)
                    if name == NSWorkspace.didWakeNotification { self?.onWake?() }
                }
            })
        }
        note("bridge.started")
    }

    func update(_ next: CodexPhoneBackgroundMode) {
        guard next != mode else { return }
        // Acquire before releasing so standby-to-call transitions have no gap.
        let previous = activity
        activity = next == .off ? nil : beginActivity(next.options,
            next == .call ? "CellDock AI telephone audio" : "CellDock automatic telephone answering")
        if let previous { endActivity(previous) }
        mode = next; note("activity.\(next.rawValue)")
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll(); update(.off); note("bridge.stopped")
    }

    func tick(modulePresent: Bool, callPhase: String, radioState: [String: String] = [:],
              uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let lastPollUptime {
            let gap = max(0, uptime - lastPollUptime)
            largestPollGap = max(largestPollGap, gap)
            if gap >= 3 { note("poll.delayed", details: ["seconds": gap]) }
        }
        lastPollUptime = uptime
        if self.modulePresent != modulePresent {
            self.modulePresent = modulePresent
            note(modulePresent ? "module.present" : "module.absent")
        }
        if self.callPhase != callPhase { self.callPhase = callPhase; note("call.\(callPhase)") }
        if self.radioState != radioState { self.radioState = radioState; note("radio.changed", details: ["state": radioState]) }
        if uptime - lastSaveUptime >= 15 { lastSaveUptime = uptime; save() }
    }

    func note(_ kind: String, details: [String: Any] = [:]) {
        var event = details; event["type"] = kind; event["timestamp"] = Date().timeIntervalSince1970
        recentEvents.append(event)
        if recentEvents.count > 100 { recentEvents.removeFirst(recentEvents.count - 100) }
        save()
    }

    var snapshot: [String: Any] {
        ["mode": mode.rawValue, "activityHeld": activity != nil, "allowsDisplaySleep": true,
         "modulePresent": modulePresent ?? false, "callPhase": callPhase,
         "radio": radioState,
         "largestPollGapSeconds": largestPollGap, "updatedAt": Date().timeIntervalSince1970,
         "events": recentEvents, "error": lastError ?? ""]
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            if lastError != nil { lastError = nil }
        } catch { lastError = "后台诊断保存失败：\(error.localizedDescription)" }
    }
}
