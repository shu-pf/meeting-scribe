//
//  TranscriptionService.swift
//  MeetingScribe
//
//  同梱 Whisper CLI 仕様: docs/WHISPER_CLI.md
//  起動パス: Bundle.main/Contents/Resources/whisper
//  引数: -m <モデル.bin> -otxt -l ja <入力WAV>
//  出力: 標準出力にテキスト
//

import Foundation
import os

private nonisolated func transcriptionLogger() -> Logger {
    Logger(subsystem: "MeetingScribe", category: "Transcription")
}

protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(audioOrVideoURL: URL, modelID: String) async throws -> String
}

final class TranscriptionService: TranscriptionServiceProtocol {
    private let store: WhisperModelStoreProtocol
    private let processTimeout: TimeInterval = 600

    init(store: WhisperModelStoreProtocol = WhisperModelStore.shared) {
        self.store = store
    }

    func transcribe(audioOrVideoURL: URL, modelID: String) async throws -> String {
        try Task.checkCancellation()

        transcriptionLogger().info("transcribe 開始 modelID=\(modelID, privacy: .public) input=\(audioOrVideoURL.path, privacy: .public)")

        let modelURL = await store.localFileURL(forModelID: modelID)
        guard let modelPath = modelURL?.path, FileManager.default.fileExists(atPath: modelPath) else {
            transcriptionLogger().error("モデルが見つからない modelID=\(modelID, privacy: .public) path=\(String(describing: modelURL?.path ?? "nil"), privacy: .public)")
            throw TranscriptionError.modelNotFound(modelID)
        }
        transcriptionLogger().debug("モデルパス modelPath=\(modelPath, privacy: .public)")

        let whisperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/whisper")
        guard FileManager.default.fileExists(atPath: whisperURL.path) else {
            transcriptionLogger().error("whisper バイナリ不在 path=\(whisperURL.path, privacy: .public)")
            throw TranscriptionError.whisperBinaryNotFound
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MeetingScribe/TranscriptionTemp", isDirectory: true)
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeetingScribe/TranscriptionTemp", isDirectory: true)

        transcriptionLogger().debug("NSTemporaryDirectory=\(NSTemporaryDirectory(), privacy: .public) tmpDir=\(tmpDir.path, privacy: .public)")
        transcriptionLogger().debug("cachesDir=\(cachesDir.path, privacy: .public) (Containers=\(cachesDir.path.contains("Containers"), privacy: .public))")

        let inSandbox = tmpDir.path.contains("Containers")
        let transcriptionDir: URL
        if inSandbox {
            try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
            transcriptionDir = cachesDir
            transcriptionLogger().info("WAV 作業ディレクトリ: caches（サンドボックス検出）→ \(cachesDir.path, privacy: .public)")
        } else if (try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)) != nil {
            transcriptionDir = tmpDir
            transcriptionLogger().info("WAV 作業ディレクトリ: tmp → \(tmpDir.path, privacy: .public)")
        } else {
            try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
            transcriptionDir = cachesDir
            transcriptionLogger().info("WAV 作業ディレクトリ: caches（フォールバック）→ \(cachesDir.path, privacy: .public)")
        }

        let wavURL: URL
        if audioOrVideoURL.pathExtension.lowercased() == "wav" {
            wavURL = transcriptionDir.appendingPathComponent(UUID().uuidString + ".wav")
            transcriptionLogger().debug("WAV copy 開始 from=\(audioOrVideoURL.path, privacy: .public) to=\(wavURL.path, privacy: .public)")
            try FileManager.default.copyItem(at: audioOrVideoURL, to: wavURL)
        } else {
            transcriptionLogger().debug("WAV extract 開始 outputDir=\(transcriptionDir.path, privacy: .public)")
            wavURL = try await AudioExtractor.extractWAV(from: audioOrVideoURL, outputDirectory: transcriptionDir)
        }

        var wavURLToUse = wavURL
        let wavExists = FileManager.default.fileExists(atPath: wavURL.path)
        let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: transcriptionDir.path)) ?? []
        transcriptionLogger().info("WAV 作成後 wavURL=\(wavURL.path, privacy: .public) fileExists=\(wavExists, privacy: .public) dirContents=\(dirContents.joined(separator: ", "), privacy: .public)")

        if !wavExists, let singleWav = dirContents.filter({ $0.lowercased().hasSuffix(".wav") }).onlyOne {
            let fallbackURL = transcriptionDir.appendingPathComponent(singleWav)
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                transcriptionLogger().info("fileExists フォールバック: \(singleWav, privacy: .public) を使用")
                wavURLToUse = fallbackURL
            }
        }
        defer { try? FileManager.default.removeItem(at: wavURLToUse) }

        try Task.checkCancellation()

        let resourcesURL = whisperURL.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["DYLD_LIBRARY_PATH"] ?? ""
        let newPath = [resourcesURL.path, existingPath].filter { !$0.isEmpty }.joined(separator: ":")
        env["DYLD_LIBRARY_PATH"] = newPath

        let wavResolved = wavURLToUse.resolvingSymlinksInPath()
        let wavDir = wavResolved.deletingLastPathComponent()
        let wavFileName = wavResolved.lastPathComponent
        let modelResolved = URL(fileURLWithPath: modelPath).resolvingSymlinksInPath()
        let modelPathResolved = modelResolved.path

        let wavExistsResolved = FileManager.default.fileExists(atPath: wavResolved.path)
        transcriptionLogger().info("Process 起動前 wavResolved=\(wavResolved.path, privacy: .public) fileExists=\(wavExistsResolved, privacy: .public) currentDir=\(wavDir.path, privacy: .public) arg=\(wavFileName, privacy: .public)")

        guard wavExistsResolved else {
            transcriptionLogger().error("音声ファイル不在のため throw wavResolved=\(wavResolved.path, privacy: .public)")
            throw TranscriptionError.processFailed(exitCode: -1, stderr: "音声ファイルが存在しません: \(wavResolved.path)")
        }
        guard FileManager.default.fileExists(atPath: modelPathResolved) else {
            transcriptionLogger().error("モデルファイル不在のため throw path=\(modelPathResolved, privacy: .public)")
            throw TranscriptionError.processFailed(exitCode: -1, stderr: "モデルファイルが存在しません: \(modelPathResolved)")
        }

        let process = Process()
        process.executableURL = whisperURL
        process.environment = env
        process.currentDirectoryURL = wavDir
        process.arguments = [
            "-m", modelPathResolved,
            "-otxt",
            "-l", "ja",
            wavFileName,
        ]
        transcriptionLogger().info("Process 起動 executable=\(whisperURL.path, privacy: .public) cwd=\(wavDir.path, privacy: .public) args=\(process.arguments ?? [], privacy: .public)")

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let result: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
            let lock = NSLock()
            final class OnceState: @unchecked Sendable {
                var resumed = false
            }
            let state = OnceState()
            @Sendable func resumeOnce(with r: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !state.resumed else { return }
                state.resumed = true
                switch r {
                case .success(let s): cont.resume(returning: s)
                case .failure(let e): cont.resume(throwing: e)
                }
            }

            process.terminationHandler = { _ in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let text = (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let stderrText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                transcriptionLogger().info("Process 終了 status=\(process.terminationStatus) stdoutLen=\(text.count) stderr=\(stderrText, privacy: .public)")
                if process.terminationStatus == 0 {
                    resumeOnce(with: .success(text))
                } else {
                    resumeOnce(with: .failure(TranscriptionError.processFailed(exitCode: Int(process.terminationStatus), stderr: stderrText.isEmpty ? nil : stderrText)))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(processTimeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                resumeOnce(with: .failure(TranscriptionError.timeout))
            }
        }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        try Task.checkCancellation()
        return result
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotFound(String)
    case whisperBinaryNotFound
    case outputEncodingFailed
    case timeout
    case processFailed(exitCode: Int, stderr: String?)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let id):
            return "文字起こし用のモデル「\(id)」が見つかりません。設定でモデルをダウンロードしてください。"
        case .whisperBinaryNotFound:
            return "Whisper の実行ファイルが見つかりません。scripts/build_whisper.sh を実行してバイナリを用意してください。"
        case .outputEncodingFailed:
            return "文字起こし結果の取得に失敗しました。"
        case .timeout:
            return "文字起こしがタイムアウトしました。"
        case .processFailed(let code, let stderr):
            var msg = "文字起こしに失敗しました（終了コード: \(code)）。"
            if let stderr, !stderr.isEmpty {
                msg += " " + stderr
            }
            return msg
        }
    }
}

private extension Array {
    /// 要素が1つだけならその要素を返し、それ以外は nil。
    var onlyOne: Element? {
        count == 1 ? first : nil
    }
}
