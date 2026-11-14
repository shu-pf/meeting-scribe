//
//  ErrorReportingDisclosure.swift
//  MeetingScribe
//

/// エラーの自動送信で何を送り、何を送らないかの説明。初回セットアップと設定画面で同じ文を使う。
enum ErrorReportingDisclosure {
    static let text =
        "アプリが落ちたときやエラーが起きたときに、エラーの種類と発生箇所、アプリとmacOSのバージョンを開発者（Sentry）へ送ります。"
        + "会議の録画・文字起こし・要約、会議名、ファイル名は送りません。"
}
