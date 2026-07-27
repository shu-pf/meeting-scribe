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
    private let settings = SettingsService()

    var body: some View {
        TabView {
            Tab("録画", systemImage: "record.circle") {
                RecordingSettingsTab(viewModel: viewModel)
            }

            Tab("AIモデル", systemImage: "brain") {
                ModelSettingsTab(viewModel: viewModel)
            }

            Tab("起動・更新", systemImage: "arrow.triangle.2.circlepath") {
                GeneralSettingsTab(viewModel: viewModel)
            }

            Tab("ログ・情報", systemImage: "doc.text.magnifyingglass") {
                InformationSettingsTab()
            }
        }
        .frame(minWidth: 460, minHeight: 480)
        .task {
            await viewModel.load()
            if await settings.hasSeenFirstLaunchGuidance,
               await viewModel.shouldShowWhisperModelDownloadSheet() {
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
}

@MainActor
private struct RecordingSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

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

            Section("マイク") {
                Picker(
                    "自分の声",
                    selection: Binding(
                        get: { viewModel.microphoneRecordingPreference },
                        set: { preference in
                            Task {
                                await viewModel.setMicrophoneRecordingPreference(
                                    preference
                                )
                            }
                        }
                    )
                ) {
                    ForEach(MicrophoneRecordingPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }

                Text(viewModel.microphoneRecordingPreference.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

@MainActor
private struct ModelSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("文字起こし（Whisper）") {
                Picker(
                    "モデル",
                    selection: Binding(
                        get: { viewModel.selectedWhisperModelID },
                        set: { modelID in
                            Task {
                                await viewModel.setSelectedWhisperModelID(modelID)
                            }
                        }
                    )
                ) {
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
                Picker(
                    "モデル",
                    selection: Binding(
                        get: { viewModel.selectedSummaryModelID },
                        set: { modelID in
                            Task {
                                await viewModel.setSelectedSummaryModelID(modelID)
                            }
                        }
                    )
                ) {
                    Text("未選択").tag("")
                    ForEach(viewModel.summaryModelPickerIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Text("長い文字起こしは自動的に分割・統合して要約します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct GeneralSettingsTab: View {
    @EnvironmentObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("起動") {
                Toggle(
                    "ログイン時に起動",
                    isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { shouldLaunchAtLogin in
                            Task {
                                await viewModel.setLaunchAtLogin(
                                    shouldLaunchAtLogin
                                )
                            }
                        }
                    )
                )
            }

            Section("アップデート") {
                Toggle(
                    "自動的にアップデートを確認",
                    isOn: $checkForUpdatesViewModel.automaticallyChecksForUpdates
                )
                Button("アップデートを確認…") {
                    checkForUpdatesViewModel.checkForUpdates()
                }
                .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct InformationSettingsTab: View {
    var body: some View {
        Form {
            Section("診断ログ") {
                Text("録画や文字起こしが失敗したときの調査情報を、このMac内だけに保存します。会議の内容は記録しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("ログを開く") {
                        openDiagnosticLog()
                    }
                    Button("Finderで表示") {
                        revealDiagnosticLog()
                    }
                }
                Text(DiagnosticLogStore.currentLogURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("バージョン情報") {
                LabeledContent("バージョン") {
                    HStack(spacing: 8) {
                        Text(appVersion)
                        DevelopmentBuildBadge()
                    }
                }
                LabeledContent("作成者") {
                    Text("Shugo Furuse")
                }
                LabeledContent("リポジトリ") {
                    Link("GitHub", destination: URL(string: "https://github.com/shu-pf/meeting-scribe")!)
                }
                Text("会議の録画・文字起こし・要約をワンクリックで。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    private func openDiagnosticLog() {
        DiagnosticLogStore.shared.flush()
        NSWorkspace.shared.open(DiagnosticLogStore.currentLogURL)
    }

    private func revealDiagnosticLog() {
        DiagnosticLogStore.shared.flush()
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLogStore.currentLogURL])
    }
}

#Preview {
    SettingsView()
        .frame(width: 450, height: 400)
}
