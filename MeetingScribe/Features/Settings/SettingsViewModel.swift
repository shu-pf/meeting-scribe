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
    @Published var showWhisperModelDownloadSheet: Bool = false

    private let settings: SettingsServiceProtocol
    private let whisperModelStore: WhisperModelStoreProtocol
    private let summaryService: SummaryServiceProtocol

    init(
        settings: SettingsServiceProtocol? = nil,
        whisperModelStore: WhisperModelStoreProtocol,
        summaryService: SummaryServiceProtocol? = nil
    ) {
        self.settings = settings ?? SettingsService()
        self.whisperModelStore = whisperModelStore
        self.summaryService = summaryService ?? SummaryService()
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
        whisperModelIDs = await whisperModelStore.downloadedModelIDs()
        do {
            summaryModelIDs = try await summaryService.fetchAvailableModelIDs()
        } catch {
            summaryModelIDs = []
        }
    }

    /// 文字起こしモデルが未設定のときは true（初回ダイアログ表示用）
    func shouldShowWhisperModelDownloadSheet() async -> Bool {
        let selected = await settings.selectedWhisperModelID
        let downloaded = await whisperModelStore.downloadedModelIDs()
        return selected == nil && downloaded.isEmpty
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
