//
//  InitialSetupViewModel.swift
//  MeetingScribe
//

import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import Observation

enum InitialSetupStep: Int, CaseIterable, Sendable {
    case welcome
    case outputDirectory
    case permissions
    case transcriptionModel
    case summaryModel
    case complete

    var title: String {
        switch self {
        case .welcome: "ようこそ"
        case .outputDirectory: "保存先"
        case .permissions: "権限"
        case .transcriptionModel: "文字起こし"
        case .summaryModel: "要約"
        case .complete: "完了"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "hand.wave"
        case .outputDirectory: "folder"
        case .permissions: "lock.shield"
        case .transcriptionModel: "waveform"
        case .summaryModel: "text.document"
        case .complete: "checkmark.circle"
        }
    }
}

struct InitialSetupRecommendation: Sendable {
    static let whisperModelID = "large-v3-turbo"

    let summaryModelID: String
    let summaryModelSize: String

    static var currentMac: Self {
        let memory = ProcessInfo.processInfo.physicalMemory
        if memory >= 24 * 1_024 * 1_024 * 1_024 {
            return Self(summaryModelID: "gemma4:12b", summaryModelSize: "約7.6GB")
        }
        return Self(
            summaryModelID: "gemma4:e2b-it-qat",
            summaryModelSize: "約4.3GB"
        )
    }
}

@MainActor
@Observable
final class InitialSetupViewModel {
    var currentStep: InitialSetupStep = .welcome
    var outputDirectoryPath = ""
    var hasScreenCapturePermission = false
    var hasMicrophonePermission = false
    var isRequestingPermissions = false

    var isWhisperModelInstalled = false
    var isDownloadingWhisperModel = false
    var whisperDownloadProgress = 0.0
    var whisperErrorMessage: String?

    var isOllamaAvailable = false
    var isOllamaInstalled = false
    var isSummaryModelInstalled = false
    var isCheckingOllama = false
    var isDownloadingSummaryModel = false
    var summaryDownloadProgress: Double?
    var summaryDownloadStatus = ""
    var summaryErrorMessage: String?
    var requiresOllamaUpdate = false

    let recommendation: InitialSetupRecommendation

    private let settings: SettingsServiceProtocol
    private let whisperStore: WhisperModelStoreProtocol
    private let whisperDownloader: WhisperModelDownloader
    private let summaryService: SummaryServiceProtocol

    init() {
        self.settings = SettingsService()
        self.whisperStore = WhisperModelStore.shared
        self.whisperDownloader = WhisperModelDownloader()
        self.summaryService = SummaryService()
        self.recommendation = .currentMac
    }

    init(
        settings: SettingsServiceProtocol,
        whisperStore: WhisperModelStoreProtocol,
        whisperDownloader: WhisperModelDownloader,
        summaryService: SummaryServiceProtocol,
        recommendation: InitialSetupRecommendation
    ) {
        self.settings = settings
        self.whisperStore = whisperStore
        self.whisperDownloader = whisperDownloader
        self.summaryService = summaryService
        self.recommendation = recommendation
    }

    var canMoveForward: Bool {
        switch currentStep {
        case .welcome:
            true
        case .outputDirectory:
            !outputDirectoryPath.isEmpty
        case .permissions:
            hasScreenCapturePermission
        case .transcriptionModel:
            isWhisperModelInstalled
        case .summaryModel:
            isSummaryModelInstalled
        case .complete:
            false
        }
    }

    var canMoveBack: Bool {
        currentStep != .welcome
            && !isDownloadingWhisperModel
            && !isDownloadingSummaryModel
            && !isRequestingPermissions
    }

    func load() async {
        let savedStepRawValue = await settings.initialSetupStepRawValue
        currentStep = InitialSetupStep(rawValue: savedStepRawValue) ?? .welcome
        outputDirectoryPath = await settings.outputDirectoryURL?.path ?? ""
        refreshPermissionStatuses()
        isWhisperModelInstalled = await whisperStore.localFileURL(
            forModelID: InitialSetupRecommendation.whisperModelID
        ) != nil
        await refreshOllamaStatus()
    }

    func moveForward() async {
        guard canMoveForward,
              let next = InitialSetupStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        await settings.setInitialSetupStepRawValue(next.rawValue)
        currentStep = next
    }

    func moveBack() async {
        guard canMoveBack,
              let previous = InitialSetupStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        await settings.setInitialSetupStepRawValue(previous.rawValue)
        currentStep = previous
    }

    func setOutputDirectory(_ url: URL) async {
        await settings.setOutputDirectory(url)
        outputDirectoryPath = url.path
    }

    func requestScreenCapturePermission() async {
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        refreshPermissionStatuses()
    }

    func requestMicrophonePermission() async {
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        refreshPermissionStatuses()
    }

    func refreshPermissionStatuses() {
        hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
        hasMicrophonePermission =
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func downloadWhisperModel() async {
        guard !isDownloadingWhisperModel else { return }
        isDownloadingWhisperModel = true
        whisperDownloadProgress = 0
        whisperErrorMessage = nil
        defer { isDownloadingWhisperModel = false }

        let (progressStream, progressContinuation) = AsyncStream.makeStream(
            of: Double.self
        )
        let progressTask = Task { [weak self] in
            for await progress in progressStream {
                self?.whisperDownloadProgress = progress
            }
        }
        defer {
            progressContinuation.finish()
            progressTask.cancel()
        }

        do {
            try await whisperDownloader.download(
                modelID: InitialSetupRecommendation.whisperModelID,
                store: whisperStore,
                progressHandler: { progress in
                    progressContinuation.yield(progress)
                }
            )
            await settings.setSelectedWhisperModelID(
                InitialSetupRecommendation.whisperModelID
            )
            isWhisperModelInstalled = true
            whisperDownloadProgress = 1
        } catch is CancellationError {
            return
        } catch {
            whisperErrorMessage = error.localizedDescription
        }
    }

    func cancelWhisperDownload() {
        whisperDownloader.cancel()
    }

    func refreshOllamaStatus() async {
        guard !isCheckingOllama else { return }
        isCheckingOllama = true
        summaryErrorMessage = nil
        defer { isCheckingOllama = false }

        isOllamaInstalled =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.electron.ollama"
            ) != nil
        do {
            let modelIDs = try await summaryService.fetchAvailableModelIDs()
            isOllamaAvailable = true
            isSummaryModelInstalled = modelIDs.contains(
                recommendation.summaryModelID
            )
            if isSummaryModelInstalled {
                await settings.setSelectedSummaryModelID(
                    recommendation.summaryModelID
                )
            }
        } catch {
            isOllamaAvailable = false
            isSummaryModelInstalled = false
            summaryErrorMessage =
                "Ollamaに接続できません。Ollamaをインストールして起動してから、もう一度確認してください。"
        }
    }

    func launchOllama() async {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.electron.ollama"
        ) else {
            isOllamaInstalled = false
            summaryErrorMessage =
                "Ollamaがまだインストールされていません。公式サイトからインストールしてください。"
            return
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: configuration
            )
            try? await Task.sleep(for: .seconds(2))
            await refreshOllamaStatus()
        } catch {
            summaryErrorMessage =
                "Ollamaを起動できませんでした: \(error.localizedDescription)"
        }
    }

    func downloadSummaryModel() async {
        guard isOllamaAvailable, !isDownloadingSummaryModel else { return }
        isDownloadingSummaryModel = true
        summaryDownloadProgress = nil
        summaryDownloadStatus = "ダウンロードを開始しています…"
        summaryErrorMessage = nil
        requiresOllamaUpdate = false
        defer { isDownloadingSummaryModel = false }

        let (progressStream, progressContinuation) = AsyncStream.makeStream(
            of: OllamaModelPullProgress.self
        )
        let progressTask = Task { [weak self] in
            for await progress in progressStream {
                self?.summaryDownloadStatus = progress.status
                self?.summaryDownloadProgress = progress.fractionCompleted
            }
        }
        defer {
            progressContinuation.finish()
            progressTask.cancel()
        }

        do {
            try await summaryService.pullModel(
                modelID: recommendation.summaryModelID,
                progressHandler: { progress in
                    progressContinuation.yield(progress)
                }
            )
            await settings.setSelectedSummaryModelID(
                recommendation.summaryModelID
            )
            isSummaryModelInstalled = true
            summaryDownloadProgress = 1
            summaryDownloadStatus = "ダウンロードが完了しました"
        } catch is CancellationError {
            return
        } catch SummaryError.ollamaUpdateRequired {
            requiresOllamaUpdate = true
            summaryErrorMessage = SummaryError
                .ollamaUpdateRequired
                .localizedDescription
        } catch {
            summaryErrorMessage = error.localizedDescription
        }
    }
}
