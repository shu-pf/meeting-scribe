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
    var hasSeenFirstLaunchGuidance: Bool { get async }
    func setHasSeenFirstLaunchGuidance(_ value: Bool) async
    var summaryContextLength: Int { get async }
    func setSummaryContextLength(_ value: Int) async
}

final class SettingsService: SettingsServiceProtocol {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let outputDirectoryPath = "outputDirectoryPath"
        static let outputDirectoryBookmark = "outputDirectoryBookmark"
        static let selectedWhisperModelID = "selectedWhisperModelID"
        static let selectedSummaryModelID = "selectedSummaryModelID"
        static let launchAtLogin = "launchAtLogin"
        static let hasSeenFirstLaunchGuidance = "hasSeenFirstLaunchGuidance"
        static let summaryContextLength = "summaryContextLength"
    }

    private static let defaultSummaryContextLength = 131_072

    var outputDirectoryURL: URL? {
        get async {
            guard let bookmarkData = defaults.data(forKey: Keys.outputDirectoryBookmark) else {
                return defaults.string(forKey: Keys.outputDirectoryPath).map { URL(fileURLWithPath: $0) }
            }
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    try? persistOutputDirectoryBookmark(url: url)
                }
                return url
            } catch {
                return defaults.string(forKey: Keys.outputDirectoryPath).map { URL(fileURLWithPath: $0) }
            }
        }
    }

    func setOutputDirectory(_ url: URL?) async {
        guard let url = url else {
            defaults.removeObject(forKey: Keys.outputDirectoryPath)
            defaults.removeObject(forKey: Keys.outputDirectoryBookmark)
            return
        }
        defaults.set(url.path, forKey: Keys.outputDirectoryPath)
        try? persistOutputDirectoryBookmark(url: url)
    }

    private func persistOutputDirectoryBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: Keys.outputDirectoryBookmark)
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

    var hasSeenFirstLaunchGuidance: Bool {
        get async { defaults.bool(forKey: Keys.hasSeenFirstLaunchGuidance) }
    }

    func setHasSeenFirstLaunchGuidance(_ value: Bool) async {
        defaults.set(value, forKey: Keys.hasSeenFirstLaunchGuidance)
    }

    var summaryContextLength: Int {
        get async {
            let key = Keys.summaryContextLength
            guard defaults.object(forKey: key) != nil else {
                return Self.defaultSummaryContextLength
            }
            return defaults.integer(forKey: key)
        }
    }

    func setSummaryContextLength(_ value: Int) async {
        defaults.set(value, forKey: Keys.summaryContextLength)
    }
}
