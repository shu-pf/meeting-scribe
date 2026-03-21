# MeetingScribe

Mac 用の会議メモアプリ。録画 → Whisper で文字起こし → ローカル LLM で要約。

## 開発

Xcode で `MeetingScribe` を開いてビルド。

## 配布

1. Xcode の General → Identity で **Version** を上げる（例: `1.0.0` → `1.1.0`）
2. `.env.example` を `.env` にコピーし、必要な値を入れる
3. `.env` の `DOWNLOAD_URL_PREFIX` をリリースバージョンに合わせて設定する
   ```
   DOWNLOAD_URL_PREFIX=https://github.com/shu-pf/meeting-scribe/releases/download/v1.1.0/
   ```
4. Xcode でリリース用にビルド
5. `./scripts/notarize_and_dmg.sh` を実行する
6. 署名・公証済みの `.app`、`.dmg`、`appcast.xml` が **`dist/`** に出力される
7. GitHub で同じバージョンタグ（例: `v1.1.0`）の Release を作成し、DMG をアップロード
8. `appcast.xml` を [meeting-scribe-lp](https://github.com/shu-pf/meeting-scribe-lp) リポジトリにコミット・プッシュ

### 自動アップデート（Sparkle）

アプリには [Sparkle](https://sparkle-project.org/) による自動アップデート機能が組み込まれている。

- **appcast.xml の配信先**: `https://shu-pf.github.io/meeting-scribe-lp/appcast.xml`
- **バイナリの配信先**: GitHub Releases（このリポジトリ）
- **EdDSA 署名鍵**: Keychain に保存済み（`generate_keys` で生成）。紛失時は鍵のローテーションが必要。
