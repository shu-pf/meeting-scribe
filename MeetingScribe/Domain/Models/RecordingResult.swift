//
//  RecordingResult.swift
//  MeetingScribe
//

import Foundation

struct RecordingResult: Sendable {
    let fileURL: URL
    let startedAt: Date
    let endedAt: Date
}
