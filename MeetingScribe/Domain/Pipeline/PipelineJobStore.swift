//
//  PipelineJobStore.swift
//  MeetingScribe
//

import Foundation

nonisolated enum PersistedPipelineJobState: String, Codable, Sendable {
    case waiting
    case transcribing
    case summarizing
    case saving
    case completed
    case failed

    var isActive: Bool {
        switch self {
        case .waiting, .transcribing, .summarizing, .saving:
            true
        case .completed, .failed:
            false
        }
    }
}

nonisolated struct PersistedPipelineJob: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let recordingDate: Date
    let recordingPath: String
    let outputDirectoryPath: String
    let outputDirectoryBookmark: Data?
    let whisperModelID: String
    let summaryModelID: String
    var state: PersistedPipelineJobState
    var detail: String?

    var recordingURL: URL {
        URL(fileURLWithPath: recordingPath)
    }

    func resolveOutputDirectoryURL() -> URL {
        guard let outputDirectoryBookmark else {
            return URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        }
        var isStale = false
        return (try? URL(
            resolvingBookmarkData: outputDirectoryBookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )) ?? URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
    }
}

nonisolated enum PipelineWorkspace {
    static func rootDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return applicationSupportDirectory
            .appendingPathComponent("MeetingScribe", isDirectory: true)
            .appendingPathComponent("PipelineJobs", isDirectory: true)
    }

    static func workDirectory(
        for jobID: UUID,
        fileManager: FileManager = .default
    ) throws -> URL {
        try rootDirectory(fileManager: fileManager)
            .appendingPathComponent("Work", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
    }
}

actor PipelineJobStore {
    private let fileManager: FileManager
    private let manifestsDirectory: URL

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let root = baseDirectory
            ?? (try? PipelineWorkspace.rootDirectory(fileManager: fileManager))
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("MeetingScribe/PipelineJobs", isDirectory: true)
        self.manifestsDirectory = root.appendingPathComponent(
            "Manifests",
            isDirectory: true
        )
    }

    func loadAll() throws -> [PersistedPipelineJob] {
        guard fileManager.fileExists(atPath: manifestsDirectory.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: manifestsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(PersistedPipelineJob.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func upsert(_ job: PersistedPipelineJob) throws {
        try fileManager.createDirectory(
            at: manifestsDirectory,
            withIntermediateDirectories: true
        )
        let destination = manifestURL(for: job.id)
        let data = try JSONEncoder().encode(job)
        try data.write(to: destination, options: .atomic)
    }

    func removeWorkDirectory(for jobID: UUID) {
        guard let directory = try? PipelineWorkspace.workDirectory(
            for: jobID,
            fileManager: fileManager
        ) else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    func trimFinishedJobs(keeping maximumCount: Int) throws {
        let finished = try loadAll()
            .filter { !$0.state.isActive }
            .sorted { $0.createdAt > $1.createdAt }
        for job in finished.dropFirst(maximumCount) {
            try? fileManager.removeItem(at: manifestURL(for: job.id))
            removeWorkDirectory(for: job.id)
        }
    }

    private func manifestURL(for jobID: UUID) -> URL {
        manifestsDirectory
            .appendingPathComponent(jobID.uuidString)
            .appendingPathExtension("json")
    }
}
