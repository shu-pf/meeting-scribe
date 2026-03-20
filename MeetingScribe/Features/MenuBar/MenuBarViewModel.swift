//
//  MenuBarViewModel.swift
//  MeetingScribe
//

import Combine
import Foundation
import ScreenCaptureKit
import SwiftUI

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
    /// 録画・パイプラインで使用中のセキュリティスコープ付き出力フォルダ（stop 時に stopAccessingSecurityScopedResource するため保持）
    private var securityScopedOutputDirectory: URL?

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
                securityScopedOutputDirectory = settingsDir
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
                pipelineStatus = .idle
            } catch {
                releaseSecurityScopedOutputDirectory()
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
                pipelineStatus = .transcribing
                do {
                    try await pipeline.processRecording(fileURL: fileURL)
                    pipelineStatus = .completed
                } catch {
                    pipelineStatus = .failed(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
                pipelineStatus = .failed(error.localizedDescription)
            }
            releaseSecurityScopedOutputDirectory()
        }
    }

    /// ストリームが予期せず停止したとき（例: 録画元ウィンドウが閉じられたとき）にコールバックから呼ばれる。録画終了と同様にパイプラインを実行する。
    private func handleStreamStoppedUnexpectedly(result: Result<URL, Error>) {
        isRecording = false
        releaseSecurityScopedOutputDirectory()
        switch result {
        case .success(let fileURL):
            errorMessage = nil
            pipelineStatus = .transcribing
            Task {
                do {
                    try await pipeline.processRecording(fileURL: fileURL)
                    pipelineStatus = .completed
                } catch {
                    pipelineStatus = .failed(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            pipelineStatus = .failed(error.localizedDescription)
        }
    }

    private func releaseSecurityScopedOutputDirectory() {
        if let url = securityScopedOutputDirectory {
            url.stopAccessingSecurityScopedResource()
            securityScopedOutputDirectory = nil
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
