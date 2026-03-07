//
//  SettingsService.swift
//  MeetingScribe
//

import Foundation

protocol SettingsServiceProtocol: Sendable {
    var outputDirectoryURL: URL? { get async }
    func setOutputDirectory(_ url: URL?) async
    var selectedWhisperModelID: String? { get async }
    func setSelectedWhisperModelID(_ id: String?) async
    var selectedSummaryModelID: String? { get async }
    func setSelectedSummaryModelID(_ id: String?) async
    var launchAtLogin: Bool { get async }
    func setLaunchAtLogin(_ enabled: Bool) async
}

final class SettingsService: SettingsServiceProtocol {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let outputDirectoryPath = "outputDirectoryPath"
        static let selectedWhisperModelID = "selectedWhisperModelID"
        static let selectedSummaryModelID = "selectedSummaryModelID"
        static let launchAtLogin = "launchAtLogin"
    }

    var outputDirectoryURL: URL? {
        get async {
            guard let path = defaults.string(forKey: Keys.outputDirectoryPath) else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    func setOutputDirectory(_ url: URL?) async {
        guard let url = url else {
            defaults.removeObject(forKey: Keys.outputDirectoryPath)
            return
        }
        defaults.set(url.path, forKey: Keys.outputDirectoryPath)
    }

    var selectedWhisperModelID: String? {
        get async { defaults.string(forKey: Keys.selectedWhisperModelID) }
    }

    func setSelectedWhisperModelID(_ id: String?) async {
        if let id = id { defaults.set(id, forKey: Keys.selectedWhisperModelID) }
        else { defaults.removeObject(forKey: Keys.selectedWhisperModelID) }
    }

    var selectedSummaryModelID: String? {
        get async { defaults.string(forKey: Keys.selectedSummaryModelID) }
    }

    func setSelectedSummaryModelID(_ id: String?) async {
        if let id = id { defaults.set(id, forKey: Keys.selectedSummaryModelID) }
        else { defaults.removeObject(forKey: Keys.selectedSummaryModelID) }
    }

    var launchAtLogin: Bool {
        get async { defaults.bool(forKey: Keys.launchAtLogin) }
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Keys.launchAtLogin)
    }
}
