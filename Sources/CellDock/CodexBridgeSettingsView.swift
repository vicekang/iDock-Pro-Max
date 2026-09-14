import SwiftUI

struct CodexBridgeSettingsView: View {
    @ObservedObject var bridge: CodexPhoneBridge
    @State private var showsArchive = false
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: bridge.status).font(.callout).foregroundStyle(.secondary)
                Toggle("Codex 自动接听来电", isOn: Binding(get: { bridge.autoAnswer }, set: bridge.setAutoAnswer))
                CodexBackgroundStatusView(background: bridge.background)
                Toggle("自动保存 AI 通话录音", isOn: Binding(get: { bridge.recordAICalls }, set: bridge.setRecordAICalls))
                Text("从下一通 AI 电话生效。录音开启时会在开场告知对方；双向原声和逐句文字保存在此 Mac。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("查看通话记录与录音") { showsArchive = true }
                Text("使用已登录 Codex 的原生实时语音接听和回答，支持打断。单次通话默认最长 10 分钟。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("测试 Codex 原生语音") { bridge.testVoice() }
                Divider()
                CodexOpeningSettingsView(opening: bridge.openingAudio, bridge: bridge)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: { Label("Codex 电话助理", systemImage: "phone.badge.waveform") }
        .sheet(isPresented: $showsArchive) { CodexCallArchiveView() }
    }
}

private struct CodexOpeningSettingsView: View {
    @ObservedObject var opening: CodexOpeningAudio
    @ObservedObject var bridge: CodexPhoneBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("接通后先播放本地开场白", isOn: Binding(get: { opening.enabled }, set: opening.setEnabled))
            Text(verbatim: opening.displayName).font(.callout)
            Text("来电时提前准备 AI，通话音频就绪后先播放本机录音，再由 AI 听取并回应对方。提前生成的回复会等开场白结束再播放。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(opening.importing ? "正在导入…" : "导入我的录音") { opening.chooseFile() }
                    .disabled(opening.importing)
                Button("试听 / 停止") { opening.preview(recording: bridge.recordAICalls) }
                    .disabled(!opening.enabled)
                if opening.customName != nil { Button("使用默认开场白") { opening.useDefault() } }
            }
            if opening.customName != nil {
                TextField("开场白文字（可选，帮助 AI 理解已说内容）", text: Binding(
                    get: { opening.customText }, set: { opening.customText = $0 }), axis: .vertical)
                    .lineLimit(2...4)
                Toggle("我的录音已包含录音告知", isOn: Binding(
                    get: { opening.customIncludesRecordingNotice }, set: { opening.customIncludesRecordingNotice = $0 }))
            }
            Text("支持 WAV、M4A、MP3 等音频，建议 3–8 秒。录音开启时会自动补充录音告知；勾选“已包含”可避免重复。更改从下一通电话生效。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = opening.lastError { Text(verbatim: error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

private struct CodexBackgroundStatusView: View {
    @ObservedObject var background: CodexPhoneBackground
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(background.mode == .off ? "后台值守未启用" : "后台值守中 · 允许锁屏和熄屏",
                  systemImage: background.mode == .off ? "moon" : "phone.badge.waveform")
            Text("自动接听开启且模组连接时保持 Mac 唤醒，会增加电池耗电。合盖导致睡眠、手动睡眠或关机期间无法接听。")
            if let error = background.lastError { Text(verbatim: error).foregroundStyle(.orange) }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
