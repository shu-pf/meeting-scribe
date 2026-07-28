import Foundation

@main
private enum RecordingHistoryStoreCheck {
    static func main() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MeetingScribe-history-check-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: root) }

        do {
            let storeDirectory = root.appendingPathComponent(
                "Store",
                isDirectory: true
            )
            let firstOutput = root.appendingPathComponent(
                "Output-A",
                isDirectory: true
            )
            let secondOutput = root.appendingPathComponent(
                "Output-B",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: firstOutput,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: secondOutput,
                withIntermediateDirectories: true
            )

            let firstBaseName = "2026-07-28_1200_最初の会議"
            let firstRecording = firstOutput
                .appendingPathComponent(firstBaseName)
                .appendingPathExtension("mp4")
            let firstTranscript = firstOutput
                .appendingPathComponent("\(firstBaseName)_transcript")
                .appendingPathExtension("md")
            let firstSummary = firstOutput
                .appendingPathComponent("\(firstBaseName)_summary")
                .appendingPathExtension("md")
            try Data("video".utf8).write(to: firstRecording)
            try Data("transcript".utf8).write(to: firstTranscript)
            try Data("summary".utf8).write(to: firstSummary)

            let store = RecordingHistoryStore(
                baseDirectory: storeDirectory,
                fileManager: fileManager
            )
            let imported = try await store.importLegacyRecordingsIfNeeded(
                from: firstOutput
            )
            try require(imported == 1, "従来履歴を1件取り込めませんでした")

            var items = try await store.loadAll()
            try require(items.count == 1, "取り込んだ履歴を読み込めませんでした")
            try require(items[0].title == "最初の会議", "会議名の移行に失敗しました")
            try require(
                items[0].transcriptURL?.standardizedFileURL
                    == firstTranscript.standardizedFileURL,
                "文字起こしの関連付けに失敗しました"
            )
            try require(
                items[0].summaryURL?.standardizedFileURL
                    == firstSummary.standardizedFileURL,
                "要約の関連付けに失敗しました"
            )

            let ignoredLegacyRecording = secondOutput
                .appendingPathComponent("2026-07-28_1230_移行対象外")
                .appendingPathExtension("mp4")
            try Data("video".utf8).write(to: ignoredLegacyRecording)
            let secondImport = try await store.importLegacyRecordingsIfNeeded(
                from: secondOutput
            )
            try require(secondImport == 0, "初回移行が二重に実行されました")

            let secondRecording = secondOutput
                .appendingPathComponent("2026-07-28_1300_新しい保存先")
                .appendingPathExtension("mp4")
            try Data("video".utf8).write(to: secondRecording)
            let secondID = UUID()
            let secondItem = PersistedRecordingHistoryItem(
                id: secondID,
                recordedAt: Date(),
                title: "新しい保存先",
                recordingURL: secondRecording,
                transcriptURL: nil,
                summaryURL: nil
            )
            try await store.upsert(secondItem)

            let reloadedStore = RecordingHistoryStore(
                baseDirectory: storeDirectory,
                fileManager: fileManager
            )
            items = try await reloadedStore.loadAll()
            try require(
                items.count == 2,
                "保存先変更前後の履歴が永続化されませんでした"
            )
            let storedPaths = Set(items.map {
                canonicalPath($0.recordingURL)
            })
            try require(
                storedPaths.contains(canonicalPath(firstRecording)),
                "変更前の保存先にある履歴が失われました"
            )
            try require(
                storedPaths.contains(canonicalPath(secondRecording)),
                "変更後の保存先にある履歴が失われました"
            )

            try fileManager.removeItem(at: firstRecording)
            items = try await reloadedStore.loadAll()
            try require(
                items.contains { $0.title == "最初の会議" },
                "実ファイル削除時に履歴まで失われました"
            )
            let missingItem = try requireValue(
                items.first { $0.title == "最初の会議" },
                "欠損確認対象の履歴がありません"
            )
            try require(
                !fileManager.fileExists(atPath: missingItem.recordingURL.path),
                "削除済み録画が利用可能として解決されました"
            )

            try await reloadedStore.remove(id: secondID)
            items = try await reloadedStore.loadAll()
            try require(items.count == 1, "履歴メタデータを削除できませんでした")

            print("PASS: 録画履歴の移行・永続化・保存先変更・欠損保持・削除")
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

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func requireValue<T>(
        _ value: T?,
        _ message: String
    ) throws -> T {
        guard let value else {
            throw CheckError.failed(message)
        }
        return value
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
