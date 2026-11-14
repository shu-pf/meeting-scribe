//
//  CheckForUpdatesViewModel.swift
//  MeetingScribe
//

import SwiftUI
import Combine
import Sparkle

/// Sparkle の SPUUpdater を SwiftUI から利用するための ViewModel。
/// `canCheckForUpdates` を公開し、ボタンの有効/無効を制御する。
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false

    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)

        // ユーザーがトグルを変更したときに updater に反映する。
        // Sparkle は同じ値を書いても変更を通知するので、同じ値なら書かない。
        // 書くと通知 → この値 → 書き込みが無限に続き、スタックが溢れて落ちる
        $automaticallyChecksForUpdates
            .dropFirst() // 初期値を無視
            .sink { [weak updater] newValue in
                guard let updater, updater.automaticallyChecksForUpdates != newValue else { return }
                updater.automaticallyChecksForUpdates = newValue
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
