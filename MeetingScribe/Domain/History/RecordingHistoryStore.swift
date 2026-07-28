//
//  RecordingHistoryStore.swift
//  MeetingScribe
//

import Foundation

nonisolated struct PersistedRecordingHistoryItem: Codable, Identifiable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let recordedAt: Date
    let title: String
    let recordingPath: String
    let recordingBookmark: Data?
    let transcriptPath: String?
    let transcriptBookmark: Data?
    let summaryPath: String?
    let summaryBookmark: Data?

    init(
        id: UUID,
        recordedAt: Date,
        title: String,
        recordingURL: URL,
        transcriptURL: URL?,
        summaryURL: URL?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.recordedAt = recordedAt
        self.title = title
        self.recordingPath = recordingURL.path
        self.recordingBookmark = Self.makeBookmark(for: recordingURL)
        self.transcriptPath = transcriptURL?.path
        self.transcriptBookmark = transcriptURL.flatMap(Self.makeBookmark)
        self.summaryPath = summaryURL?.path
        self.summaryBookmark = summaryURL.flatMap(Self.makeBookmark)
    }

    var recordingURL: URL {
        Self.resolveURL(bookmark: recordingBookmark, fallbackPath: recordingPath)
    }

    var transcriptURL: URL? {
        Self.resolveOptionalURL(
            bookmark: transcriptBookmark,
            fallbackPath: transcriptPath
        )
    }

    var summaryURL: URL? {
        Self.resolveOptionalURL(
            bookmark: summaryBookmark,
            fallbackPath: summaryPath
        )
    }

    private static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveOptionalURL(
        bookmark: Data?,
        fallbackPath: String?
    ) -> URL? {
        guard let fallbackPath else { return nil }
        return resolveURL(bookmark: bookmark, fallbackPath: fallbackPath)
    }

    private static func resolveURL(
        bookmark: Data?,
        fallbackPath: String
    ) -> URL {
        guard let bookmark else {
            return URL(fileURLWithPath: fallbackPath)
        }
        var isStale = false
        return (try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )) ?? URL(fileURLWithPath: fallbackPath)
    }
}

nonisolated enum RecordingHistoryWorkspace {
    static func rootDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return applicationSupportDirectory
            .appendingPathComponent("MeetingScribe", isDirectory: true)
            .appendingPathComponent("RecordingHistory", isDirectory: true)
    }
}

actor RecordingHistoryStore {
    private static let recordingExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let recordsDirectory: URL
    private let legacyMigrationMarkerURL: URL

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = baseDirectory
            ?? (try? RecordingHistoryWorkspace.rootDirectory(fileManager: fileManager))
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("MeetingScribe/RecordingHistory", isDirectory: true)
        self.recordsDirectory = rootDirectory
            .appendingPathComponent("Records", isDirectory: true)
        self.legacyMigrationMarkerURL = rootDirectory
            .appendingPathComponent("legacy-output-folder-import-v1")
    }

    func loadAll() throws -> [PersistedRecordingHistoryItem] {
        guard fileManager.fileExists(atPath: recordsDirectory.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: recordsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(
                PersistedRecordingHistoryItem.self,
                from: data
            )
        }
        .sorted { $0.recordedAt > $1.recordedAt }
    }

    func upsert(_ item: PersistedRecordingHistoryItem) throws {
        try fileManager.createDirectory(
            at: recordsDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(item)
        try data.write(to: recordURL(for: item.id), options: .atomic)
    }

    func remove(id: UUID) throws {
        let url = recordURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// v1.4.0以前の履歴を現在の保存先から一度だけ取り込む。
    @discardableResult
    func importLegacyRecordingsIfNeeded(from outputDirectory: URL) throws -> Int {
        guard !fileManager.fileExists(atPath: legacyMigrationMarkerURL.path) else {
            return 0
        }
        guard fileManager.fileExists(atPath: outputDirectory.path) else {
            return 0
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let standardizedURLs = Set(fileURLs.map(\.standardizedFileURL))
        var knownRecordingPaths = Set(
            try loadAll().map { Self.canonicalPath($0.recordingURL) }
        )
        var importedCount = 0

        for recordingURL in fileURLs {
            guard let item = Self.makeLegacyItem(
                recordingURL: recordingURL,
                allFileURLs: standardizedURLs
            ) else {
                continue
            }
            let path = Self.canonicalPath(item.recordingURL)
            guard knownRecordingPaths.insert(path).inserted else { continue }
            try upsert(item)
            importedCount += 1
        }

        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Data().write(to: legacyMigrationMarkerURL, options: .atomic)
        return importedCount
    }

    private func recordURL(for id: UUID) -> URL {
        recordsDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("json")
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func makeLegacyItem(
        recordingURL: URL,
        allFileURLs: Set<URL>
    ) -> PersistedRecordingHistoryItem? {
        guard recordingExtensions.contains(
            recordingURL.pathExtension.lowercased()
        ) else {
            return nil
        }

        let baseName = recordingURL.deletingPathExtension().lastPathComponent
        guard baseName.count > 16 else { return nil }
        let dateText = String(baseName.prefix(15))
        guard let recordedAt = dateFormatter.date(from: dateText) else {
            return nil
        }

        let titleStart = baseName.index(baseName.startIndex, offsetBy: 16)
        let title = String(baseName[titleStart...])
            .replacingOccurrences(of: "_", with: " ")
        let directory = recordingURL.deletingLastPathComponent()
        let transcriptURL = directory
            .appendingPathComponent("\(baseName)_transcript")
            .appendingPathExtension("md")
            .standardizedFileURL
        let summaryURL = directory
            .appendingPathComponent("\(baseName)_summary")
            .appendingPathExtension("md")
            .standardizedFileURL

        return PersistedRecordingHistoryItem(
            id: UUID(),
            recordedAt: recordedAt,
            title: title,
            recordingURL: recordingURL,
            transcriptURL: allFileURLs.contains(transcriptURL) ? transcriptURL : nil,
            summaryURL: allFileURLs.contains(summaryURL) ? summaryURL : nil
        )
    }
}
