//
//  MenuBarView.swift
//  MeetingScribe
//

import SwiftUI

@MainActor
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowPickerView(
                selectedDisplayID: $viewModel.selectedDisplayID,
                selectedWindowID: $viewModel.selectedWindowID
            )

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
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}

#Preview {
    MenuBarView()
        .frame(width: 280)
}
