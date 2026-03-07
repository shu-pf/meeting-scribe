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

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var selectedDisplayID: UInt32?
    @Published var selectedWindowID: UInt32?
    @Published var errorMessage: String?
    @Published var displayItems: [DisplayItem] = []
    @Published var windowItems: [WindowItem] = []
    @Published var isLoadingContent = false

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
                let outputDir: URL
                if let settingsDir = await settings.outputDirectoryURL {
                    settingsDir.startAccessingSecurityScopedResource()
                    securityScopedOutputDirectory = settingsDir
                    outputDir = settingsDir
                } else {
                    outputDir = FileManager.default.temporaryDirectory
                }
                let name = "recording_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).mp4"
                let outputURL = outputDir.appendingPathComponent(name)
                try await recording.startRecording(displayID: selectedDisplayID, windowID: selectedWindowID, outputURL: outputURL)
                isRecording = true
                errorMessage = nil
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
                try await pipeline.processRecording(fileURL: fileURL)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            releaseSecurityScopedOutputDirectory()
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
