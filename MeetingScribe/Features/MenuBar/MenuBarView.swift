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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                statusIcon
                    .frame(width: 16, height: 16)

                Text("\(job.createdAt.formatted(date: .omitted, time: .shortened)) の録画")
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer(minLength: 0)

                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: .capsule)
            }

            if isProcessing {
                PipelineStageIndicator(status: job.status)

                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        "\(elapsedText(at: context.date))・バックグラウンドで動作中",
                        systemImage: "clock"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            } else if case .waiting = job.status {
                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .completed(let title) = job.status {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if case .failed(let message) = job.status {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.65), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .waiting:
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        case .transcribing, .summarizing, .saving:
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

    private var isProcessing: Bool {
        switch job.status {
        case .transcribing, .summarizing, .saving:
            true
        case .waiting, .completed, .failed:
            false
        }
    }

    private var statusText: String {
        switch job.status {
        case .waiting:
            "再開待ち"
        case .transcribing:
            "工程 1/3"
        case .summarizing:
            "工程 2/3"
        case .saving:
            "工程 3/3"
        case .completed:
            "完了"
        case .failed:
            "失敗"
        }
    }

    private var statusDetail: String {
        switch job.status {
        case .waiting:
            "スリープ・再起動後も自動的に処理を再開します。"
        case .transcribing:
            "録画音声を解析して文字起こししています。"
        case .summarizing:
            "文字起こしから会議内容を整理して要約しています。"
        case .saving:
            "録画・文字起こし・要約を完成ファイルとして保存しています。"
        case .completed:
            "すべての処理が完了しました。"
        case .failed:
            "録画後の処理に失敗しました。"
        }
    }

    private var statusColor: Color {
        if case .failed = job.status {
            return .red
        }
        return .secondary
    }

    private func elapsedText(at date: Date) -> String {
        let elapsed = max(
            0,
            Int(date.timeIntervalSince(job.statusUpdatedAt))
        )
        let hours = elapsed / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return "この工程を \(hours)時間\(minutes)分処理中"
        }
        if minutes > 0 {
            return "この工程を \(minutes)分\(seconds)秒処理中"
        }
        return "この工程を \(seconds)秒処理中"
    }
}

private struct PipelineStageIndicator: View {
    let status: PipelineJobStatus

    var body: some View {
        HStack(spacing: 5) {
            PipelineStageView(
                title: "文字起こし",
                state: state(for: 0)
            )
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            PipelineStageView(
                title: "要約",
                state: state(for: 1)
            )
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            PipelineStageView(
                title: "保存",
                state: state(for: 2)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityProgressLabel)
    }

    private var currentStageIndex: Int? {
        switch status {
        case .transcribing:
            0
        case .summarizing:
            1
        case .saving:
            2
        case .waiting, .completed, .failed:
            nil
        }
    }

    private func state(for stageIndex: Int) -> PipelineStageState {
        if case .completed = status {
            return .completed
        }
        guard let currentStageIndex else {
            return .pending
        }
        if stageIndex < currentStageIndex {
            return .completed
        }
        if stageIndex == currentStageIndex {
            return .active
        }
        return .pending
    }

    private var accessibilityProgressLabel: String {
        switch status {
        case .waiting:
            "録画後処理は再開待ちです"
        case .transcribing:
            "全3工程中1番目、文字起こしを実行中"
        case .summarizing:
            "全3工程中2番目、文字起こし完了、要約を実行中"
        case .saving:
            "全3工程中3番目、文字起こしと要約が完了、保存中"
        case .completed:
            "録画後処理の全3工程が完了"
        case .failed:
            "録画後処理に失敗"
        }
    }
}

private enum PipelineStageState: Equatable {
    case pending
    case active
    case completed
}

private struct PipelineStageView: View {
    let title: String
    let state: PipelineStageState

    var body: some View {
        HStack(spacing: 4) {
            stageIcon
                .frame(width: 12, height: 12)

            Text(title)
                .font(.caption2)
                .fontWeight(state == .active ? .semibold : .regular)
                .foregroundStyle(state == .pending ? .tertiary : .primary)
        }
    }

    @ViewBuilder
    private var stageIcon: some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    MenuBarView(viewModel: MenuBarViewModel())
        .frame(width: 320)
}
