# MeetingScribe

Mac用ローカル会議議事録アプリ。メニューバー常駐、画面録画 → Whisper文字起こし → Ollama要約。全処理ローカル完結。

## エージェント設定方針

Claude Code・Codex 両対応。新コマンドの許可追加は `~/.claude/settings.json` と `~/.codex/rules/default.rules` の両方に追加すること。

## Build

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project MeetingScribe.xcodeproj -scheme "MeetingScribe - Debug" CODE_SIGN_IDENTITY=-
```

スキームは `"MeetingScribe - Debug"` / `"MeetingScribe - Release"`(引用符必須)。変更後は必ずビルドを通すこと。

## Architecture

```
App/              メニューバー常駐エントリポイント
Features/MenuBar/ メニューバーUI・録画ウィンドウ選択
Features/Settings/ 設定画面・Whisperモデルダウンロード
Services/         Recording / AudioExtractor / Transcription / Summary / Settings / WhisperModel
Domain/Pipeline/  録画停止後パイプライン(音声抽出→文字起こし→要約→保存)
Resources/        whisperバイナリ・dylib群(build_whisper.sh生成物、手で編集しない)
```

## 制約

- 議事録生成は**日本語**固定(プロンプト変更時は必ず維持。過去に英語生成バグあり)
- `Resources/` のバイナリは `scripts/build_whisper.sh` の生成物。手で編集しない
- ScreenCaptureKit録画はTCC権限が必要でCIでは実行不可。録画以外の層をテスト対象とする
- Debugのbundle ID: `com.shu-pf.MeetingScribe.dev`、Release: `com.shu-pf.MeetingScribe`(製品版と共存のため分離)
- SwiftUI + Swift 6 strict concurrency、macOS 15.0以降
