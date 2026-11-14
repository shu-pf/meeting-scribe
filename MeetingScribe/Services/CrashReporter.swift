//
//  CrashReporter.swift
//  MeetingScribe
//

import Foundation
import Sentry

/// クラッシュと診断ログのエラーを Sentry へ送る。ユーザーが送信を選んだときだけ動く。
/// 送るのはエラーの種類・スタックトレース・アプリと macOS の版で、
/// 会議の内容・会議名・ファイル名・パスは `PrivacyScrubber` で伏せてから送る。
nonisolated enum CrashReporter {
    private static let preferenceKey = "crashReportingEnabled"

    /// Info.plist の `SentryDSN`。空ならエラーレポートの機能ごと出さない
    static var isAvailable: Bool { dsn != nil }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }

    /// 送信するかをまだ選んでいない。アップデートで来た既存ユーザーは未選択のまま送らない
    static var hasChosen: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) != nil
    }

    private static var dsn: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// アプリ起動時に呼ぶ。送信を選んだユーザーのときだけ SDK を開始する
    static func startIfEnabled() {
        DiagnosticLogForwarder.shared.setHandler { level, category, message in
            forward(level: level, category: category, message: message)
        }
        guard isEnabled else { return }
        start()
        #if DEBUG
        runSelfTestIfRequested()
        #endif
    }

    #if DEBUG
    /// 動作確認用。`-SentrySelfTest` で伏せ字つきのエラーを、`-SentryCrashTest` でクラッシュを起こす
    private static func runSelfTestIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let log = DiagnosticLogger(category: "SelfTest")
        if arguments.contains("-SentrySelfTest") {
            log.info("自己テスト開始 baseName=2026-11-14_1000_顧客A 定例")
            log.error(
                "自己テスト error path=\(NSHomeDirectory())/Movies/顧客A 定例.mp4 "
                + "description=ファイル“顧客A 定例.mp4”は存在しません。 code=4"
            )
            SentrySDK.flush(timeout: 5)
        }
        if arguments.contains("-SentryCrashTest") {
            log.info("クラッシュテスト title=顧客A 定例")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                SentrySDK.crash()
            }
        }
    }
    #endif

    /// 初回セットアップで、送信をオンにした状態の選択肢を見せる
    static func enableByDefaultIfUnchosen() {
        guard isAvailable, !hasChosen else { return }
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled {
            start()
        } else if SentrySDK.isEnabled {
            SentrySDK.close()
        }
    }

    private static func start() {
        guard let dsn, !SentrySDK.isEnabled else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
            options.sendDefaultPii = false
            options.enableUncaughtNSExceptionReporting = true
            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.maxBreadcrumbs = 60
            options.beforeBreadcrumb = { breadcrumb in
                scrub(breadcrumb)
                return breadcrumb
            }
            options.beforeSend = { event in
                scrub(event)
            }
        }
    }

    /// 診断ログの ERROR はイベントとして、INFO・WARN は直前の経緯（パンくず）として送る
    private static func forward(
        level: DiagnosticLogger.Level,
        category: String,
        message: String
    ) {
        guard SentrySDK.isEnabled else { return }
        let scrubbed = PrivacyScrubber.scrub(message)
        switch level {
        case .error:
            SentrySDK.capture(message: scrubbed) { scope in
                scope.setLevel(.error)
                scope.setTag(value: category, key: "category")
            }
        case .warning:
            addBreadcrumb(level: .warning, category: category, message: scrubbed)
        case .info:
            addBreadcrumb(level: .info, category: category, message: scrubbed)
        case .debug:
            break
        }
    }

    private static func addBreadcrumb(
        level: SentryLevel,
        category: String,
        message: String
    ) {
        let breadcrumb = Breadcrumb(level: level, category: category)
        breadcrumb.message = message
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    private static func scrub(_ breadcrumb: Breadcrumb) {
        breadcrumb.message = breadcrumb.message.map(PrivacyScrubber.scrub)
        breadcrumb.data = breadcrumb.data.map(scrubValues)
    }

    private static func scrub(_ event: Event) -> Event {
        if let message = event.message {
            event.message = SentryMessage(formatted: PrivacyScrubber.scrub(message.formatted))
        }
        event.exceptions?.forEach { exception in
            exception.value = exception.value.map(PrivacyScrubber.scrub)
            exception.stacktrace?.frames.forEach(scrub)
        }
        event.threads?.forEach { thread in
            thread.stacktrace?.frames.forEach(scrub)
        }
        event.breadcrumbs?.forEach(scrub)
        event.debugMeta?.forEach { image in
            image.codeFile = image.codeFile.map(PrivacyScrubber.scrubHomeDirectory)
        }
        event.extra = event.extra.map(scrubValues)
        event.serverName = nil
        // IP を明示しないと Sentry が通信元の IP から市区町村まで推定するため、使えない値を入れておく
        let user = event.user ?? User()
        user.ipAddress = "0.0.0.0"
        event.user = user
        event.context?["device"]?["name"] = nil
        return event
    }

    private static func scrub(_ frame: Frame) {
        frame.package = frame.package.map(PrivacyScrubber.scrubHomeDirectory)
        frame.fileName = frame.fileName.map(PrivacyScrubber.scrubHomeDirectory)
    }

    private static func scrubValues(_ values: [String: Any]) -> [String: Any] {
        values.mapValues { value in
            if let text = value as? String {
                return PrivacyScrubber.scrub(text)
            }
            return value
        }
    }
}
