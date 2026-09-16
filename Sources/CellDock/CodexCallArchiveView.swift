import AppKit
import SwiftUI

struct CodexCallArchiveView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var archive = CodexCallArchive.shared
    @ObservedObject private var recordings = CallRecordingStore.shared
    @State private var selection: UUID?
    @State private var query = ""
    @State private var deleting: CodexArchivedCall?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI 通话记录").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).adaptiveGlassButton()
            }.padding(20)
            Divider()
            HSplitView {
                VStack {
                    TextField("搜索号码或对话内容", text: $query).communicationSearchField().padding(12)
                    List(selection: $selection) {
                        ForEach(archive.calls.filter { query.isEmpty || $0.number.contains(query) || $0.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) } }) { call in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(appState.privacyPresentation.phoneNumber(call.number)).font(.headline)
                                Text(call.startedAt, style: .date) + Text(" ") + Text(call.startedAt, style: .time)
                                Text(audio(for: call) == nil ? "仅有文字记录" : "录音与文字").foregroundStyle(.secondary)
                            }.font(.caption).padding(.vertical, 5).tag(call.id)
                        }
                    }.scrollContentBackground(.hidden)
                }.frame(minWidth: 220, idealWidth: 260, maxWidth: 310).communicationSidebarColumnStyle()
                ScrollView {
                    if let call = archive.calls.first(where: { $0.id == selection }) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text(appState.privacyPresentation.phoneNumber(call.number)).font(.title2.bold())
                                Spacer()
                                Text(call.direction == "incoming" ? "呼入" : "呼出").foregroundStyle(.secondary)
                            }
                            if let record = audio(for: call) {
                                HStack {
                                    Button(recordings.playingRecordingID == record.id && recordings.isPlaybackPlaying ? "暂停录音" : "播放录音") { recordings.play(record) }
                                    Button("导出录音") { recordings.export(record) }.disabled(appState.isPresentationPrivacyEnabled)
                                    Button("在访达中显示") { recordings.reveal(record) }.disabled(appState.isPresentationPrivacyEnabled)
                                }
                                Text("左声道：对方；右声道：AI。进度、波形和倍速控制在录音库中。")
                                    .font(.caption).foregroundStyle(.secondary)
                                if record.isIncomplete { Text("录音有部分音频未写入。").foregroundStyle(.orange) }
                            } else {
                                Text(call.endedAt == nil ? "通话进行中，录音将在挂断后保存。" : "没有可用的原声录音；文字不能还原当时的声音。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            if call.interrupted { Text("上次会话中断，以下是已保存的内容。").foregroundStyle(.orange) }
                            if let failure = call.failure { Text(verbatim: failure).foregroundStyle(.orange) }
                            if appState.isPresentationPrivacyEnabled {
                                Text("演示隐私保护已隐藏通话文字。")
                            } else {
                                CodexTranscriptContent(call: call)
                                HStack {
                                    Button("导出文字") { export(call) }
                                    Spacer()
                                    Button("删除文字记录", role: .destructive) { deleting = call }.disabled(call.endedAt == nil)
                                }
                            }
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(archive.calls.isEmpty ? "AI 通话结束后，可在这里查看录音和文字。" : "选择一通电话")
                            .foregroundStyle(.secondary).padding(40)
                    }
                }.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity).communicationDetailColumnStyle()
            }.padding(8)
            if let error = archive.lastError ?? recordings.lastError {
                Text(verbatim: error).foregroundStyle(.red).padding(12)
            }
        }
        .background { IDockWindowBackdrop() }
        .adaptiveGlassButton()
        .frame(minWidth: 800, idealWidth: 920, minHeight: 550, idealHeight: 660)
        .onAppear { selection = archive.calls.first?.id }
        .confirmationDialog("删除这通电话的文字记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除文字记录", role: .destructive) { if let call = deleting { archive.delete(call) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("录音仍保留在录音库中，可单独删除。") }
    }

    private func audio(for call: CodexArchivedCall) -> CallRecordingRecord? {
        recordings.records.first { $0.callID == call.id }
    }

    private func export(_ call: CodexArchivedCall) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "AI通话-\(call.number).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "\(call.number) · \(call.startedAt.formatted())\n文字为自动转写，可能有误；请以录音为准。\n\n" + call.transcript.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] \($0.role == "assistant" ? "AI" : "对方")：\($0.text)"
        }.joined(separator: "\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { NSAlert(error: error).runModal() }
    }
}

struct CodexTranscriptContent: View {
    let call: CodexArchivedCall
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("通话文字").font(.headline)
            Text("自动转写可能有误，也可能包含被打断的 AI 回答，请以原声录音为准。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(call.transcript) { line in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(line.role == "assistant" ? "AI 助理" : "对方").fontWeight(.semibold)
                        Text(line.timestamp, style: .time).foregroundStyle(.secondary)
                    }.font(.caption)
                    Text(verbatim: line.text).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(line.role == "assistant" ? Color.accentColor.opacity(0.07) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            if call.transcript.isEmpty { Text("暂无已完成的转写。").foregroundStyle(.secondary) }
        }
    }
}
