//
//  InitialSetupViewModel.swift
//  MeetingScribe
//

import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import Observation

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

extension SettingsServiceProtocol {
    func apply(_ effect: InitialSetupEffect) async {
        switch effect {
        case .saveStep(let step):
            await setInitialSetupStepRawValue(step.rawValue)
        case .selectWhisperModel(let id):
            await setSelectedWhisperModelID(id)
        case .selectSummaryModel(let id):
            await setSelectedSummaryModelID(id)
        case .setSkipsSummary(let value):
            await setSkipsSummary(value)
        }
    }
}

/// 初回セットアップの画面。手順と設定への書き込みの判断は InitialSetupFlow に任せ、
/// ここでは権限・ファイル・Ollama を読み取り、ダウンロードを始め、書き込みを順に反映する。
@MainActor
@Observable
final class InitialSetupViewModel {
    private(set) var flow: InitialSetupFlow
    var outputDirectoryPath = ""
    var hasMicrophonePermission = false
    var isRequestingPermissions = false
    private(set) var isCompleting = false

    var isOllamaAvailable = false
    var isOllamaInstalled = false
    var isCheckingOllama = false
    private var ollamaErrorMessage: String?

    let recommendation: InitialSetupRecommendation

    private let settings: SettingsServiceProtocol
    private let whisperStore: WhisperModelStoreProtocol
    private let summaryService: SummaryServiceProtocol
    private let downloads: InitialSetupDownloads
    /// 設定への書き込みを、判断した順に 1 つずつ反映する
    private var pendingWrites: Task<Void, Never>?

    convenience init() {
        self.init(
            settings: SettingsService(),
            whisperStore: WhisperModelStore.shared,
            summaryService: SummaryService(),
            downloads: .shared,
            recommendation: .currentMac
        )
    }

    init(
        settings: SettingsServiceProtocol,
        whisperStore: WhisperModelStoreProtocol,
        summaryService: SummaryServiceProtocol,
        downloads: InitialSetupDownloads,
        recommendation: InitialSetupRecommendation
    ) {
        self.settings = settings
        self.whisperStore = whisperStore
        self.summaryService = summaryService
        self.downloads = downloads
        self.recommendation = recommendation
        self.flow = InitialSetupFlow(
            whisperModelID: InitialSetupRecommendation.whisperModelID,
            summaryModelID: recommendation.summaryModelID
        )
    }

    var currentStep: InitialSetupStep { flow.step }
    var hasScreenCapturePermission: Bool { flow.hasScreenCapturePermission }
    var isWhisperModelInstalled: Bool { flow.isWhisperModelInstalled }
    var isSummaryModelInstalled: Bool { flow.isSummaryModelInstalled }
    var skipsSummary: Bool { flow.skipsSummary }

    var isDownloadingWhisperModel: Bool { downloads.gate.isDownloadingWhisper }
    var whisperDownloadProgress: Double { downloads.whisperProgress }
    var whisperErrorMessage: String? { downloads.whisperErrorMessage }

    var isDownloadingSummaryModel: Bool { downloads.gate.isDownloadingSummary }
    var summaryDownloadProgress: Double? { downloads.summaryProgress }
    var summaryDownloadStatus: String { downloads.summaryStatus }
    var summaryErrorMessage: String? {
        downloads.summaryErrorMessage ?? ollamaErrorMessage
    }
    var requiresOllamaUpdate: Bool { downloads.requiresOllamaUpdate }

    var canMoveForward: Bool { flow.canMoveForward }

    var canMoveBack: Bool {
        currentStep != .welcome
            && !downloads.gate.isDownloading
            && !isRequestingPermissions
            && !isCompleting
    }

    func load() async {
        flow.restore(savedStepRawValue: await settings.initialSetupStepRawValue)
        outputDirectoryPath = await settings.outputDirectoryURL?.path ?? ""
        flow.observeOutputDirectory(!outputDirectoryPath.isEmpty)
        flow.observeSkipsSummary(await settings.skipsSummary)
        refreshPermissionStatuses()
        await refreshWhisperModelStatus()
        await refreshOllamaStatus()
        followRunningDownloads()
    }

    func moveForward() {
        write(flow.moveForward())
    }

    func moveBack() {
        guard canMoveBack else { return }
        write(flow.moveBack())
    }

    /// 要約モデルを用意せずに、文字起こしだけで使い始める
    func skipSummaryModel() {
        guard !isDownloadingSummaryModel else { return }
        write(flow.skipSummary())
    }

    /// 完了の操作。設定と環境を読み直し、そろっていれば true。
    /// 欠けていれば完了せず、欠けている最初の手順へ戻す。
    func complete() async -> Bool {
        guard currentStep == .complete, !isCompleting else { return false }
        isCompleting = true
        defer { isCompleting = false }

        await pendingWrites?.value
        refreshPermissionStatuses()
        let outputDirectory = await settings.outputDirectoryURL
        let installedSummaryModelIDs = try? await summaryService.fetchAvailableModelIDs()
        let snapshot = InitialSetupSnapshot(
            hasOutputDirectory: outputDirectory.map(Self.isExistingDirectory) ?? false,
            hasScreenCapturePermission: CGPreflightScreenCaptureAccess(),
            isWhisperModelInstalled: await whisperStore.localFileURL(
                forModelID: InitialSetupRecommendation.whisperModelID
            ) != nil,
            installedSummaryModelIDs: installedSummaryModelIDs.map(Set.init),
            skipsSummary: await settings.skipsSummary
        )
        outputDirectoryPath = snapshot.hasOutputDirectory ? outputDirectory?.path ?? "" : ""
        isOllamaAvailable = installedSummaryModelIDs != nil
        write(flow.complete(snapshot))
        await pendingWrites?.value
        return flow.isFinished
    }

    func setOutputDirectory(_ url: URL) async {
        await settings.setOutputDirectory(url)
        outputDirectoryPath = url.path
        flow.observeOutputDirectory(true)
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
        flow.observeScreenCapturePermission(CGPreflightScreenCaptureAccess())
        hasMicrophonePermission =
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func downloadWhisperModel() async {
        downloads.startWhisperDownload(
            modelID: InitialSetupRecommendation.whisperModelID,
            store: whisperStore,
            settings: settings
        )
        await downloads.waitForWhisperDownload()
        await refreshWhisperModelStatus()
    }

    func cancelWhisperDownload() {
        downloads.cancelWhisperDownload()
    }

    func refreshOllamaStatus() async {
        guard !isCheckingOllama else { return }
        isCheckingOllama = true
        ollamaErrorMessage = nil
        defer { isCheckingOllama = false }

        isOllamaInstalled =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.electron.ollama"
            ) != nil
        do {
            let modelIDs = try await summaryService.fetchAvailableModelIDs()
            isOllamaAvailable = true
            write(flow.observeSummaryModels(Set(modelIDs)))
        } catch {
            isOllamaAvailable = false
            write(flow.observeSummaryModels(nil))
            ollamaErrorMessage =
                "Ollamaに接続できません。Ollamaをインストールして起動してから、もう一度確認してください。"
        }
    }

    func launchOllama() async {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.electron.ollama"
        ) else {
            isOllamaInstalled = false
            ollamaErrorMessage =
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
            ollamaErrorMessage =
                "Ollamaを起動できませんでした: \(error.localizedDescription)"
        }
    }

    func downloadSummaryModel() async {
        guard isOllamaAvailable else { return }
        downloads.startSummaryPull(
            modelID: recommendation.summaryModelID,
            summaryService: summaryService,
            settings: settings
        )
        await downloads.waitForSummaryPull()
        await refreshOllamaStatus()
    }

    private func refreshWhisperModelStatus() async {
        let installed = await whisperStore.localFileURL(
            forModelID: InitialSetupRecommendation.whisperModelID
        ) != nil
        write(flow.observeWhisperModel(installed: installed))
    }

    /// 画面を閉じて開き直したとき、裏で続いているダウンロードの終わりを画面に反映する
    private func followRunningDownloads() {
        if downloads.gate.isDownloadingWhisper {
            Task { [weak self] in
                await self?.downloads.waitForWhisperDownload()
                await self?.refreshWhisperModelStatus()
            }
        }
        if downloads.gate.isDownloadingSummary {
            Task { [weak self] in
                await self?.downloads.waitForSummaryPull()
                await self?.refreshOllamaStatus()
            }
        }
    }

    private func write(_ effects: [InitialSetupEffect]) {
        guard !effects.isEmpty else { return }
        let previous = pendingWrites
        let settings = settings
        pendingWrites = Task {
            await previous?.value
            for effect in effects {
                await settings.apply(effect)
            }
        }
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

/// オンボーディングのモデルのダウンロード。画面 (ViewModel) を閉じても続くので、
/// アプリで 1 つだけ持ち、開き直した画面が同じダウンロードの進み具合を表示する。
@MainActor
@Observable
final class InitialSetupDownloads {
    static let shared = InitialSetupDownloads()

    private(set) var gate = InitialSetupDownloadGate()
    private(set) var whisperProgress = 0.0
    private(set) var whisperErrorMessage: String?
    private(set) var summaryProgress: Double?
    private(set) var summaryStatus = ""
    private(set) var summaryErrorMessage: String?
    private(set) var requiresOllamaUpdate = false

    private let whisperDownloader = WhisperModelDownloader()
    private var whisperTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?

    func startWhisperDownload(
        modelID: String,
        store: WhisperModelStoreProtocol,
        settings: SettingsServiceProtocol
    ) {
        guard gate.begin(.whisper) else { return }
        whisperProgress = 0
        whisperErrorMessage = nil
        whisperTask = Task { [weak self] in
            guard let self else { return }
            let (progressStream, progressContinuation) = AsyncStream.makeStream(
                of: Double.self
            )
            let progressTask = Task { [weak self] in
                for await progress in progressStream {
                    self?.whisperProgress = progress
                }
            }
            do {
                try await whisperDownloader.download(
                    modelID: modelID,
                    store: store,
                    progressHandler: { progress in
                        progressContinuation.yield(progress)
                    }
                )
                for effect in InitialSetupFlow.whisperModelDownloaded(modelID) {
                    await settings.apply(effect)
                }
                whisperProgress = 1
            } catch let error where Self.isCancellation(error) {
                // キャンセルはエラーとして表示しない
            } catch {
                whisperErrorMessage = error.localizedDescription
            }
            progressContinuation.finish()
            progressTask.cancel()
            gate.end(.whisper)
            whisperTask = nil
        }
    }

    func waitForWhisperDownload() async {
        await whisperTask?.value
    }

    func cancelWhisperDownload() {
        whisperDownloader.cancel()
    }

    func startSummaryPull(
        modelID: String,
        summaryService: SummaryServiceProtocol,
        settings: SettingsServiceProtocol
    ) {
        guard gate.begin(.summary) else { return }
        summaryProgress = nil
        summaryStatus = "ダウンロードを開始しています…"
        summaryErrorMessage = nil
        requiresOllamaUpdate = false
        summaryTask = Task { [weak self] in
            guard let self else { return }
            let (progressStream, progressContinuation) = AsyncStream.makeStream(
                of: OllamaModelPullProgress.self
            )
            let progressTask = Task { [weak self] in
                for await progress in progressStream {
                    self?.summaryStatus = progress.status
                    self?.summaryProgress = progress.fractionCompleted
                }
            }
            do {
                try await summaryService.pullModel(
                    modelID: modelID,
                    progressHandler: { progress in
                        progressContinuation.yield(progress)
                    }
                )
                for effect in InitialSetupFlow.summaryModelPulled(modelID) {
                    await settings.apply(effect)
                }
                summaryProgress = 1
                summaryStatus = "ダウンロードが完了しました"
            } catch let error where Self.isCancellation(error) {
                // キャンセルはエラーとして表示しない
            } catch SummaryError.ollamaUpdateRequired {
                requiresOllamaUpdate = true
                summaryErrorMessage = SummaryError
                    .ollamaUpdateRequired
                    .localizedDescription
            } catch {
                summaryErrorMessage = error.localizedDescription
            }
            progressContinuation.finish()
            progressTask.cancel()
            gate.end(.summary)
            summaryTask = nil
        }
    }

    func waitForSummaryPull() async {
        await summaryTask?.value
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
