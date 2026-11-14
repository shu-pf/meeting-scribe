//
//  PrivacyScrubber.swift
//  MeetingScribe
//

import Foundation

/// エラーレポートへ送る文字列から、会議名・ファイル名・パス・ユーザー名を伏せる。
/// 会議名は録画ファイル名（`<日時>_<会議名>`）に入るため、パスとファイル名はすべて伏せる。
nonisolated enum PrivacyScrubber {
    static let redactedPath = "<path>"
    static let redacted = "<redacted>"
    static let redactedUser = "<user>"

    /// 値に会議名が入るログのキー。会議名を出すキーを足したらここにも加える
    static let sensitiveKeys = ["baseName", "title", "meetingTitle", "fileName"]

    /// 次の `key=value` の直前、区切り文字、行末で値が終わる
    private static let valueEnd = #"(?=\s+[A-Za-z_][A-Za-z0-9_.]*=|$|\n)"#

    private static let sensitiveValuePattern = try! NSRegularExpression(
        pattern: #"\b("# + sensitiveKeys.joined(separator: "|") + #")=[^\n]*?"# + valueEnd
    )

    /// 絶対パス・`~` から始まるパス・file URL。スペースを含むファイル名もまとめて伏せる
    private static let pathPattern = try! NSRegularExpression(
        pattern: #"(?:file://)?(?:~|/(?:Users|Volumes|private|var|tmp|Applications|Library|System|opt|cores))/[^\n]*?(?=\s+[A-Za-z_][A-Za-z0-9_.]*=|[,;"'}\n”」]|$)"#
    )

    /// Cocoa のエラー文はファイル名を “…” で囲む。日本語の 「…」 も同じに扱う
    private static let quotedNamePatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"“[^”\n]*”"#), "“\(redacted)”"),
        (try! NSRegularExpression(pattern: #"「[^」\n]*」"#), "「\(redacted)」"),
    ]

    static func scrub(_ text: String) -> String {
        var result = replace(sensitiveValuePattern, in: text, with: "$1=\(redacted)")
        result = replace(pathPattern, in: result, with: redactedPath)
        for (pattern, template) in quotedNamePatterns {
            result = replace(pattern, in: result, with: template)
        }
        for token in identifyingTokens {
            result = result.replacingOccurrences(of: token, with: redactedUser)
        }
        return result
    }

    /// バイナリの場所（スタックトレースのイメージパス）から、ホームディレクトリのユーザー名だけを伏せる。
    /// ファイル名はアプリやフレームワークの名前なので残す
    static func scrubHomeDirectory(_ path: String) -> String {
        let home = NSHomeDirectory()
        if !home.isEmpty, path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return replace(userDirectoryPattern, in: path, with: "~")
    }

    /// ホームディレクトリと一致しなくても、`/Users/<名前>` はユーザー名なので伏せる
    private static let userDirectoryPattern = try! NSRegularExpression(
        pattern: #"^(?:/private)?/Users/[^/]+"#
    )

    /// ホームディレクトリ名とログインユーザー名。短すぎる名前は普通の語を壊すので対象にしない
    private static let identifyingTokens: [String] = {
        let candidates = [NSHomeDirectory(), NSUserName(), NSFullUserName()]
        return Array(Set(candidates.filter { $0.count >= 3 }))
            .sorted { $0.count > $1.count }
    }()

    private static func replace(
        _ pattern: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }
}
