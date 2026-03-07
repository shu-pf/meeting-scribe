//
//  SettingsView.swift
//  MeetingScribe
//

import SwiftUI
import AppKit

@MainActor
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel(
        whisperModelStore: WhisperModelStore.shared,
        summaryService: SummaryService()
    )
    @State private var whisperDownloader = WhisperModelDownloader()

    var body: some View {
        Form {
            Section("出力") {
                HStack {
                    TextField("出力フォルダ", text: $viewModel.outputDirectoryPath)
                        .disabled(true)
                    Button("選択") {
                        openOutputFolderPicker()
                    }
                    if !viewModel.outputDirectoryPath.isEmpty {
                        Button("クリア") {
                            Task { await viewModel.clearOutputDirectory() }
                        }
                    }
                }
            }
            Section("文字起こし（Whisper）") {
                Picker("モデル", selection: Binding(
                    get: { viewModel.selectedWhisperModelID },
                    set: { new in Task { await viewModel.setSelectedWhisperModelID(new) } }
                )) {
                    Text("未選択").tag("")
                    ForEach(viewModel.whisperModelIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Button("モデルを追加") {
                    viewModel.showWhisperModelDownloadSheet = true
                }
            }
            Section("要約（LLM）") {
                Picker("モデル", selection: Binding(
                    get: { viewModel.selectedSummaryModelID },
                    set: { new in Task { await viewModel.setSelectedSummaryModelID(new) } }
                )) {
                    Text("未選択").tag("")
                    ForEach(viewModel.summaryModelIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
            }
            Section("起動") {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { new in Task { await viewModel.setLaunchAtLogin(new) } }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 320)
        .task {
            await viewModel.load()
            if await viewModel.shouldShowWhisperModelDownloadSheet() {
                viewModel.showWhisperModelDownloadSheet = true
            }
        }
        .sheet(isPresented: $viewModel.showWhisperModelDownloadSheet) {
            WhisperModelDownloadView(
                onComplete: { modelID in
                    Task {
                        await viewModel.setSelectedWhisperModelID(modelID)
                        await viewModel.load()
                    }
                },
                store: WhisperModelStore.shared,
                downloader: whisperDownloader
            )
        }
    }

    private func openOutputFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await viewModel.setOutputDirectory(url) }
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 450, height: 400)
}
