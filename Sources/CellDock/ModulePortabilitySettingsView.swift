import SwiftUI

struct ModulePortabilitySettingsView: View {
    @ObservedObject var appState: AppState
    private var enabled: Bool { appState.modem.usbConfiguration?.isCellDockPortableTarget == true }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: enabled ? "自动切换已启用" : "当前为 Mac 固定模式")
                Text(verbatim: "一次开启后，模块默认提供手机网络；连接此 Mac 时，CellDock 自动恢复电话和短信能力。切换时模块会短暂重连。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(verbatim: "iPhone 需要支持 USB 网卡的连接方式和足够供电。此模块的 iPhone 实际兼容性仍需拔插验收。")
                    .font(.caption).foregroundStyle(.secondary)
                if enabled {
                    Text(verbatim: appState.modem.portableMacAudioReady ? "Mac 声卡已自动恢复" : "等待 Mac 声卡恢复")
                        .font(.caption)
                }
                Button(action: { appState.configurePortability(enabled: !enabled) }) {
                    Text(verbatim: enabled ? "恢复 Mac 固定模式" : "开启 Mac / iPhone 自动切换")
                }
                .disabled(appState.modem.state != .connected || appState.isConfiguringECM || appState.call.hasCall ||
                          appState.modem.hardwareFamily != .baiwangInjectedVoice ||
                          !ModulePortabilityPolicy.supports(firmware: appState.modem.firmwareVersion))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: { Label("Mac / iPhone", systemImage: "cable.connector") }
    }
}
