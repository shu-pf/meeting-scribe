// エラーレポートへ送る前の伏せ字処理を確認する。
// 実行: ./scripts/run_checks.sh（または下記を直接）
//   xcrun swiftc -parse-as-library scripts/check_privacy_scrubber.swift \
//     MeetingScribe/Services/PrivacyScrubber.swift -o /tmp/check_privacy_scrubber && /tmp/check_privacy_scrubber

import Foundation

@main
struct CheckPrivacyScrubber {
    static func main() {
        let home = NSHomeDirectory()
        var failures: [String] = []

        func expect(_ input: String, _ expected: String, _ label: String) {
            let actual = PrivacyScrubber.scrub(input)
            if actual != expected {
                failures.append("\(label)\n  input:    \(input)\n  expected: \(expected)\n  actual:   \(actual)")
            }
        }

        func expectHidden(_ input: String, _ secrets: [String], _ label: String) {
            let actual = PrivacyScrubber.scrub(input)
            for secret in secrets where actual.contains(secret) {
                failures.append("\(label): \"\(secret)\" が残った\n  actual: \(actual)")
            }
        }

        // 会議名を値に持つキー
        expect(
            "パイプライン処理完了 baseName=2026-11-14_10-00_営業 定例 会議",
            "パイプライン処理完了 baseName=<redacted>",
            "baseName の値（スペース入り）"
        )
        expect(
            "録画後パイプライン完了 title=顧客A 打ち合わせ jobID=1234",
            "録画後パイプライン完了 title=<redacted> jobID=1234",
            "title の後ろのキーは残す"
        )

        // パス
        expect(
            "完成した録画を保存先へ移動 source=\(home)/Library/Application Support/MeetingScribe/Staging/顧客A 定例.mp4 destination=/Volumes/外付け/議事録/顧客A 定例.mp4",
            "完成した録画を保存先へ移動 source=<path> destination=<path>",
            "スペースを含むパスと外部ボリューム"
        )
        expect(
            "モデルが見つからない modelID=large-v3-turbo path=~/Library/Application Support/MeetingScribe/Models/ggml-large-v3-turbo.bin",
            "モデルが見つからない modelID=large-v3-turbo path=<path>",
            "~ から始まるパス"
        )
        expect(
            "録画開始失敗 error=Error Domain=NSCocoaErrorDomain Code=4 UserInfo={NSFilePath=/Users/someone/Documents/会議 (1).mov, NSUnderlyingError=0x600}",
            "録画開始失敗 error=Error Domain=NSCocoaErrorDomain Code=4 UserInfo={NSFilePath=<path>, NSUnderlyingError=0x600}",
            "NSError の UserInfo 内のパス"
        )
        expect(
            "outputURL=file:///Users/someone/Movies/%E4%BC%9A%E8%AD%B0.mp4 status=2",
            "outputURL=<path> status=2",
            "file URL"
        )

        // エラー文に入るファイル名
        expect(
            "録画停止失敗 error=domain=NSCocoaErrorDomain code=4 description=ファイル“顧客A 定例.mp4”は存在しません。",
            "録画停止失敗 error=domain=NSCocoaErrorDomain code=4 description=ファイル“<redacted>”は存在しません。",
            "“…” で囲まれたファイル名"
        )
        expect(
            "description=「定例会議.mp4」を開けませんでした",
            "description=「<redacted>」を開けませんでした",
            "「…」で囲まれたファイル名"
        )

        // ユーザー名
        let userName = NSUserName()
        if userName.count >= 3 {
            expectHidden("whisper の stderr: user \(userName) not permitted", [userName], "ログインユーザー名")
        }

        // 調査に要る情報は残す
        expect(
            "Ollama 接続失敗 attempt=3 code=-1004 stage=finalSummary",
            "Ollama 接続失敗 attempt=3 code=-1004 stage=finalSummary",
            "パスも会議名も無い行は変えない"
        )
        expect(
            "https://api.elevenlabs.io/v1/speech-to-text status=500",
            "https://api.elevenlabs.io/v1/speech-to-text status=500",
            "Web の URL はパスとして扱わない"
        )

        // スタックトレースのイメージパスは、ユーザー名だけを伏せてファイル名を残す
        let imagePath = "\(home)/Downloads/MeetingScribe.app/Contents/MacOS/MeetingScribe"
        if PrivacyScrubber.scrubHomeDirectory(imagePath) != "~/Downloads/MeetingScribe.app/Contents/MacOS/MeetingScribe" {
            failures.append("scrubHomeDirectory: \(PrivacyScrubber.scrubHomeDirectory(imagePath))")
        }
        if PrivacyScrubber.scrubHomeDirectory("/Users/someone-else/Desktop/MeetingScribe.app/Contents/MacOS/MeetingScribe")
            != "~/Desktop/MeetingScribe.app/Contents/MacOS/MeetingScribe" {
            failures.append("scrubHomeDirectory が別ユーザーの /Users/<名前> を残した")
        }
        if PrivacyScrubber.scrubHomeDirectory("/Applications/MeetingScribe.app/Contents/MacOS/MeetingScribe")
            != "/Applications/MeetingScribe.app/Contents/MacOS/MeetingScribe" {
            failures.append("scrubHomeDirectory が /Applications を変えた")
        }

        if failures.isEmpty {
            print("OK: privacy scrubber")
        } else {
            print(failures.joined(separator: "\n\n"))
            exit(1)
        }
    }
}
