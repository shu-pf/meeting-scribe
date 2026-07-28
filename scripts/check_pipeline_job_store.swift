import Foundation

@main
private enum PipelineJobStoreCheck {
    static func main() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MeetingScribe-pipeline-store-check-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: root) }

        do {
            let id = UUID()
            let createdAt = Date(timeIntervalSinceReferenceDate: 100)
            let legacyData = try JSONEncoder().encode(
                LegacyPersistedPipelineJob(
                    id: id,
                    createdAt: createdAt,
                    recordingDate: createdAt,
                    recordingPath: "/tmp/recording.mp4",
                    outputDirectoryPath: "/tmp",
                    outputDirectoryBookmark: nil,
                    whisperModelID: "whisper",
                    summaryModelID: "summary",
                    state: .summarizing,
                    detail: nil
                )
            )
            let decodedLegacy = try JSONDecoder().decode(
                PersistedPipelineJob.self,
                from: legacyData
            )
            try require(
                decodedLegacy.stateUpdatedAt == nil,
                "旧形式のジョブを読み込めませんでした"
            )

            let stateUpdatedAt = Date(timeIntervalSinceReferenceDate: 200)
            var current = decodedLegacy
            current.stateUpdatedAt = stateUpdatedAt
            let store = PipelineJobStore(
                baseDirectory: root,
                fileManager: fileManager
            )
            try await store.upsert(current)

            let loaded = try await store.loadAll()
            try require(loaded.count == 1, "保存したジョブを読み込めませんでした")
            try require(loaded[0].id == id, "保存したジョブIDが一致しません")
            try require(
                loaded[0].stateUpdatedAt == stateUpdatedAt,
                "フェーズ更新時刻が永続化されませんでした"
            )

            print("PASS: 旧ジョブ互換性とフェーズ更新時刻の永続化")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckError.failed(message)
        }
    }

    private enum CheckError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                message
            }
        }
    }
}

private struct LegacyPersistedPipelineJob: Codable {
    let id: UUID
    let createdAt: Date
    let recordingDate: Date
    let recordingPath: String
    let outputDirectoryPath: String
    let outputDirectoryBookmark: Data?
    let whisperModelID: String
    let summaryModelID: String
    let state: PersistedPipelineJobState
    let detail: String?
}
