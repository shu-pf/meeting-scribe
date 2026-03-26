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

/// 録画終了後のパイプライン（文字起こし・要約）の状態
enum PipelineStatus: Equatable {
    case idle
    case transcribing
    case summarizing
    case completed
    case failed(String)
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
    @Published var pipelineStatus: PipelineStatus = .idle
    /// 出力フォルダが設定済みか（未設定の場合は録画開始不可）
    @Published var isOutputDirectorySet = false

    private let recording: RecordingServiceProtocol
    private let settings: SettingsServiceProtocol
    private let pipeline: RecordingPipelineProtocol
    /// 録画用のセキュリティスコープ付き出力フォルダ
    private var recordingSecurityScopedDirectory: URL?
    /// 実行中のパイプラインタスク数（0 になったら pipelineStatus を更新可能）
    private var runningPipelineCount = 0

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
        Task {
            do {
                guard let settingsDir = await settings.outputDirectoryURL else {
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
            } catch {
                releaseRecordingSecurityScopedDirectory()
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        Task {
            do {
                let fileURL = try await recording.stopRecording()
                isRecording = false
                errorMessage = nil
                // 録画用のセキュリティスコープを解放し、パイプライン専用に新たに取得する
                releaseRecordingSecurityScopedDirectory()
                runPipelineInBackground(fileURL: fileURL)
            } catch {
                errorMessage = error.localizedDescription
                pipelineStatus = .failed(error.localizedDescription)
                releaseRecordingSecurityScopedDirectory()
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
            runPipelineInBackground(fileURL: fileURL)
        case .failure(let error):
            errorMessage = error.localizedDescription
            pipelineStatus = .failed(error.localizedDescription)
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
        runningPipelineCount += 1
        pipelineStatus = .transcribing
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
                let result = try await pipeline.processRecording(fileURL: fileURL)
                self.runningPipelineCount -= 1
                if self.runningPipelineCount == 0 {
                    self.pipelineStatus = .completed
                }
                self.sendCompletionNotification(title: result.meetingTitle)
            } catch {
                self.runningPipelineCount -= 1
                if self.runningPipelineCount == 0 {
                    self.pipelineStatus = .failed(error.localizedDescription)
                }
                self.errorMessage = error.localizedDescription
            }
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
            }
        }
    }
}

private enum ShareableContentError: Error {
    case unavailable
}
