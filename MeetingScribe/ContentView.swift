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
            .onAppear {
                NSApp.setActivationPolicy(.regular)
            }
            .onDisappear {
                NSApp.setActivationPolicy(.accessory)
            }
            .task {
                guard await !settings.hasSeenFirstLaunchGuidance else { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
                showFirstLaunchGuidance = true
            }
            .sheet(isPresented: $showFirstLaunchGuidance) {
                FirstLaunchGuidanceView {
                    Task {
                        await settings.setHasSeenFirstLaunchGuidance(true)
                        await settings.setInitialSetupStepRawValue(0)
                        showFirstLaunchGuidance = false
                    }
                }
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 480, height: 400)
}
