//
//  RecordingService.swift
//  MeetingScribe
//

import Foundation

protocol RecordingServiceProtocol: Sendable {
    func startRecording(displayID: UInt32?, windowID: UInt32?, outputURL: URL) async throws
    func stopRecording() async throws -> URL
    var isRecording: Bool { get async }
}

/// Placeholder implementation. ScreenCaptureKit integration will be added in 開発手順 3.
final class RecordingService: RecordingServiceProtocol {
    private var _isRecording = false
    private var currentOutputURL: URL?

    var isRecording: Bool {
        get async { _isRecording }
    }

    func startRecording(displayID: UInt32?, windowID: UInt32?, outputURL: URL) async throws {
        guard !_isRecording else { return }
        _isRecording = true
        currentOutputURL = outputURL
    }

    func stopRecording() async throws -> URL {
        guard _isRecording, let url = currentOutputURL else {
            throw RecordingError.notRecording
        }
        _isRecording = false
        currentOutputURL = nil
        return url
    }

    enum RecordingError: Error {
        case notRecording
    }
}
