//
//  MenuBarView.swift
//  MeetingScribe
//

import SwiftUI

@MainActor
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
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
            }

            if let message = viewModel.errorMessage {
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
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings", value: "main")
    }
}

#Preview {
    MenuBarView(viewModel: MenuBarViewModel())
        .frame(width: 280)
}
