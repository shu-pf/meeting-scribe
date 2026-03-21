# MeetingScribe

Mac 用の会議メモアプリ。録画 → Whisper で文字起こし → ローカル LLM で要約。

## 開発

Xcode で `MeetingScribe` を開いてビルド。

## 配布

1. リリース用に Xcode でビルド
2. `.env.example` を `.env` にコピーし、Apple 公証用の値を入れる。
3. `./scripts/notarize_and_dmg.sh` を実行する。

署名・公証済みの `.app` と `.dmg`（`create-dmg` がある場合）は **`dist/`** に出力される。別の場所にしたい場合は環境変数 `DIST_DIR` を設定する。
