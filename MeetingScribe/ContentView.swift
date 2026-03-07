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
    private let settings = SettingsService()

    var body: some View {
        SettingsView()
            .task {
                if await !settings.hasSeenFirstLaunchGuidance {
                    showFirstLaunchGuidance = true
                }
            }
            .sheet(isPresented: $showFirstLaunchGuidance) {
                FirstLaunchGuidanceView {
                    Task {
                        await settings.setHasSeenFirstLaunchGuidance(true)
                        showFirstLaunchGuidance = false
                    }
                }
            }
    }
}

#Preview {
    ContentView()
}
