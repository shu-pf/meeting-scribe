//
//  SettingsView.swift
//  MeetingScribe
//

import SwiftUI
import AppKit

private struct ContextLengthPreset {
    let label: String
    let value: Int
}

@MainActor
struct SettingsView: View {
    /// ガイダンスを閉じたあと、Whisper モデル未設定ならダウンロード画面を出すためのトリガー（ContentView から渡す）
    @Binding var triggerWhisperSheetAfterGuidance: Bool

    private static let contextLengthPresets: [ContextLengthPreset] = [
        ContextLengthPreset(label: "4K", value: 4_096),
        ContextLengthPreset(label: "8K", value: 8_192),
        ContextLengthPreset(label: "16K", value: 16_384),
        ContextLengthPreset(label: "32K", value: 32_768),
        ContextLengthPreset(label: "64K", value: 65_536),
        ContextLengthPreset(label: "128K", value: 131_072),
        ContextLengthPreset(label: "256K", value: 262_144)
    ]

    @StateObject private var viewModel = SettingsViewModel(
        whisperModelStore: WhisperModelStore.shared,
        summaryService: SummaryService()
    )
    @State private var whisperDownloader = WhisperModelDownloader()
    private let settings = SettingsService()

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
                    ForEach(viewModel.summaryModelPickerIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Picker("最大コンテキスト", selection: Binding(
                    get: { viewModel.summaryContextLength },
                    set: { new in Task { await viewModel.setSummaryContextLength(new) } }
                )) {
                    ForEach(Self.contextLengthPresets, id: \.value) { preset in
                        Text(preset.label).tag(preset.value)
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
        .frame(minWidth: 400, minHeight: 440)
        .task {
            await viewModel.load()
            if await settings.hasSeenFirstLaunchGuidance,
               await viewModel.shouldShowWhisperModelDownloadSheet() {
                viewModel.showWhisperModelDownloadSheet = true
            }
        }
        .onChange(of: triggerWhisperSheetAfterGuidance) { _, newValue in
            guard newValue else { return }
            Task {
                await viewModel.load()
                if await viewModel.shouldShowWhisperModelDownloadSheet() {
                    viewModel.showWhisperModelDownloadSheet = true
                }
                triggerWhisperSheetAfterGuidance = false
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
    SettingsView(triggerWhisperSheetAfterGuidance: .constant(false))
        .frame(width: 450, height: 400)
}
