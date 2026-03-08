//
//  ContentView.swift
//  MeetingScribe
//
//  Created by Furuse Shugo on 2026/03/07.
//

import SwiftUI

/// 設定ウィンドウのルート。アプリクリックで開くメインウィンドウに表示する。
struct ContentView: View {
    @State private var showFirstLaunchGuidance = false
    @State private var triggerWhisperSheetAfterGuidance = false
    private let settings = SettingsService()

    var body: some View {
        SettingsView(triggerWhisperSheetAfterGuidance: $triggerWhisperSheetAfterGuidance)
            .task {
                guard await !settings.hasSeenFirstLaunchGuidance else { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
                showFirstLaunchGuidance = true
            }
            .sheet(isPresented: $showFirstLaunchGuidance) {
                FirstLaunchGuidanceView {
                    Task {
                        await settings.setHasSeenFirstLaunchGuidance(true)
                        showFirstLaunchGuidance = false
                        triggerWhisperSheetAfterGuidance = true
                    }
                }
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 480, height: 400)
}
