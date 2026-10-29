# 開発者向けドキュメント

## 設計資料

- [アプリケーションライフサイクル](./application-lifecycle.md)

## 開発

Xcode で `MeetingScribe` を開いてビルド。

## 配布

1. `.env.example` を `.env` にコピーし、公証用の値を書く。公証の認証情報は `xcrun notarytool store-credentials meeting-scribe` でキーチェーンに保存し、`.env` には `NOTARY_KEYCHAIN_PROFILE=meeting-scribe` だけを書く
2. main で `MARKETING_VERSION` を上げてコミット・push する（`Bump version to x.y.z`）
3. リリースノートを Markdown で書き、`./scripts/release.sh <version> <リリースノート.md>` を実行する
   - Release ビルド → 署名・公証・DMG（`scripts/notarize_and_dmg.sh`）→ GitHub Release `v<version>` → `docs/appcast.xml` のコミット・push（`Release v<version>`）→ Homebrew tap の cask 更新

### Sparkle

- **appcast**: `https://shu-pf.github.io/meeting-scribe/appcast.xml`（`docs/appcast.xml`）
- **DMG**: GitHub Releases（タグは `v${APP_VERSION}` と一致させる）
- EdDSA 鍵は Keychain に保存（紛失時は鍵の再生成が必要）
