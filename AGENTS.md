# MeetingScribe

Mac用ローカル会議議事録アプリ。メニューバー常駐、画面録画 → Whisper文字起こし → Ollama要約。全処理ローカル完結。

## エージェント設定方針

Claude Code・Codex 両対応。新コマンドの許可追加は `~/.claude/settings.json` と `~/.codex/rules/default.rules` の両方に追加すること。

## Build

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project MeetingScribe.xcodeproj -scheme "MeetingScribe - Debug"
```

スキームは `"MeetingScribe - Debug"` / `"MeetingScribe - Release"`(引用符必須)。変更後は必ずビルドを通すこと。

### Debug署名

- 実際に起動して動作確認するDebugアプリは、Team `3R3JQ22JJF` の `Apple Development` 証明書で署名する
- `CODE_SIGN_IDENTITY=-` によるアドホック署名は禁止。ビルドごとにDesignated Requirementが変わり、画面収録のTCC権限が失われる
- ビルド後は `scripts/verify_debug_signing.sh <MeetingScribe.appのパス>` を実行し、安定した開発署名であることを確認してから動作確認する
- コード署名証明書を利用できないCI等でコンパイルだけ確認する場合は `CODE_SIGNING_ALLOWED=NO` を使用できるが、その成果物を動作確認には使用しない

## 動作確認

- 機能変更後はビルド成功だけで完了とせず、Debugアプリを起動して変更した機能を実際に操作し、期待どおり動作することを確認する
- 変更箇所に応じて正常系に加えて主要な異常系・境界条件も確認する
- TCC権限、外部サービス、実機操作などに阻まれて変更フローを最後まで確認できない場合は、未確認部分と理由を明記し、ユーザーに必要な確認を依頼する。未確認のまま「動作確認済み」と報告しない
- 画面収録権限は `scripts/check_screen_capture_permission.swift` をDebugアプリと同じbundle ID・開発証明書で署名して確認する
- ウィンドウ閉鎖時のScreenCaptureKit終了通知を確認するときは、`scripts/check_window_close_signal.swift` をコンパイル・実行し、映像フレーム受信後の結果だけを有効とする
- 録画音声を変更したときは、マイクありの実録画にシステム音声とマイク音声の2トラックがあり両方に実データが入ること、マイクなしではシステム音声の1トラックだけになること、および各録画から文字起こし用WAVを正常に抽出・合成できることを確認する
- Whisperモデル導入フローを変更したときは、アプリからモデルを実際にダウンロードし、録画開始の有効化と文字起こし完了まで確認する
- 初回セットアップまたは要約モデル導入フローを変更したときは、Ollama未起動時に次へ進めないこと、古いOllamaでは日本語の更新手順を表示すること、アプリから推奨モデルを実際にダウンロードできること、完了後に選択状態となることを確認する
- 設定ウィンドウはシングルトンとし、「設定を開く」の連打やアプリ再起動で複数枚に増えないことを確認する
- 長文要約の分割・統合処理を変更したときは、`scripts/check_long_summary_input.swift` を `SummaryService.swift`・`DiagnosticLogger.swift` とともにコンパイル・実行し、モデルのコンテキスト長を超える合成文字起こしが入力エラーにならず日本語要約まで完了することを確認する。分割が2チャンク以上になる実際の長さの文字起こしでも、部分要約・最終要約が空にならず本文が出力されることを確認する（要約モデルが思考を生成する場合、思考が出力上限を使い切ると本文が空になる）
- 要約のやり直し経路を変更したときは、`scripts/check_resummarize.swift` を `RecordingPipeline.swift`・`PipelineJobStore.swift`・`SummaryService.swift`・`TranscriptionService.swift`・`WhisperModelStore.swift`・`AudioExtractor.swift`・`DiagnosticLogger.swift` とともにコンパイル・実行し、既存ファイル名の日時部分を保ったまま会議名が付け替わり、やり直し前のファイルが残らないことを確認する。やり直しの出力先は現在の保存先設定ではなく既存ファイルのある場所とする
- 録画後パイプラインの再開処理を変更したときは、文字起こし中と要約中のそれぞれでDebugアプリを終了・再起動し、永続キューとチェックポイントから二重実行せず完了することを確認する。文字起こし中の強制終了では、残留Whisperを実行パス照合後に停止してから1プロセスだけで再開することも確認する。蓋を閉じたスリープは処理継続を保証せず、スリープ前に再開待ちへ戻して復帰後に自動再開する
- 録画中に設定済みの保存先フォルダが削除されても、録画完了時に保存先を再作成して完成ファイルを保存できることを境界条件として確認する
- 録画の品質保証上限は5時間。長時間処理を変更したときは、5時間の音声入力に対して `scripts/check_long_audio_extraction.swift` を実行し、WAV抽出がメモリへ全量展開されないことを確認する
- 5時間到達時は録画ファイルを正常終了して後処理へ渡し、ユーザーへローカル通知する。この自動終了経路を変更した場合は、短い上限を注入して境界動作を確認する

## Architecture

```
App/              メニューバー常駐エントリポイント
Features/MenuBar/ メニューバーUI・録画ウィンドウ選択
Features/Settings/ 設定画面・初回必須セットアップ・モデルダウンロード
Services/         Recording / AudioExtractor / Transcription / Summary / Settings / WhisperModel
Domain/Pipeline/  録画停止後パイプライン(音声抽出→文字起こし→要約→保存)
Resources/        whisperバイナリ・dylib群(build_whisper.sh生成物、手で編集しない)
```

- 録画・停止・後処理・保存場所などのライフサイクルを変更した場合は、実装と `internal-docs/application-lifecycle.md` を照合し、同じ変更内で必ず更新する
- 特に停止経路（手動、ScreenCaptureKit通知、ウィンドウ存在確認、5時間上限）を追加・削除・変更した場合は、フロー図、シーケンス図、「録画停止の経路」を同期する

## 制約

- 議事録生成は**日本語**固定(プロンプト変更時は必ず維持。過去に英語生成バグあり)
- `Resources/` のバイナリは `scripts/build_whisper.sh` の生成物。手で編集しない
- マイク音声（自分の声）は「録画開始前に毎回確認」「常に含める」「常に含めない」の設定に従う。初期値は毎回確認。Teamsなど他アプリのミュート状態には連動しないことを確認画面で明示する
- マイクありではシステム音声とマイク音声を別トラックで保持し、文字起こし時に全音声トラックをモノラルへ合成する。マイクなしではマイク権限を要求せず、システム音声トラックだけを録音・文字起こしする
- 録画開始には、選択済みWhisperモデルの実ファイルと、選択済み要約モデルが必要。未設定時は録画を無効化して設定を案内し、存在しない `default` モデルへのフォールバックや要約のスキップを行わない
- 初回起動では、保存先、画面収録権限、推奨Whisperモデル、推奨要約モデルがすべて準備できるまでセットアップを完了させない。マイク権限は任意で、自分の声を含める録画の開始時にも要求できる
- 要約時はOllamaからモデル固有のコンテキスト長を取得し、長文を部分要約してから段階的に統合する。ユーザーに最大コンテキスト長を設定させず、入力長超過をユーザー向けエラーにしない
- 録画中のファイルは `~/Library/Application Support/MeetingScribe/InProgress/` に `.partial.mp4` として書き込み、正常終了後に設定済み保存先へ移動する。保存先が録画中に削除された場合は終了時に再作成する
- 録画後処理のジョブ状態と文字起こし・要約チェックポイントは `~/Library/Application Support/MeetingScribe/PipelineJobs/` に永続化する。スリープ、アプリ終了、クラッシュ後は未完了フェーズから自動再開し、完成後に本文を含むチェックポイントを削除する
- ScreenCaptureKit録画はTCC権限が必要でCIでは実行不可。録画以外の層をテスト対象とする
- Debugは製品名 `MeetingScribe Dev`・bundle ID `com.shu-pf.MeetingScribe.dev`、Releaseは製品名 `MeetingScribe`・bundle ID `com.shu-pf.MeetingScribe`（製品版およびTCC権限表示と区別するため分離）
- SwiftUI + Swift 6 strict concurrency、macOS 15.0以降
