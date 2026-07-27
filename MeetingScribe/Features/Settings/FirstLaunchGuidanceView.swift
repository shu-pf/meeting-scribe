//
//  FirstLaunchGuidanceView.swift
//  MeetingScribe
//

import AppKit
import SwiftUI

/// 初回起動時に必要な保存先・権限・モデルを順番に準備する必須セットアップ。
@MainActor
struct FirstLaunchGuidanceView: View {
    @State private var viewModel = InitialSetupViewModel()

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InitialSetupProgressHeader(currentStep: viewModel.currentStep)

            Divider()

            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
                    .padding(32)
            }

            Divider()

            InitialSetupNavigationBar(
                currentStep: viewModel.currentStep,
                canMoveBack: viewModel.canMoveBack,
                canMoveForward: viewModel.canMoveForward,
                onBack: {
                    Task { await viewModel.moveBack() }
                },
                onForward: {
                    Task { await viewModel.moveForward() }
                },
                onComplete: onComplete
            )
        }
        .frame(width: 680, height: 590)
        .task {
            await viewModel.load()
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            InitialSetupWelcomeStep(
                recommendation: viewModel.recommendation
            )
        case .outputDirectory:
            InitialSetupOutputStep(viewModel: viewModel)
        case .permissions:
            InitialSetupPermissionsStep(viewModel: viewModel)
        case .transcriptionModel:
            InitialSetupWhisperStep(viewModel: viewModel)
        case .summaryModel:
            InitialSetupSummaryStep(viewModel: viewModel)
        case .complete:
            InitialSetupCompleteStep(
                outputDirectoryPath: viewModel.outputDirectoryPath,
                recommendation: viewModel.recommendation,
                hasMicrophonePermission: viewModel.hasMicrophonePermission
            )
        }
    }
}

private struct InitialSetupProgressHeader: View {
    let currentStep: InitialSetupStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(InitialSetupStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    Image(
                        systemName: step.rawValue < currentStep.rawValue
                            ? "checkmark.circle.fill"
                            : step.systemImage
                    )
                    .foregroundStyle(
                        step.rawValue <= currentStep.rawValue
                            ? Color.accentColor
                            : Color.secondary
                    )

                    Text(step.title)
                        .font(.caption)
                        .fontWeight(step == currentStep ? .semibold : .regular)
                        .foregroundStyle(
                            step == currentStep ? .primary : .secondary
                        )
                }

                if step != InitialSetupStep.allCases.last {
                    Rectangle()
                        .fill(
                            step.rawValue < currentStep.rawValue
                                ? Color.accentColor
                                : Color.secondary.opacity(0.25)
                        )
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "初期設定、全\(InitialSetupStep.allCases.count)ステップ中"
                + "\(currentStep.rawValue + 1)番目、\(currentStep.title)"
        )
    }
}

private struct InitialSetupWelcomeStep: View {
    let recommendation: InitialSetupRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("MeetingScribeへようこそ", systemImage: "sparkles")
                .font(.largeTitle.bold())

            Text(
                "会議の録画、文字起こし、要約をすべてこのMacの中で処理します。"
                + "クラウドへ会議内容を送信しません。"
            )
            .font(.title3)

            InitialSetupInformationCard(
                title: "このセットアップで行うこと",
                systemImage: "list.number",
                lines: [
                    "録画と議事録の保存先を選びます",
                    "画面収録とマイクの権限を許可します",
                    "推奨Whisperモデル large-v3-turbo を取得します",
                    "推奨要約モデル \(recommendation.summaryModelID) をOllamaで取得します",
                ]
            )

            Text(
                "モデルのダウンロードには数GBの通信と空き容量が必要です。"
                + "途中でアプリを閉じた場合、次回起動時にセットアップをやり直せます。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct InitialSetupOutputStep: View {
    let viewModel: InitialSetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InitialSetupStepTitle(
                title: "録画と議事録の保存先",
                description: "完成した録画、文字起こし、要約を保存するフォルダを選びます。",
                systemImage: "folder"
            )

            InitialSetupInformationCard(
                title: "おすすめ",
                systemImage: "externaldrive",
                lines: [
                    "長時間録画に十分な空き容量があるフォルダを選んでください",
                    "録画中の作業ファイルはアプリ専用領域に安全に保存されます",
                    "選んだ保存先が録画中に消えても、終了時に再作成します",
                ]
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("選択中の保存先")
                    .font(.headline)

                Text(
                    viewModel.outputDirectoryPath.isEmpty
                        ? "まだ選択されていません"
                        : viewModel.outputDirectoryPath
                )
                .font(.callout)
                .foregroundStyle(
                    viewModel.outputDirectoryPath.isEmpty ? .secondary : .primary
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: .rect(cornerRadius: 8))

                Button("保存先を選ぶ…") {
                    chooseOutputDirectory()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "録画と議事録の保存先を選択"
        panel.message = "長時間録画に十分な空き容量があるフォルダを選んでください。"
        panel.prompt = "このフォルダを使用"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await viewModel.setOutputDirectory(url) }
        }
    }
}

private struct InitialSetupPermissionsStep: View {
    let viewModel: InitialSetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InitialSetupStepTitle(
                title: "録画に必要な権限",
                description: "画面収録は必須です。自分の声を含めたい場合だけマイクも許可してください。",
                systemImage: "lock.shield"
            )

            VStack(spacing: 12) {
                InitialSetupPermissionRow(
                    title: "画面収録",
                    description: "画面や会議ウィンドウとシステム音声を録画します。",
                    isGranted: viewModel.hasScreenCapturePermission
                )
                InitialSetupPermissionRow(
                    title: "マイク",
                    description: "任意。録画開始時に自分の声を含める場合だけ使用します。",
                    isGranted: viewModel.hasMicrophonePermission
                )
            }

            Text(
                "画面収録を許可した直後に状態が変わらない場合は、"
                + "MeetingScribeを終了してもう一度起動してください。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("画面収録を許可・確認") {
                    Task { await viewModel.requestScreenCapturePermission() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRequestingPermissions)

                Button("システム設定を開く") {
                    openPrivacySettings()
                }
                .buttonStyle(.bordered)

                if !viewModel.hasMicrophonePermission {
                    Button("マイクも許可") {
                        Task { await viewModel.requestMicrophonePermission() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRequestingPermissions)
                }

                if viewModel.isRequestingPermissions {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("権限を確認中")
                }
            }
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct InitialSetupWhisperStep: View {
    let viewModel: InitialSetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InitialSetupStepTitle(
                title: "文字起こしモデル",
                description: "録画した日本語音声を文字にするWhisperモデルを準備します。",
                systemImage: "waveform"
            )

            InitialSetupModelCard(
                name: InitialSetupRecommendation.whisperModelID,
                badge: "おすすめ",
                size: "約1.6GB",
                details: [
                    "large-v3に近い文字起こし精度",
                    "large-v3より高速で、長時間会議とのバランスが良好",
                    "ダウンロード後も処理はすべてこのMac内で完結",
                ],
                isInstalled: viewModel.isWhisperModelInstalled
            )

            if viewModel.isDownloadingWhisperModel {
                ProgressView(value: viewModel.whisperDownloadProgress) {
                    Text("Whisperモデルをダウンロード中…")
                } currentValueLabel: {
                    Text(viewModel.whisperDownloadProgress, format: .percent)
                }
                .progressViewStyle(.linear)

                Button("ダウンロードをキャンセル") {
                    viewModel.cancelWhisperDownload()
                }
            } else if !viewModel.isWhisperModelInstalled {
                Button("おすすめモデルをダウンロード") {
                    Task { await viewModel.downloadWhisperModel() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let message = viewModel.whisperErrorMessage {
                InitialSetupErrorMessage(message: message)
            }
        }
    }
}

private struct InitialSetupSummaryStep: View {
    let viewModel: InitialSetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InitialSetupStepTitle(
                title: "要約モデル",
                description: "文字起こしから日本語の会議タイトル、要約、決定事項を作るモデルを準備します。",
                systemImage: "text.document"
            )

            InitialSetupModelCard(
                name: viewModel.recommendation.summaryModelID,
                badge: "このMacにおすすめ",
                size: viewModel.recommendation.summaryModelSize,
                details: [
                    "Gemma 4は要約に適したGoogleの現行ローカルモデル",
                    "日本語を含む140以上の言語と長いコンテキストに対応",
                    "24GB以上のMacでは12B、その他は軽量なE2B QATを選択",
                ],
                isInstalled: viewModel.isSummaryModelInstalled
            )

            if !viewModel.isOllamaAvailable {
                InitialSetupInformationCard(
                    title: viewModel.isOllamaInstalled
                        ? "Ollamaを起動してください"
                        : "先にOllamaをインストールしてください",
                    systemImage: "shippingbox",
                    lines: ollamaSetupInstructions
                )

                HStack {
                    if viewModel.isOllamaInstalled {
                        Button("Ollamaを起動") {
                            Task { await viewModel.launchOllama() }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Link(
                            "Ollama公式ダウンロードを開く",
                            destination: URL(string: "https://ollama.com/download")!
                        )
                    }
                    Button("Ollamaをもう一度確認") {
                        Task { await viewModel.refreshOllamaStatus() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCheckingOllama)
                }
            } else if viewModel.isDownloadingSummaryModel {
                if let progress = viewModel.summaryDownloadProgress {
                    ProgressView(value: progress) {
                        Text(viewModel.summaryDownloadStatus)
                    } currentValueLabel: {
                        Text(progress, format: .percent)
                    }
                    .progressViewStyle(.linear)
                } else {
                    ProgressView {
                        Text(viewModel.summaryDownloadStatus)
                    }
                }
                Text("Ollamaを終了せず、この画面を開いたままお待ちください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !viewModel.isSummaryModelInstalled {
                Button("おすすめモデルをOllamaでダウンロード") {
                    Task { await viewModel.downloadSummaryModel() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let message = viewModel.summaryErrorMessage {
                InitialSetupErrorMessage(message: message)
            }

            if viewModel.requiresOllamaUpdate {
                InitialSetupInformationCard(
                    title: "Ollamaを最新版へ更新してください",
                    systemImage: "arrow.down.app",
                    lines: [
                        "1. 下のボタンからOllama公式ダウンロードを開きます",
                        "2. 最新のmacOS版をダウンロードし、ApplicationsのOllamaを更新します",
                        "3. Ollamaを起動し直して、この画面のダウンロードボタンをもう一度押します",
                    ]
                )

                Link(
                    "Ollama公式ダウンロードを開く",
                    destination: URL(string: "https://ollama.com/download")!
                )
            }
        }
    }

    private var ollamaSetupInstructions: [String] {
        if viewModel.isOllamaInstalled {
            return [
                "Ollamaはインストール済みですが、ローカルAPIへ接続できません",
                "「Ollamaを起動」を押し、メニューバーにOllamaが表示されるまで待ちます",
                "接続できると、この画面から要約モデルを取得できます",
            ]
        }
        return [
            "1. 「Ollama公式ダウンロードを開く」からmacOS版を取得します",
            "2. ダウンロードしたファイルを開き、案内に従ってApplicationsへ入れます",
            "3. ApplicationsフォルダからOllamaを一度起動します",
            "4. この画面へ戻り「Ollamaをもう一度確認」を押します",
        ]
    }
}

private struct InitialSetupCompleteStep: View {
    let outputDirectoryPath: String
    let recommendation: InitialSetupRecommendation
    let hasMicrophonePermission: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("準備ができました", systemImage: "checkmark.circle.fill")
                .font(.largeTitle.bold())
                .foregroundStyle(.green)

            Text("メニューバーのMeetingScribeアイコンから、すぐに録画を開始できます。")
                .font(.title3)

            InitialSetupInformationCard(
                title: "設定内容",
                systemImage: "checklist",
                lines: [
                    "保存先: \(outputDirectoryPath)",
                    "文字起こし: \(InitialSetupRecommendation.whisperModelID)",
                    "要約: \(recommendation.summaryModelID)",
                    "画面収録: 許可済み",
                    "マイク: \(hasMicrophonePermission ? "許可済み" : "未許可（必要時に確認）")",
                ]
            )

            Text(
                "録画終了後、文字起こしと要約はバックグラウンドで進みます。"
                + "複数の処理状況と過去の録画はメニューバーから確認できます。"
            )
            .foregroundStyle(.secondary)
        }
    }
}

private struct InitialSetupNavigationBar: View {
    let currentStep: InitialSetupStep
    let canMoveBack: Bool
    let canMoveForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onComplete: () -> Void

    var body: some View {
        HStack {
            Button("戻る", action: onBack)
                .disabled(!canMoveBack)

            Spacer()

            if currentStep == .complete {
                Button("MeetingScribeを使い始める", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("次へ", action: onForward)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canMoveForward)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

private struct InitialSetupStepTitle: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.title.bold())
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct InitialSetupInformationCard: View {
    let title: String
    let systemImage: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark")
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct InitialSetupPermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName: isGranted
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle"
            )
            .font(.title2)
            .foregroundStyle(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isGranted ? "許可済み" : "許可が必要")
                .font(.callout.bold())
                .foregroundStyle(isGranted ? .green : .orange)
        }
        .padding(14)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct InitialSetupModelCard: View {
    let name: String
    let badge: String
    let size: String
    let details: [String]
    let isInstalled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title3.bold())
                        .textSelection(.enabled)
                    Text("\(badge)・\(size)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    isInstalled ? "準備済み" : "未ダウンロード",
                    systemImage: isInstalled
                        ? "checkmark.circle.fill"
                        : "arrow.down.circle"
                )
                .foregroundStyle(isInstalled ? .green : .secondary)
            }

            ForEach(details, id: \.self) { detail in
                Label(detail, systemImage: "checkmark")
                    .font(.callout)
            }
        }
        .padding(16)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct InitialSetupErrorMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.red.opacity(0.08), in: .rect(cornerRadius: 8))
    }
}
