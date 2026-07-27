import AVFoundation
import Foundation

@main
private enum LongAudioExtractionCheck {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: check_long_audio_extraction <audio-or-video-path>\n", stderr)
            Foundation.exit(2)
        }

        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        do {
            let sourceDuration = try await AVURLAsset(url: inputURL).load(.duration).seconds
            let wavURL = try await AudioExtractor.extractWAV(from: inputURL)
            defer { try? FileManager.default.removeItem(at: wavURL) }

            let attributes = try FileManager.default.attributesOfItem(atPath: wavURL.path)
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let expectedPCMBytes = UInt64(sourceDuration * 16_000 * 2)
            let tolerance = UInt64(16_000 * 2)

            guard fileSize >= 44,
                  fileSize - 44 >= expectedPCMBytes - min(expectedPCMBytes, tolerance),
                  fileSize - 44 <= expectedPCMBytes + tolerance else {
                throw CheckError.unexpectedSize(
                    actual: fileSize,
                    expected: expectedPCMBytes + 44
                )
            }

            print(
                "PASS: duration=\(sourceDuration)s wavSize=\(fileSize) "
                    + "streaming extraction completed"
            )
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private enum CheckError: LocalizedError {
    case unexpectedSize(actual: UInt64, expected: UInt64)

    var errorDescription: String? {
        switch self {
        case .unexpectedSize(let actual, let expected):
            "WAVサイズが不正です（actual=\(actual), expected≈\(expected)）"
        }
    }
}
