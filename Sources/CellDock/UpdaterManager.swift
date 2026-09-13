import AppKit
import Combine
import Foundation
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    static let defaultsKey = "CellDockUpdateChannel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: return L10n.tr("稳定版")
        case .beta: return L10n.tr("测试版")
        }
    }

    fileprivate var feedURL: String {
        "https://celldock.app/\(rawValue)/appcast.xml"
    }
}

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    private var controller: SPUStandardUpdaterController!

    @Published private(set) var canCheckForUpdates = false
    @Published var channel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: UpdateChannel.defaultsKey)
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
        return L10n.tr("版本 %@（构建 %@）", version, build)
    }

    private override init() {
        let storedChannel = UserDefaults.standard.string(forKey: UpdateChannel.defaultsKey)
        channel = UpdateChannel(rawValue: storedChannel ?? "") ?? .stable
        super.init()

        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "CellDockCodexBridge") as? Bool != true else { return }
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        guard Bundle.main.object(forInfoDictionaryKey: "CellDockCodexBridge") as? Bool != true else { return }
        #if !DEBUG
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { channel.feedURL }
    }
}
