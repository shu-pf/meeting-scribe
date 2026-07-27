//
//  MenuBarViewModel.swift
//  MeetingScribe
//

import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SwiftUI
import UserNotifications

/// 録画対象として表示するディスプレイの表示用モデル
struct DisplayItem: Identifiable {
    let id: UInt32
    let displayID: UInt32
    let label: String
}

/// 録画対象として表示するウィンドウの表示用モデル
struct WindowItem: Identifiable {
    let id: UInt32
    let windowID: UInt32
    let label: String
}

/// 録画終了後に実行される1件分の処理状態
enum PipelineJobStatus: Equatable {
    case waiting
    case transcribing
    case summarizing
    case saving
    case completed(String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .waiting, .transcribing, .summarizing, .saving:
            true
        case .completed, .failed:
            false
        }
    }
}

/// メニューバーに表示する録画後処理ジョブ
struct PipelineJob: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var status: PipelineJobStatus
}

/// 出力フォルダから復元した録画履歴
struct RecordingHistoryItem: Identifiable, Equatable {
    var id: URL { recordingURL }

    let recordingURL: URL
    let title: String
    let recordedAt: Date
    let hasTranscript: Bool
    let hasSummary: Bool
}

private enum OutputDirectoryPreparationError: LocalizedError {
    case pathIsNotDirectory(String)
    case creationFailed(String, Error)
    case destinationUnavailable
    case finalizationFailed(String, String, Error)

    var errorDescription: String? {
        switch self {
        case .pathIsNotDirectory(let path):
            "保存先がフォルダではありません: \(path)"
        case .creationFailed(let path, let error):
            "保存先フォルダを作成できませんでした: \(path)（\(error.localizedDescription)）"
        case .destinationUnavailable:
            "完成した録画の保存先を確認できませんでした。"
        case .finalizationFailed(let source, let destination, let error):
            "完成した録画を保存先へ移動できませんでした: \(source) → \(destination)（\(error.localizedDescription)）"
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var selectedDisplayID: UInt32?
    @Published var selectedWindowID: UInt32?
    @Published var errorMessage: String?
    @Published var displayItems: [DisplayItem] = []
    @Published var windowItems: [WindowItem] = []
    @Published var isLoadingContent = false
    @Published private(set) var pipelineJobs: [PipelineJob] = []
    @Published private(set) var recordingHistory: [RecordingHistoryItem] = []
    @Published private(set) var isLoadingRecordingHistory = false
    /// 出力フォルダが設定済みか（未設定の場合は録画開始不可）
    @Published var isOutputDirectorySet = false
    /// 選択済みWhisperモデルの実ファイルが利用可能か
    @Published private(set) var isWhisperModelReady = false
    /// 要約モデルが選択済みか
    @Published private(set) var isSummaryModelSet = false
    @Published var isShowingMicrophoneChoice = false
    @Published private(set) var isPreparingRecording = false

    private let recording: RecordingServiceProtocol
    private let settings: SettingsServiceProtocol
    private let pipeline: RecordingPipelineProtocol
    private let pipelineJobStore: PipelineJobStore
    private let whisperModelStore: WhisperModelStoreProtocol
    private let diagnosticLog = DiagnosticLogger(category: "MenuBar")
    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    private static let recordingExtensions: Set<String> = ["mp4", "mov", "m4v"]
    /// 録画用のセキュリティスコープ付き出力フォルダ
    private var recordingSecurityScopedDirectory: URL?
    /// 録画完了後に作業領域から移動する最終保存先
    private var recordingDestinationURL: URL?
    private var persistedPipelineJobs: [UUID: PersistedPipelineJob] = [:]
    private var pipelineTasks: [UUID: Task<Void, Never>] = [:]
    private var hasRestoredPipelineJobs = false
    private var isPipelinePausedForSleep = false
    var activePipelineJobCount: Int {
        pipelineJobs.count { job in
            switch job.status {
            case .transcribing, .summarizing, .saving:
                true
            case .waiting, .completed, .failed:
                false
            }
        }
    }

    var waitingPipelineJobCount: Int {
        pipelineJobs.count { $0.status == .waiting }
    }

    var canStartRecording: Bool {
        isOutputDirectorySet
            && isWhisperModelReady
            && isSummaryModelSet
            && !isPreparingRecording
    }

    init(
        recording: RecordingServiceProtocol? = nil,
        settings: SettingsServiceProtocol? = nil,
        pipeline: RecordingPipelineProtocol? = nil,
        whisperModelStore: WhisperModelStoreProtocol? = nil,
        pipelineJobStore: PipelineJobStore? = nil
    ) {
        let settingsInstance = settings ?? SettingsService()
        self.recording = recording ?? RecordingService()
        self.settings = settingsInstance
        self.whisperModelStore = whisperModelStore ?? WhisperModelStore.shared
        self.pipelineJobStore = pipelineJobStore ?? PipelineJobStore()
        self.pipeline = pipeline ?? RecordingPipeline(
            transcription: TranscriptionService(),
            summary: SummaryService()
        )
    }

    func startRecording() {
        guard !isRecording, !isPreparingRecording else { return }
        isPreparingRecording = true
        Task {
            let preference = await settings.microphoneRecordingPreference
            switch preference {
            case .askEveryTime:
                isPreparingRecording = false
                isShowingMicrophoneChoice = true
            case .alwaysInclude:
                await startRecording(includeMicrophone: true)
            case .neverInclude:
                await startRecording(includeMicrophone: false)
            }
        }
    }

    func confirmRecordingStart(includeMicrophone: Bool) {
        isShowingMicrophoneChoice = false
        guard !isRecording, !isPreparingRecording else { return }
        isPreparingRecording = true
        Task {
            await startRecording(includeMicrophone: includeMicrophone)
        }
    }

    func cancelRecordingStart() {
        isShowingMicrophoneChoice = false
    }

    private func startRecording(includeMicrophone: Bool) async {
        defer {
            if !isRecording {
                isPreparingRecording = false
            }
        }
        diagnosticLog.info(
            "録画開始操作 displayID=\(String(describing: selectedDisplayID)) windowID=\(String(describing: selectedWindowID)) includeMicrophone=\(includeMicrophone)"
        )
        do {
                await refreshWhisperModelAvailability()
                guard isWhisperModelReady else {
                    errorMessage = "文字起こしモデルをダウンロードしてください。"
                    diagnosticLog.warning("録画開始を中断: 文字起こしモデル未設定")
                    return
                }
                await refreshSummaryModelSelection()
                guard isSummaryModelSet else {
                    errorMessage = "要約モデルを設定してください。"
                    diagnosticLog.warning("録画開始を中断: 要約モデル未設定")
                    return
                }
                guard let settingsDir = await settings.outputDirectoryURL else {
                    diagnosticLog.error("録画開始失敗: 出力フォルダ未設定")
                    errorMessage = "出力フォルダが未設定です。設定から出力フォルダを選択してください。"
                    return
                }
                let isAccessing = settingsDir.startAccessingSecurityScopedResource()
                if isAccessing {
                    recordingSecurityScopedDirectory = settingsDir
                }
                try prepareOutputDirectory(settingsDir)
                let name = "recording_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).mp4"
                let destinationURL = settingsDir.appendingPathComponent(name)
                let stagingDirectory = try prepareRecordingStagingDirectory()
                let stagingURL = stagingDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("partial.mp4")
                recordingDestinationURL = destinationURL
                try await recording.startRecording(
                    displayID: selectedDisplayID,
                    windowID: selectedWindowID,
                    outputURL: stagingURL,
                    includeMicrophone: includeMicrophone,
                    onStreamStoppedUnexpectedly: { [weak self] result in
                        guard let self else { return }
                        Task { @MainActor in
                            self.handleStreamStoppedUnexpectedly(result: result)
                        }
                    },
                    onMaximumDurationReached: { [weak self] in
                        guard let self else { return }
                        Task { @MainActor in
                            self.sendMaximumDurationNotification()
                        }
                    }
                )
                isRecording = true
                isPreparingRecording = false
                errorMessage = nil
                diagnosticLog.info(
                    "録画中状態へ遷移 stagingURL=\(stagingURL.path) destinationURL=\(destinationURL.path)"
                )
            } catch {
                recordingDestinationURL = nil
                releaseRecordingSecurityScopedDirectory()
                errorMessage = error.localizedDescription
                diagnosticLog.error("録画開始失敗 error=\(Self.describeError(error))")
            }
    }

    func stopRecording() {
        diagnosticLog.info("録画停止操作")
        Task {
            do {
                let stagingURL = try await recording.stopRecording()
                let fileURL = try finalizeRecording(at: stagingURL)
                isRecording = false
                errorMessage = nil
                // 録画用のセキュリティスコープを解放し、パイプライン専用に新たに取得する
                releaseRecordingSecurityScopedDirectory()
                runPipelineInBackground(fileURL: fileURL)
                diagnosticLog.info("録画停止成功 fileURL=\(fileURL.path)")
            } catch {
                isRecording = false
                recordingDestinationURL = nil
                errorMessage = error.localizedDescription
                releaseRecordingSecurityScopedDirectory()
                diagnosticLog.error("録画停止失敗 error=\(Self.describeError(error))")
            }
        }
    }

    private func prepareOutputDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) {
            guard isDirectory.boolValue else {
                throw OutputDirectoryPreparationError.pathIsNotDirectory(directory.path)
            }
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            diagnosticLog.info("存在しない出力フォルダを作成 path=\(directory.path)")
        } catch {
            throw OutputDirectoryPreparationError.creationFailed(directory.path, error)
        }
    }

    private func prepareRecordingStagingDirectory() throws -> URL {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw OutputDirectoryPreparationError.destinationUnavailable
        }
        let stagingDirectory = applicationSupportDirectory
            .appendingPathComponent("MeetingScribe", isDirectory: true)
            .appendingPathComponent("InProgress", isDirectory: true)
        try prepareOutputDirectory(stagingDirectory)
        return stagingDirectory
    }

    private func finalizeRecording(at stagingURL: URL) throws -> URL {
        guard let destinationURL = recordingDestinationURL else {
            throw OutputDirectoryPreparationError.destinationUnavailable
        }
        defer { recordingDestinationURL = nil }

        try prepareOutputDirectory(destinationURL.deletingLastPathComponent())
        do {
            try FileManager.default.moveItem(
                at: stagingURL,
                to: destinationURL
            )
            // 空なら隠し作業フォルダも片付ける。クラッシュ時の未完了ファイルが
            // 残っている場合は削除に失敗するため、そのまま保全される。
            try? FileManager.default.removeItem(
                at: stagingURL.deletingLastPathComponent()
            )
            diagnosticLog.info(
                "完成した録画を保存先へ移動 source=\(stagingURL.path) destination=\(destinationURL.path)"
            )
            return destinationURL
        } catch {
            throw OutputDirectoryPreparationError.finalizationFailed(
                stagingURL.path,
                destinationURL.path,
                error
            )
        }
    }

    /// ストリームが予期せず停止したとき（例: 録画元ウィンドウが閉じられたとき）にコールバックから呼ばれる。録画終了と同様にパイプラインを実行する。
    private func handleStreamStoppedUnexpectedly(result: Result<URL, Error>) {
        isRecording = false
        defer { releaseRecordingSecurityScopedDirectory() }
        switch result {
        case .success(let stagingURL):
            do {
                let fileURL = try finalizeRecording(at: stagingURL)
                errorMessage = nil
                diagnosticLog.warning(
                    "録画ストリームが予期せず停止 fileURL=\(fileURL.path)"
                )
                runPipelineInBackground(fileURL: fileURL)
            } catch {
                recordingDestinationURL = nil
                errorMessage = error.localizedDescription
                diagnosticLog.error(
                    "予期しない停止後の録画保存に失敗 error=\(Self.describeError(error))"
                )
            }
        case .failure(let error):
            recordingDestinationURL = nil
            errorMessage = error.localizedDescription
            diagnosticLog.error(
                "録画ストリームの予期しない停止処理に失敗 error=\(Self.describeError(error))"
            )
        }
    }

    /// 通知の送信権限をリクエストする（アプリ起動時に呼ぶ）
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 要約完了時にローカル通知を送信する
    private func sendCompletionNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "会議の要約が完了しました"
        content.body = title
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendMaximumDurationNotification() {
        let content = UNMutableNotificationContent()
        content.title = "5時間の上限に達しました"
        content.body = "録画を自動終了しています。完了後に文字起こしと要約を開始します。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// パイプライン処理をバックグラウンドで実行する。新しい録画の開始に影響されない独立した Task として動かす。
    private func runPipelineInBackground(fileURL: URL) {
        let jobID = UUID()
        let createdAt = Date()
        let job = PipelineJob(id: jobID, createdAt: createdAt, status: .waiting)
        pipelineJobs.insert(job, at: 0)
        trimFinishedPipelineJobs()
        diagnosticLog.info("録画後パイプライン開始 fileURL=\(fileURL.path)")
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let outputDirectory = await settings.outputDirectoryURL,
                      let whisperModelID = await settings.selectedWhisperModelID,
                      let summaryModelID = await settings.selectedSummaryModelID else {
                    throw PipelineJobPreparationError.settingsUnavailable
                }
                let recordingDate =
                    (try? FileManager.default.attributesOfItem(
                        atPath: fileURL.path
                    )[.creationDate] as? Date) ?? createdAt
                let bookmark = try? outputDirectory.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let persistedJob = PersistedPipelineJob(
                    id: jobID,
                    createdAt: createdAt,
                    recordingDate: recordingDate,
                    recordingPath: fileURL.path,
                    outputDirectoryPath: outputDirectory.path,
                    outputDirectoryBookmark: bookmark,
                    whisperModelID: whisperModelID,
                    summaryModelID: summaryModelID,
                    state: .waiting,
                    detail: nil
                )
                persistedPipelineJobs[jobID] = persistedJob
                try await pipelineJobStore.upsert(persistedJob)
                await executePipelineJob(persistedJob)
            } catch {
                updatePipelineJob(
                    id: jobID,
                    status: .failed(error.localizedDescription)
                )
                diagnosticLog.error(
                    "録画後パイプライン準備失敗 error=\(Self.describeError(error))"
                )
            }
            pipelineTasks[jobID] = nil
        }
        pipelineTasks[jobID] = task
    }

    /// 永続化された未完了ジョブを起動時に復元する。
    func restorePipelineJobsIfNeeded() {
        guard !hasRestoredPipelineJobs else { return }
        hasRestoredPipelineJobs = true
        Task {
            do {
                var restored = try await pipelineJobStore.loadAll()
                for index in restored.indices where restored[index].state.isActive {
                    restored[index].state = .waiting
                    restored[index].detail = nil
                    try await pipelineJobStore.upsert(restored[index])
                }
                persistedPipelineJobs = Dictionary(
                    uniqueKeysWithValues: restored.map { ($0.id, $0) }
                )
                pipelineJobs = restored.map(Self.makePipelineJob)
                trimFinishedPipelineJobs()
                for job in restored where job.state == .waiting {
                    startPersistedPipelineJob(job)
                }
                diagnosticLog.info(
                    "永続化された録画後ジョブを復元 count=\(restored.count)"
                )
            } catch {
                diagnosticLog.error(
                    "録画後ジョブの復元失敗 error=\(Self.describeError(error))"
                )
            }
        }
    }

    /// 蓋を閉じる前に外部プロセスと通信を止め、永続キューを再開待ちへ戻す。
    func pausePipelineJobsForSystemSleep() {
        guard !isPipelinePausedForSleep else { return }
        isPipelinePausedForSleep = true
        diagnosticLog.info("システムスリープに備えて録画後処理を一時停止")
        for (id, task) in pipelineTasks {
            task.cancel()
            markPipelineJobWaiting(id: id)
        }
    }

    /// 復帰時にキャンセル完了を待ってから、未完了ジョブを重複なく再開する。
    func resumePipelineJobsAfterSystemWake() {
        guard isPipelinePausedForSleep else { return }
        Task {
            let tasks = Array(pipelineTasks.values)
            for task in tasks {
                await task.value
            }
            pipelineTasks.removeAll()
            isPipelinePausedForSleep = false
            let waitingJobs = persistedPipelineJobs.values
                .filter { $0.state == .waiting }
                .sorted { $0.createdAt < $1.createdAt }
            for job in waitingJobs {
                startPersistedPipelineJob(job)
            }
            diagnosticLog.info(
                "システム復帰後に録画後処理を再開 count=\(waitingJobs.count)"
            )
        }
    }

    private func startPersistedPipelineJob(_ job: PersistedPipelineJob) {
        guard !isPipelinePausedForSleep, pipelineTasks[job.id] == nil else {
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await executePipelineJob(job)
            pipelineTasks[job.id] = nil
        }
        pipelineTasks[job.id] = task
    }

    private func executePipelineJob(_ job: PersistedPipelineJob) async {
        let outputDirectory = job.resolveOutputDirectoryURL()
        let isAccessing = outputDirectory.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                outputDirectory.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let request = PipelineRequest(
                id: job.id,
                fileURL: job.recordingURL,
                outputDirectoryURL: outputDirectory,
                recordingDate: job.recordingDate,
                whisperModelID: job.whisperModelID,
                summaryModelID: job.summaryModelID
            )
            let result = try await pipeline.processRecording(
                request: request
            ) { [weak self] progress in
                await self?.updatePipelineJob(id: job.id, progress: progress)
            }
            await updatePersistedPipelineJob(
                id: job.id,
                state: .completed,
                detail: result.meetingTitle
            )
            updatePipelineJob(
                id: job.id,
                status: .completed(result.meetingTitle)
            )
            await pipelineJobStore.removeWorkDirectory(for: job.id)
            try? await pipelineJobStore.trimFinishedJobs(keeping: 5)
            diagnosticLog.info(
                "録画後パイプライン完了 title=\(result.meetingTitle)"
            )
            loadRecordingHistory()
            sendCompletionNotification(title: result.meetingTitle)
        } catch {
            if Task.isCancelled {
                await updatePersistedPipelineJob(
                    id: job.id,
                    state: .waiting,
                    detail: nil
                )
                updatePipelineJob(id: job.id, status: .waiting)
                diagnosticLog.info("録画後パイプラインを再開待ちに変更")
            } else {
                await updatePersistedPipelineJob(
                    id: job.id,
                    state: .failed,
                    detail: error.localizedDescription
                )
                updatePipelineJob(
                    id: job.id,
                    status: .failed(error.localizedDescription)
                )
                diagnosticLog.error(
                    "録画後パイプライン失敗 error=\(Self.describeError(error))"
                )
            }
        }
    }

    private func updatePipelineJob(
        id: PipelineJob.ID,
        progress: PipelineProgress
    ) async {
        let status: PipelineJobStatus = switch progress {
        case .transcribing: .transcribing
        case .summarizing: .summarizing
        case .saving: .saving
        }
        let state: PersistedPipelineJobState = switch progress {
        case .transcribing: .transcribing
        case .summarizing: .summarizing
        case .saving: .saving
        }
        await updatePersistedPipelineJob(id: id, state: state, detail: nil)
        updatePipelineJob(id: id, status: status)
    }

    private func updatePipelineJob(id: PipelineJob.ID, status: PipelineJobStatus) {
        guard let index = pipelineJobs.firstIndex(where: { $0.id == id }) else { return }
        pipelineJobs[index].status = status
        trimFinishedPipelineJobs()
    }

    private func markPipelineJobWaiting(id: UUID) {
        guard var job = persistedPipelineJobs[id] else { return }
        job.state = .waiting
        job.detail = nil
        persistedPipelineJobs[id] = job
        updatePipelineJob(id: id, status: .waiting)
        Task {
            try? await pipelineJobStore.upsert(job)
        }
    }

    private func updatePersistedPipelineJob(
        id: UUID,
        state: PersistedPipelineJobState,
        detail: String?
    ) async {
        guard var job = persistedPipelineJobs[id] else { return }
        job.state = state
        job.detail = detail
        persistedPipelineJobs[id] = job
        try? await pipelineJobStore.upsert(job)
    }

    private static func makePipelineJob(
        _ persisted: PersistedPipelineJob
    ) -> PipelineJob {
        let status: PipelineJobStatus = switch persisted.state {
        case .waiting:
            .waiting
        case .transcribing:
            .transcribing
        case .summarizing:
            .summarizing
        case .saving:
            .saving
        case .completed:
            .completed(persisted.detail ?? "無題")
        case .failed:
            .failed(persisted.detail ?? "不明なエラー")
        }
        return PipelineJob(
            id: persisted.id,
            createdAt: persisted.createdAt,
            status: status
        )
    }

    /// 実行中の項目は残し、完了・失敗した履歴は直近5件まで表示する。
    private func trimFinishedPipelineJobs() {
        var finishedCount = 0
        pipelineJobs.removeAll { job in
            guard !job.status.isActive else { return false }
            finishedCount += 1
            return finishedCount > 5
        }
    }

    private func releaseRecordingSecurityScopedDirectory() {
        if let url = recordingSecurityScopedDirectory {
            url.stopAccessingSecurityScopedResource()
            recordingSecurityScopedDirectory = nil
        }
    }

    private func refreshWhisperModelAvailability() async {
        guard let modelID = await settings.selectedWhisperModelID,
              !modelID.isEmpty else {
            isWhisperModelReady = false
            return
        }
        isWhisperModelReady = await whisperModelStore.localFileURL(
            forModelID: modelID
        ) != nil
    }

    private func refreshSummaryModelSelection() async {
        guard let modelID = await settings.selectedSummaryModelID else {
            isSummaryModelSet = false
            return
        }
        isSummaryModelSet = !modelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    /// ステータスメニュー表示時に、録画対象のディスプレイ・ウィンドウ一覧を取得する
    func loadShareableContent() {
        Task {
            isLoadingContent = true
            defer { isLoadingContent = false }
            isOutputDirectorySet = await settings.outputDirectoryURL != nil
            await refreshWhisperModelAvailability()
            await refreshSummaryModelSelection()
            loadRecordingHistory()

            guard CGPreflightScreenCaptureAccess() else {
                _ = CGRequestScreenCaptureAccess()
                let appName = Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleDisplayName"
                ) as? String ?? "MeetingScribe"
                errorMessage = "画面収録の許可が必要です。システム設定で\(appName)を許可し、アプリを再起動してください。"
                displayItems = []
                windowItems = []
                diagnosticLog.warning("画面収録権限が未許可のため録画対象を取得できません")
                return
            }

            do {
                let content = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SCShareableContent, Error>) in
                    SCShareableContent.getExcludingDesktopWindows(
                        false,
                        onScreenWindowsOnly: true
                    ) { content, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let content else {
                            continuation.resume(throwing: ShareableContentError.unavailable)
                            return
                        }
                        continuation.resume(returning: content)
                    }
                }
                displayItems = content.displays.map { display in
                    DisplayItem(
                        id: display.displayID,
                        displayID: display.displayID,
                        label: "ディスプレイ \(display.displayID)"
                    )
                }
                windowItems = content.windows
                    .filter { $0.isOnScreen }
                    .filter { !($0.owningApplication?.applicationName ?? "").hasPrefix("Control Center") }
                    .map { window in
                        let appName = window.owningApplication?.applicationName ?? "アプリ"
                        let title = window.title?.isEmpty == false ? window.title! : "（無題）"
                        return WindowItem(
                            id: window.windowID,
                            windowID: window.windowID,
                            label: "\(appName) - \(title)"
                        )
                    }
            } catch {
                errorMessage = "録画対象の取得に失敗しました"
                displayItems = []
                windowItems = []
                diagnosticLog.error("録画対象取得失敗 error=\(Self.describeError(error))")
            }
        }
    }

    /// 出力フォルダ内の完成済み録画を読み取り、アプリをまたいだ履歴を復元する。
    func loadRecordingHistory() {
        Task {
            guard let outputDirectory = await settings.outputDirectoryURL else {
                recordingHistory = []
                return
            }

            isLoadingRecordingHistory = true
            defer { isLoadingRecordingHistory = false }

            let isAccessing = outputDirectory.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    outputDirectory.stopAccessingSecurityScopedResource()
                }
            }

            guard FileManager.default.fileExists(atPath: outputDirectory.path) else {
                recordingHistory = []
                return
            }

            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: outputDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                let fileURLSet = Set(fileURLs.map(\.standardizedFileURL))
                recordingHistory = fileURLs.compactMap { fileURL in
                    makeRecordingHistoryItem(fileURL: fileURL, allFileURLs: fileURLSet)
                }
                .sorted { $0.recordedAt > $1.recordedAt }
                diagnosticLog.info("録画履歴を更新 count=\(recordingHistory.count)")
            } catch {
                recordingHistory = []
                diagnosticLog.error("録画履歴の取得に失敗 error=\(Self.describeError(error))")
            }
        }
    }

    func revealRecordingInFinder(_ item: RecordingHistoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.recordingURL])
    }

    private func makeRecordingHistoryItem(
        fileURL: URL,
        allFileURLs: Set<URL>
    ) -> RecordingHistoryItem? {
        guard Self.recordingExtensions.contains(fileURL.pathExtension.lowercased()) else {
            return nil
        }

        let baseName = fileURL.deletingPathExtension().lastPathComponent
        guard baseName.count > 16 else { return nil }

        let dateText = String(baseName.prefix(15))
        guard let recordedAt = Self.historyDateFormatter.date(from: dateText) else {
            // `recording_...` の一時ファイルは完成済み履歴には含めない。
            return nil
        }

        let titleStart = baseName.index(baseName.startIndex, offsetBy: 16)
        let title = String(baseName[titleStart...]).replacingOccurrences(of: "_", with: " ")
        let directory = fileURL.deletingLastPathComponent()
        let transcriptURL = directory
            .appendingPathComponent("\(baseName)_transcript")
            .appendingPathExtension("md")
            .standardizedFileURL
        let summaryURL = directory
            .appendingPathComponent("\(baseName)_summary")
            .appendingPathExtension("md")
            .standardizedFileURL

        return RecordingHistoryItem(
            recordingURL: fileURL,
            title: title,
            recordedAt: recordedAt,
            hasTranscript: allFileURLs.contains(transcriptURL),
            hasSummary: allFileURLs.contains(summaryURL)
        )
    }

    private nonisolated static func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
    }
}

private enum ShareableContentError: Error {
    case unavailable
}

private enum PipelineJobPreparationError: LocalizedError {
    case settingsUnavailable

    var errorDescription: String? {
        "録画後処理に必要な保存先またはモデル設定を確認できませんでした。"
    }
}
