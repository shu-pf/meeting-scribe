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
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "settings") {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 480, height: 400)
        .commandsRemoved()
    }
}
