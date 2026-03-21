//
//  MeetingScribeApp.swift
//  MeetingScribe
//
//  Created by Furuse Shugo on 2026/03/07.
//

import SwiftUI
import Sparkle

@main
struct MeetingScribeApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @StateObject private var menuBarViewModel = MenuBarViewModel()

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self._checkForUpdatesViewModel = StateObject(
            wrappedValue: CheckForUpdatesViewModel(updater: controller.updater)
        )
    }

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
                .environmentObject(checkForUpdatesViewModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 480, height: 540)
        .commandsRemoved()
    }
}
