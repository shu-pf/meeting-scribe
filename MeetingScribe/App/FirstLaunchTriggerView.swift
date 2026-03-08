//
//  FirstLaunchTriggerView.swift
//  MeetingScribe
//

import SwiftUI
import AppKit

/// アプリ起動時に一度だけ表示され、初回なら設定ウィンドウを開く。
/// MenuBarExtra の label に仕込むことで、メニューを開かなくても起動時に実行される。
struct FirstLaunchTriggerView: View {
    @Environment(\.openWindow) private var openWindow
    private let settings = SettingsService()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                if await !settings.hasSeenFirstLaunchGuidance {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings", value: "main")
                }
            }
    }
}
