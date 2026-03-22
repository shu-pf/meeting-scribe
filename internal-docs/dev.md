# 開発者向けドキュメント

## 開発

Xcode で `MeetingScribe` を開いてビルド。

## 配布

1. `.env.example` を `.env` にコピーし、公証用の値と **`APP_VERSION`**（例: `1.2.0`）を書く
2. Xcode で Release ビルド → `./scripts/notarize_and_dmg.sh`
3. **`dist/`** に `.app` / `.dmg`、**`docs/appcast.xml`** が更新される
4. GitHub で `v${APP_VERSION}` の Release を作り DMG を載せる
5. **`docs/appcast.xml`** を含めてコミット・プッシュ

### Sparkle

- **appcast**: `https://shu-pf.github.io/meeting-scribe/appcast.xml`（`docs/appcast.xml`）
- **DMG**: GitHub Releases（タグは `v${APP_VERSION}` と一致させる）
- EdDSA 鍵は Keychain に保存（紛失時は鍵の再生成が必要）
