// 「自動的にアップデートを確認」の値を Sparkle と画面の間で同期しても無限ループしないことを確認する。
// Sparkle は同じ値を書いても変更を通知するため、同期の書き方を誤るとスタックが溢れて落ちる。
// 実行（Debug ビルドの後、P は Build/Products/Debug）:
//   xcrun swiftc -parse-as-library -F "$P" -framework Sparkle -Xlinker -rpath -Xlinker "$P" \
//     scripts/check_update_settings_sync.swift MeetingScribe/Services/CheckForUpdatesViewModel.swift \
//     -o /tmp/check_update_settings_sync && /tmp/check_update_settings_sync "$P/MeetingScribe Dev.app"
// 自動確認の設定は渡したアプリの bundle ID の defaults に書かれる

import Foundation
import Sparkle

// 本物の SPUUpdater に CheckForUpdatesViewModel をつなぎ、
// Sparkle 側の書き込み（自動確認の許可への回答）と画面のトグル操作を再現する
@main
struct SparkleLoopCheck {
    @MainActor static func main() {
        let appPath = CommandLine.arguments[1]
        let bundle = Bundle(path: appPath)!
        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil),
            delegate: nil
        )
        let viewModel = CheckForUpdatesViewModel(updater: updater)

        // Sparkle が許可の回答を保存するときと同じ書き込み
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyChecksForUpdates = true
        guard viewModel.automaticallyChecksForUpdates == true else {
            print("NG: 画面の値が Sparkle に追従しない"); exit(1)
        }

        // 設定画面でトグルを切り替えたとき
        viewModel.automaticallyChecksForUpdates = false
        guard updater.automaticallyChecksForUpdates == false else {
            print("NG: トグルが Sparkle に反映されない"); exit(1)
        }
        viewModel.automaticallyChecksForUpdates = true
        guard updater.automaticallyChecksForUpdates == true else {
            print("NG: トグルが Sparkle に反映されない"); exit(1)
        }
        print("OK: 無限ループせず、双方向に同期する")
    }
}
