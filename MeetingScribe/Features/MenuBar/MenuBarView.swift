//
//  MenuBarView.swift
//  MeetingScribe
//

import SwiftUI

@MainActor
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
#if DEBUG
            HStack {
                Text("MeetingScribe")
                    .font(.headline)

                Spacer()

                DevelopmentBuildBadge()
            }

            Divider()
#endif

            WindowPickerView(
                selectedDisplayID: $viewModel.selectedDisplayID,
                selectedWindowID: $viewModel.selectedWindowID,
                displayItems: viewModel.displayItems,
                windowItems: viewModel.windowItems,
                isLoadingContent: viewModel.isLoadingContent
            )
            .disabled(viewModel.isRecording)
            .opacity(viewModel.isRecording ? 0.6 : 1)
            .task {
                viewModel.loadShareableContent()
            }

            Divider()

            if viewModel.isRecording {
                Button(action: { viewModel.stopRecording() }) {
                    Label("録画を終了", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.isShowingMicrophoneChoice {
                MicrophoneRecordingChoiceView(
                    onInclude: {
                        viewModel.confirmRecordingStart(includeMicrophone: true)
                    },
                    onExclude: {
                        viewModel.confirmRecordingStart(includeMicrophone: false)
                    },
                    onCancel: viewModel.cancelRecordingStart
                )
            } else {
                Button(action: { viewModel.startRecording() }) {
                    if viewModel.isPreparingRecording {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("録画を準備中")
                    } else {
                        Label("録画を開始", systemImage: "record.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStartRecording)
                .opacity(viewModel.canStartRecording ? 1 : 0.6)
            }

            if !viewModel.isRecording, !viewModel.isWhisperModelReady {
                Label(
                    "文字起こしモデルをダウンロードしてください。",
                    systemImage: "arrow.down.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !viewModel.isRecording, !viewModel.isSummaryModelSet {
                Label(
                    "要約モデルを設定してください。",
                    systemImage: "text.badge.plus"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !viewModel.isRecording, !viewModel.isOutputDirectorySet {
                VStack(alignment: .leading, spacing: 2) {
                    Text("出力フォルダが未設定です。")
                    Text("設定から出力フォルダを選択してください。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.isOutputDirectorySet, let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if !viewModel.pipelineJobs.isEmpty {
                Divider()

                PipelineJobsView(
                    jobs: viewModel.pipelineJobs,
                    activeCount: viewModel.activePipelineJobCount,
                    waitingCount: viewModel.waitingPipelineJobCount
                )
            }

            if viewModel.isOutputDirectorySet
                || viewModel.isLoadingRecordingHistory
                || !viewModel.recordingHistory.isEmpty {
                Divider()

                RecordingHistoryView(
                    items: viewModel.recordingHistory,
                    isLoading: viewModel.isLoadingRecordingHistory,
                    onReveal: viewModel.revealRecordingInFinder,
                    onRemove: viewModel.removeRecordingHistory
                )
            }

            Divider()

            Button("設定を開く") {
                openSettings()
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 320)
        .padding(12)
    }

    private func openSettings() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}

private struct MicrophoneRecordingChoiceView: View {
    let onInclude: () -> Void
    let onExclude: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "自分の声を録音に含めますか？",
                systemImage: "mic.circle"
            )
            .font(.headline)

            Text(
                "Teamsなどでミュート中でも、「含める」を選ぶと"
                    + "Macのマイク音声は録音されます。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("自分の声を含めて録画", action: onInclude)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("自分の声を含めずに録画", action: onExclude)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("キャンセル", role: .cancel, action: onCancel)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("録画するマイク音声の確認")
    }
}

private struct RecordingHistoryView: View {
    let items: [RecordingHistoryItem]
    let isLoading: Bool
    let onReveal: (RecordingHistoryItem) -> Void
    let onRemove: (RecordingHistoryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("録画履歴", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("録画履歴を読み込み中")
                }
            }

            if items.isEmpty, !isLoading {
                Text("完成した録画はまだありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            HStack(spacing: 4) {
                                Button {
                                    onReveal(item)
                                } label: {
                                    RecordingHistoryRow(item: item)
                                }
                                .buttonStyle(.plain)
                                .disabled(!item.isRecordingAvailable)
                                .accessibilityHint(
                                    item.isRecordingAvailable
                                        ? "Finderで録画ファイルを表示"
                                        : "録画ファイルが見つかりません"
                                )

                                if !item.isRecordingAvailable {
                                    Button(role: .destructive) {
                                        onRemove(item)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        "\(item.title)を履歴から削除"
                                    )
                                    .help("履歴から削除")
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("録画履歴")
    }
}

private struct RecordingHistoryRow: View {
    let item: RecordingHistoryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.recordedAt.formatted(date: .abbreviated, time: .shortened))

                    if !item.isRecordingAvailable {
                        Label(
                            "ファイルなし",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                    }

                    if item.hasTranscript {
                        Label("文字起こし", systemImage: "text.quote")
                    }

                    if item.hasSummary {
                        Label("要約", systemImage: "doc.text")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.right.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .padding(.vertical, 3)
    }
}

private struct PipelineJobsView: View {
    let jobs: [PipelineJob]
    let activeCount: Int
    let waitingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("録画後の処理", systemImage: "list.bullet.rectangle")
                    .font(.headline)

                Spacer()

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(jobs) { job in
                        PipelineJobRow(job: job)
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("録画後の処理")
    }

    private var summaryText: String {
        if waitingCount > 0 {
            return "処理中 \(activeCount)件・待機 \(waitingCount)件"
        }
        if activeCount > 0 {
            return "\(activeCount)件を処理中"
        }
        return "最近の結果"
    }
}

private struct PipelineJobRow: View {
    let job: PipelineJob

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(job.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .fontWeight(.medium)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .waiting, .transcribing, .summarizing, .saving:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch job.status {
        case .waiting:
            "待機中（スリープ・再起動後は自動再開）"
        case .transcribing:
            "文字起こし中"
        case .summarizing:
            "要約中"
        case .saving:
            "ファイルを保存中"
        case .completed(let title):
            "完了：\(title)"
        case .failed(let message):
            "失敗：\(message)"
        }
    }

    private var statusColor: Color {
        if case .failed = job.status {
            return .red
        }
        return .secondary
    }
}

#Preview {
    MenuBarView(viewModel: MenuBarViewModel())
        .frame(width: 320)
}
