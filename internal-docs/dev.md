# 開発者向けドキュメント

## 設計資料

- [アプリケーションライフサイクル](./application-lifecycle.md)

## 開発

Xcode で `MeetingScribe` を開いてビルド。

## 配布

通常は `./scripts/release.sh <リリースノート.md>` で、下の 2〜5 をまとめて実行する（バージョンは `MARKETING_VERSION` を先に上げてコミットしておく）。

1. `.env.example` を `.env` にコピーし、公証用の値と **`APP_VERSION`**（例: `1.2.0`）を書く。公証の認証情報は `xcrun notarytool store-credentials meeting-scribe` でキーチェーンに保存し、`.env` には `NOTARY_KEYCHAIN_PROFILE=meeting-scribe` だけを書く
2. Xcode で Release ビルド → `./scripts/notarize_and_dmg.sh`
3. **`dist/`** に `.app` / `.dmg`、**`docs/appcast.xml`** が更新される
4. GitHub で `v${APP_VERSION}` の Release を作り DMG を載せる
5. **`docs/appcast.xml`** を含めてコミット・プッシュ

### Sparkle

- **appcast**: `https://shu-pf.github.io/meeting-scribe/appcast.xml`（`docs/appcast.xml`）
- **DMG**: GitHub Releases（タグは `v${APP_VERSION}` と一致させる）
- EdDSA 鍵は Keychain に保存（紛失時は鍵の再生成が必要）
