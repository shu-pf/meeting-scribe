//
//  RecordingResult.swift
//  MeetingScribe
//

import Foundation

struct RecordingResult: Sendable {
    let fileURL: URL
    let startedAt: Date
    let endedAt: Date
    /// 文字起こし結果（TranscriptionService の出力）
    let transcript: String?
    /// 要約結果（SummaryService の出力）
    let summaryText: String?
}
