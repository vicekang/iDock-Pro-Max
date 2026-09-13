import SwiftUI

struct CodexBridgeSettingsView: View {
    @ObservedObject var bridge: CodexPhoneBridge
    @State private var showsArchive = false
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: bridge.status).font(.callout).foregroundStyle(.secondary)
                Toggle("Codex 自动接听来电", isOn: Binding(get: { bridge.autoAnswer }, set: bridge.setAutoAnswer))
                Toggle("自动保存 AI 通话录音", isOn: Binding(get: { bridge.recordAICalls }, set: bridge.setRecordAICalls))
                Text("从下一通 AI 电话生效。录音开启时会在开场告知对方；双向原声和逐句文字保存在此 Mac。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("查看通话记录与录音") { showsArchive = true }
                Text("使用已登录 Codex 的原生实时语音接听和回答，支持打断。单次通话默认最长 10 分钟。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("测试 Codex 原生语音") { bridge.testVoice() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: { Label("Codex 电话助理", systemImage: "phone.badge.waveform") }
        .sheet(isPresented: $showsArchive) { CodexCallArchiveView() }
    }
}
