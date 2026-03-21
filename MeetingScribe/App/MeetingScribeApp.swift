//
//  MeetingScribeApp.swift
//  MeetingScribe
//
//  Created by Furuse Shugo on 2026/03/07.
//

import SwiftUI

@main
struct MeetingScribeApp: App {
    @StateObject private var menuBarViewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: menuBarViewModel)
        } label: {
            Image(systemName: "menubar.dock.rectangle")
                .background(FirstLaunchTriggerView())
                .onAppear {
                    NSApp.setActivationPolicy(.accessory)
                    menuBarViewModel.requestNotificationPermission()
                }
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "settings", for: String.self) { _ in
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 480, height: 540)
        .commandsRemoved()
    }
}
