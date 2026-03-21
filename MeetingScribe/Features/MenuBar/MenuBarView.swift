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
            } else {
                Button(action: { viewModel.startRecording() }) {
                    Label("録画を開始", systemImage: "record.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isOutputDirectorySet)
                .opacity(viewModel.isOutputDirectorySet ? 1 : 0.6)
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

            switch viewModel.pipelineStatus {
            case .idle:
                if viewModel.isOutputDirectorySet, let message = viewModel.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            case .transcribing, .summarizing:
                Text("文字起こし・要約中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed:
                Text("処理が完了しました")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            Button("設定を開く") {
                openSettings()
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 280)
        .padding(12)
    }

    private func openSettings() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings", value: "main")
    }
}

#Preview {
    MenuBarView(viewModel: MenuBarViewModel())
        .frame(width: 280)
}
