//
//  SettingsViewModel.swift
//  MeetingScribe
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var outputDirectoryPath: String = ""
    @Published var selectedWhisperModelID: String = ""
    @Published var selectedSummaryModelID: String = ""
    @Published var launchAtLogin: Bool = false
    @Published var whisperModelIDs: [String] = []
    @Published var summaryModelIDs: [String] = []

    private let settings: SettingsServiceProtocol

    init(settings: SettingsServiceProtocol = SettingsService()) {
        self.settings = settings
    }

    func load() async {
        if let url = await settings.outputDirectoryURL {
            outputDirectoryPath = url.path
        } else {
            outputDirectoryPath = ""
        }
        selectedWhisperModelID = await settings.selectedWhisperModelID ?? ""
        selectedSummaryModelID = await settings.selectedSummaryModelID ?? ""
        launchAtLogin = await settings.launchAtLogin
        whisperModelIDs = ["tiny", "base", "small", "medium"]
        summaryModelIDs = ["llama2", "mistral", "gemma"]
    }

    func setOutputDirectory(_ url: URL) async {
        await settings.setOutputDirectory(url)
        outputDirectoryPath = url.path
    }

    func clearOutputDirectory() async {
        await settings.setOutputDirectory(nil)
        outputDirectoryPath = ""
    }

    func setSelectedWhisperModelID(_ id: String) async {
        await settings.setSelectedWhisperModelID(id.isEmpty ? nil : id)
        selectedWhisperModelID = id
    }

    func setSelectedSummaryModelID(_ id: String) async {
        await settings.setSelectedSummaryModelID(id.isEmpty ? nil : id)
        selectedSummaryModelID = id
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        await settings.setLaunchAtLogin(enabled)
        launchAtLogin = enabled
    }
}
