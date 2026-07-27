//
//  SettingsService.swift
//  MeetingScribe
//

import Foundation

enum MicrophoneRecordingPreference: String, CaseIterable, Identifiable, Sendable {
    case askEveryTime
    case alwaysInclude
    case neverInclude

    var id: Self { self }

    var title: String {
        switch self {
        case .askEveryTime:
            "録画開始前に毎回確認"
        case .alwaysInclude:
            "常に自分の声を含める"
        case .neverInclude:
            "常に自分の声を含めない"
        }
    }

    var explanation: String {
        switch self {
        case .askEveryTime:
            "録画を開始するたびに、マイク音声を含めるか確認します。"
        case .alwaysInclude:
            "Teamsなどのミュート状態に関係なく、Macのマイク音声を録音します。"
        case .neverInclude:
            "システム音声だけを録音し、Macのマイクは使用しません。"
        }
    }
}

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
    var initialSetupStepRawValue: Int { get async }
    func setInitialSetupStepRawValue(_ value: Int) async
    var microphoneRecordingPreference: MicrophoneRecordingPreference { get async }
    func setMicrophoneRecordingPreference(
        _ preference: MicrophoneRecordingPreference
    ) async
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
        static let initialSetupStepRawValue = "initialSetupStepRawValue"
        static let microphoneRecordingPreference = "microphoneRecordingPreference"
    }

    var outputDirectoryURL: URL? {
        get async {
            if let bookmarkData = defaults.data(forKey: Keys.outputDirectoryBookmark) {
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
            if let path = defaults.string(forKey: Keys.outputDirectoryPath) {
                return URL(fileURLWithPath: path)
            }
            return nil
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

    var initialSetupStepRawValue: Int {
        get async { defaults.integer(forKey: Keys.initialSetupStepRawValue) }
    }

    func setInitialSetupStepRawValue(_ value: Int) async {
        defaults.set(value, forKey: Keys.initialSetupStepRawValue)
    }

    var microphoneRecordingPreference: MicrophoneRecordingPreference {
        get async {
            guard let rawValue = defaults.string(
                forKey: Keys.microphoneRecordingPreference
            ) else {
                return .askEveryTime
            }
            return MicrophoneRecordingPreference(rawValue: rawValue)
                ?? .askEveryTime
        }
    }

    func setMicrophoneRecordingPreference(
        _ preference: MicrophoneRecordingPreference
    ) async {
        defaults.set(
            preference.rawValue,
            forKey: Keys.microphoneRecordingPreference
        )
    }
}
