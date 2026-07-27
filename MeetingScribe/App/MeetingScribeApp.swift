//
//  MeetingScribeApp.swift
//  MeetingScribe
//
//  Created by Furuse Shugo on 2026/03/07.
//

import AppKit
import Sparkle
import SwiftUI

@main
struct MeetingScribeApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @StateObject private var menuBarViewModel = MenuBarViewModel()

    init() {
        let appLog = DiagnosticLogger(category: "App")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        appLog.info(
            "アプリ起動 version=\(version) build=\(build) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
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
                    menuBarViewModel.restorePipelineJobsIfNeeded()
                }
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(
                        for: NSWorkspace.willSleepNotification
                    )
                ) { _ in
                    menuBarViewModel.pausePipelineJobsForSystemSleep()
                }
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(
                        for: NSWorkspace.didWakeNotification
                    )
                ) { _ in
                    menuBarViewModel.resumePipelineJobsAfterSystemWake()
                }
        }
        .menuBarExtraStyle(.window)

        Window("MeetingScribe 設定", id: "settings") {
            ContentView()
                .environmentObject(checkForUpdatesViewModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 480, height: 540)
        .commandsRemoved()
    }
}
