import SwiftUI

struct CodexBridgeSettingsView: View {
    @ObservedObject var bridge: CodexPhoneBridge
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: bridge.status).font(.callout).foregroundStyle(.secondary)
                Toggle("Codex 自动接听来电", isOn: Binding(get: { bridge.autoAnswer }, set: bridge.setAutoAnswer))
                Text("使用已登录 Codex 的原生实时语音接听和回答，支持打断。单次通话默认最长 10 分钟。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("测试 Codex 原生语音") { bridge.testVoice() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: { Label("Codex 电话助理", systemImage: "phone.badge.waveform") }
    }
}
