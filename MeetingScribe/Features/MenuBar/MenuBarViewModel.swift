//
//  MenuBarViewModel.swift
//  MeetingScribe
//

import Combine
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

    private let recording: RecordingServiceProtocol
    private let settings: SettingsServiceProtocol
    private let pipeline: RecordingPipelineProtocol
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

    init(
        recording: RecordingServiceProtocol? = nil,
        settings: SettingsServiceProtocol? = nil,
        pipeline: RecordingPipelineProtocol? = nil
    ) {
        let settingsInstance = settings ?? SettingsService()
        self.recording = recording ?? RecordingService()
        self.settings = settingsInstance
        self.pipeline = pipeline ?? RecordingPipeline(
            transcription: TranscriptionService(),
            summary: SummaryService(),
            settings: settingsInstance
        )
    }

    func startRecording() {
        diagnosticLog.info(
            "録画開始操作 displayID=\(String(describing: selectedDisplayID)) windowID=\(String(describing: selectedWindowID))"
        )
        Task {
            do {
                guard let settingsDir = await settings.outputDirectoryURL else {
                    diagnosticLog.error("録画開始失敗: 出力フォルダ未設定")
                    errorMessage = "出力フォルダが未設定です。設定から出力フォルダを選択してください。"
                    return
                }
                _ = settingsDir.startAccessingSecurityScopedResource()
                recordingSecurityScopedDirectory = settingsDir
                let outputDir = settingsDir
                let name = "recording_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).mp4"
                let outputURL = outputDir.appendingPathComponent(name)
                try await recording.startRecording(
                    displayID: selectedDisplayID,
                    windowID: selectedWindowID,
                    outputURL: outputURL,
                    onStreamStoppedUnexpectedly: { [weak self] result in
                        guard let self else { return }
                        Task { @MainActor in
                            self.handleStreamStoppedUnexpectedly(result: result)
                        }
                    }
                )
                isRecording = true
                errorMessage = nil
                diagnosticLog.info("録画中状態へ遷移 outputURL=\(outputURL.path)")
            } catch {
                releaseRecordingSecurityScopedDirectory()
                errorMessage = error.localizedDescription
                diagnosticLog.error("録画開始失敗 error=\(Self.describeError(error))")
            }
        }
    }

    func stopRecording() {
        diagnosticLog.info("録画停止操作")
        Task {
            do {
                let fileURL = try await recording.stopRecording()
                isRecording = false
                errorMessage = nil
                // 録画用のセキュリティスコープを解放し、パイプライン専用に新たに取得する
                releaseRecordingSecurityScopedDirectory()
                runPipelineInBackground(fileURL: fileURL)
                diagnosticLog.info("録画停止成功 fileURL=\(fileURL.path)")
            } catch {
                errorMessage = error.localizedDescription
                releaseRecordingSecurityScopedDirectory()
                diagnosticLog.error("録画停止失敗 error=\(Self.describeError(error))")
            }
        }
    }

    /// ストリームが予期せず停止したとき（例: 録画元ウィンドウが閉じられたとき）にコールバックから呼ばれる。録画終了と同様にパイプラインを実行する。
    private func handleStreamStoppedUnexpectedly(result: Result<URL, Error>) {
        isRecording = false
        releaseRecordingSecurityScopedDirectory()
        switch result {
        case .success(let fileURL):
            errorMessage = nil
            diagnosticLog.warning("録画ストリームが予期せず停止 fileURL=\(fileURL.path)")
            runPipelineInBackground(fileURL: fileURL)
        case .failure(let error):
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

    /// パイプライン処理をバックグラウンドで実行する。新しい録画の開始に影響されない独立した Task として動かす。
    private func runPipelineInBackground(fileURL: URL) {
        let job = PipelineJob(id: UUID(), createdAt: Date(), status: .waiting)
        pipelineJobs.insert(job, at: 0)
        trimFinishedPipelineJobs()
        diagnosticLog.info("録画後パイプライン開始 fileURL=\(fileURL.path)")
        Task { [pipeline, settings] in
            // パイプライン専用にセキュリティスコープ付き URL を取得する
            let scopedDir = await settings.outputDirectoryURL
            if let dir = scopedDir {
                _ = dir.startAccessingSecurityScopedResource()
            }
            defer {
                scopedDir?.stopAccessingSecurityScopedResource()
            }
            do {
                let result = try await pipeline.processRecording(fileURL: fileURL) { [weak self] progress in
                    await self?.updatePipelineJob(id: job.id, progress: progress)
                }
                self.updatePipelineJob(id: job.id, status: .completed(result.meetingTitle))
                self.diagnosticLog.info(
                    "録画後パイプライン完了 title=\(result.meetingTitle)"
                )
                self.loadRecordingHistory()
                self.sendCompletionNotification(title: result.meetingTitle)
            } catch {
                self.updatePipelineJob(id: job.id, status: .failed(error.localizedDescription))
                self.diagnosticLog.error(
                    "録画後パイプライン失敗 error=\(Self.describeError(error))"
                )
            }
        }
    }

    private func updatePipelineJob(id: PipelineJob.ID, progress: PipelineProgress) {
        let status: PipelineJobStatus = switch progress {
        case .transcribing: .transcribing
        case .summarizing: .summarizing
        case .saving: .saving
        }
        updatePipelineJob(id: id, status: status)
    }

    private func updatePipelineJob(id: PipelineJob.ID, status: PipelineJobStatus) {
        guard let index = pipelineJobs.firstIndex(where: { $0.id == id }) else { return }
        pipelineJobs[index].status = status
        trimFinishedPipelineJobs()
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

    /// ステータスメニュー表示時に、録画対象のディスプレイ・ウィンドウ一覧を取得する
    func loadShareableContent() {
        Task {
            isLoadingContent = true
            defer { isLoadingContent = false }
            isOutputDirectorySet = await settings.outputDirectoryURL != nil
            loadRecordingHistory()
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
