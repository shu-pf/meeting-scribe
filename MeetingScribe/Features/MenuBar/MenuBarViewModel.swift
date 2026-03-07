//
//  MenuBarViewModel.swift
//  MeetingScribe
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var selectedDisplayID: UInt32?
    @Published var selectedWindowID: UInt32?
    @Published var errorMessage: String?

    private let recording: RecordingServiceProtocol
    private let settings: SettingsServiceProtocol
    private let pipeline: RecordingPipelineProtocol

    init(
        recording: RecordingServiceProtocol = RecordingService(),
        settings: SettingsServiceProtocol = SettingsService(),
        pipeline: RecordingPipelineProtocol? = nil
    ) {
        self.recording = recording
        self.settings = settings
        self.pipeline = pipeline ?? RecordingPipeline(
            transcription: TranscriptionService(),
            summary: SummaryService(),
            settings: settings
        )
    }

    func startRecording() {
        Task {
            do {
                let outputDir = await settings.outputDirectoryURL ?? FileManager.default.temporaryDirectory
                let name = "recording_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).mp4"
                let outputURL = outputDir.appendingPathComponent(name)
                try await recording.startRecording(displayID: selectedDisplayID, windowID: selectedWindowID, outputURL: outputURL)
                isRecording = true
                errorMessage = nil
            } catch {
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
        }
    }
}
