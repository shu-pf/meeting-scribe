//
//  DiagnosticLogger.swift
//  MeetingScribe
//

import Foundation
import os

/// OSLog とローカルファイルの両方へ書き込む診断ロガー。
/// 会議内容は記録せず、処理状態・エラー・ファイルパスなど調査に必要なメタデータだけを扱う。
struct DiagnosticLogger: Sendable {
    enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let category: String
    private let systemLogger: Logger

    init(category: String) {
        self.category = category
        self.systemLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "MeetingScribe",
            category: category
        )
    }

    func debug(_ message: @autoclosure () -> String) {
        let message = message()
        systemLogger.debug("\(message, privacy: .public)")
    }

    func info(_ message: @autoclosure () -> String) {
        write(level: .info, message: message())
    }

    func warning(_ message: @autoclosure () -> String) {
        write(level: .warning, message: message())
    }

    func error(_ message: @autoclosure () -> String) {
        write(level: .error, message: message())
    }

    private func write(level: Level, message: String) {
        switch level {
        case .debug:
            break
        case .info:
            systemLogger.info("\(message, privacy: .public)")
        case .warning:
            systemLogger.warning("\(message, privacy: .public)")
        case .error:
            systemLogger.error("\(message, privacy: .public)")
        }
        if level != .debug {
            DiagnosticLogStore.shared.append(level: level, category: category, message: message)
        }
    }
}

/// 診断ログファイルの保存・ローテーションを直列化する。
final class DiagnosticLogStore: @unchecked Sendable {
    static let shared = DiagnosticLogStore()

    static var logDirectoryURL: URL {
        shared.directoryURL
    }

    static var currentLogURL: URL {
        shared.fileURL
    }

    private let queue = DispatchQueue(label: "MeetingScribe.diagnostic-log")
    private let directoryURL: URL
    private let fileURL: URL
    private let dateFormatter = ISO8601DateFormatter()
    private let maxFileSize: UInt64 = 5 * 1_024 * 1_024
    private let backupCount = 3
    private let fallbackLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MeetingScribe",
        category: "DiagnosticLog"
    )

    private init() {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        self.directoryURL = applicationSupport
            .appendingPathComponent("MeetingScribe", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)

        let bundleID = Bundle.main.bundleIdentifier ?? "MeetingScribe"
        self.fileURL = directoryURL
            .appendingPathComponent("\(bundleID).log", isDirectory: false)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: fileURL.path) {
                _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
        } catch {
            fallbackLogger.error(
                "診断ログの初期化に失敗しました error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func append(level: DiagnosticLogger.Level, category: String, message: String) {
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: Date())
            let sanitizedMessage = message.replacingOccurrences(of: "\n", with: "\\n")
            let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(sanitizedMessage)\n"
            guard let data = line.data(using: .utf8) else { return }

            do {
                try rotateIfNeeded(addingByteCount: UInt64(data.count))
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                try fileHandle.close()
            } catch {
                fallbackLogger.error(
                    "診断ログの書き込みに失敗しました error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// テストや終了処理で、キューに入っている書き込みの完了を待つ。
    func flush() {
        queue.sync {}
    }

    private func rotateIfNeeded(addingByteCount: UInt64) throws {
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + addingByteCount > maxFileSize else { return }

        let oldestURL = backupURL(index: backupCount)
        if fileManager.fileExists(atPath: oldestURL.path) {
            try fileManager.removeItem(at: oldestURL)
        }

        if backupCount > 1 {
            for index in stride(from: backupCount - 1, through: 1, by: -1) {
                let sourceURL = backupURL(index: index)
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
                try fileManager.moveItem(at: sourceURL, to: backupURL(index: index + 1))
            }
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.moveItem(at: fileURL, to: backupURL(index: 1))
        }
        _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    private func backupURL(index: Int) -> URL {
        URL(fileURLWithPath: "\(fileURL.path).\(index)")
    }
}
