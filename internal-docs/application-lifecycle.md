# アプリケーションライフサイクル

MeetingScribe の起動から録画、文字起こし、要約、ファイル保存までの流れを、実装に基づいてまとめます。

## 全体フロー

```mermaid
flowchart TD
    Launch["アプリ起動<br/>MeetingScribeApp"] --> AppLog["起動情報を診断ログへ記録"]
    AppLog --> MenuBar["MenuBarExtra を表示"]
    AppLog --> Sparkle["Sparkle Updater を開始"]
    MenuBar --> FirstLaunch{"初回起動か"}
    FirstLaunch -- Yes --> Settings["設定ウィンドウと初回ガイダンスを表示"]
    FirstLaunch -- No --> Idle["メニューバーで待機"]
    Settings --> Idle

    Idle --> OpenMenu["ユーザーがメニューを開く"]
    OpenMenu --> LoadContent["ScreenCaptureKit から<br/>ディスプレイ・ウィンドウ一覧を取得"]
    LoadContent --> SelectTarget["録画対象を選択"]
    LoadContent -. 取得失敗 .-> UIError["エラー表示と診断ログ記録"]

    SelectTarget --> Start["録画開始"]
    Start --> OutputCheck{"出力フォルダ設定済みか"}
    OutputCheck -- No --> UIError
    OutputCheck -- Yes --> SecurityScope["出力フォルダの<br/>Security-Scoped Access を開始"]
    SecurityScope --> CaptureSetup["SCContentFilter / SCStreamConfiguration<br/>AVAssetWriter を構築"]
    CaptureSetup --> Capture["SCStream.startCapture"]
    Capture -. 開始失敗 .-> UIError

    Capture --> Recording["録画中<br/>映像 H.264 / 音声 AAC"]
    Recording --> WindowPoll["ウィンドウ録画時は<br/>2秒ごとに存在確認"]
    WindowPoll --> Recording

    Recording --> ManualStop["ユーザーが録画停止"]
    Recording --> StreamStop["SCStream が予期せず停止"]
    Recording --> WindowGone["対象ウィンドウの閉鎖を検知"]

    ManualStop --> StopCapture["SCStream.stopCapture"]
    StopCapture --> Drain["映像処理キューをドレイン"]
    StreamStop --> UnexpectedFinalize["予期しない停止としてWriterを確定"]
    WindowGone --> UnexpectedFinalize
    Drain --> Finalize["AVAssetWriterを確定"]
    UnexpectedFinalize --> Finalize
    Finalize -. 確定失敗 .-> UIError

    Finalize --> Pipeline["録画後パイプラインをバックグラウンド開始"]
    Pipeline --> Transcribe["音声抽出<br/>Whisperで日本語文字起こし"]
    Transcribe --> Transcript["文字起こしMarkdownを保存"]
    Transcript --> SummaryCheck{"要約モデル設定済みか"}
    SummaryCheck -- Yes --> Summarize["Ollamaで日本語要約"]
    SummaryCheck -- No --> NoSummary["会議名を「無題」にする"]
    Summarize --> Save["録画・文字起こし・要約を<br/>日時＋会議名で保存"]
    NoSummary --> Save
    Save --> Notify["完了状態を表示してローカル通知"]
    Transcribe -. 失敗 .-> PipelineError["パイプライン失敗を表示・記録"]
    Summarize -. 失敗 .-> PipelineError
```

## コンポーネント間のシーケンス

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant UI as MenuBarView
    participant VM as MenuBarViewModel
    participant RS as RecordingService
    participant SC as ScreenCaptureKit
    participant AW as AVAssetWriter
    participant PL as RecordingPipeline
    participant WH as Whisper
    participant OL as Ollama
    participant FS as ローカルファイル
    participant LOG as DiagnosticLogger

    User->>UI: 録画対象を選択して開始
    UI->>VM: startRecording()
    VM->>LOG: 録画開始操作
    VM->>RS: startRecording(...)
    RS->>SC: 共有可能コンテンツ取得・ストリーム開始
    RS->>AW: Writerと映像入力を作成
    SC-->>RS: 映像・音声サンプル
    RS->>AW: H.264映像 / AAC音声を追加
    RS-->>VM: 録画開始成功

    alt ユーザーが停止
        User->>UI: 録画を終了
        UI->>VM: stopRecording()
        VM->>RS: stopRecording()
        RS->>SC: stopCapture()
    else ストリーム停止または対象ウィンドウ閉鎖
        SC-->>RS: didStopWithError
        RS-->>VM: onStreamStoppedUnexpectedly
        VM->>LOG: 予期しない停止
    end

    RS->>AW: endSession / markAsFinished / finishWriting
    AW-->>VM: 録画ファイルURL
    VM->>PL: processRecording(fileURL)
    PL->>WH: 日本語文字起こし
    WH-->>PL: 文字起こし本文
    PL->>FS: 文字起こしMarkdownを保存

    opt 要約モデル設定済み
        PL->>OL: 日本語要約を要求
        OL-->>PL: 会議タイトル・要約本文
        PL->>FS: 要約Markdownを保存
    end

    PL->>FS: 録画ファイル名を確定
    PL-->>VM: PipelineResult
    VM->>LOG: パイプライン完了
    VM-->>User: 完了表示・ローカル通知
```

## 各フェーズの責務

| フェーズ | 主な実装 | 責務 |
|---|---|---|
| 起動 | `MeetingScribeApp`、`FirstLaunchTriggerView` | メニューバー常駐、Sparkle開始、初回設定画面、通知権限要求 |
| 対象選択 | `MenuBarViewModel.loadShareableContent()` | 画面・ウィンドウ一覧の取得とUI用モデルへの変換 |
| 録画開始 | `RecordingService.startRecording()` | キャプチャフィルタ、解像度、SCStream、AVAssetWriterの構築 |
| 録画中 | `RecordingStreamOutput` | 映像と音声のタイムスタンプ補正、H.264/AAC書き込み |
| ウィンドウ監視 | `RecordingService.pollWindowExistence()` | 2秒間隔で対象ウィンドウの存在を確認。別Spaceのウィンドウも存在対象に含める |
| 録画停止 | `RecordingService.stopRecording()` | キャプチャ停止、キューのドレイン、Writerの正常終了 |
| 予期しない停止 | `RecordingStreamDelegate`、`handleStreamStoppedUnexpectedly()` | システム側停止やウィンドウ閉鎖時にも録画ファイルを可能な限り確定 |
| 後処理 | `RecordingPipeline.processRecording()` | Whisper文字起こし、Ollama要約、録画・Markdown保存 |
| UI状態と通知 | `MenuBarViewModel` | 録画・パイプライン状態、エラー表示、完了通知 |
| 診断 | `DiagnosticLogger`、`DiagnosticLogStore` | OSLogとローカルファイルへ処理状態・エラーを記録 |

## 録画停止の経路

録画終了には3つの経路があります。

1. ユーザーによる手動停止
   - `SCStream.stopCapture()` を呼び、映像処理キューをドレインしてからWriterを確定します。
2. ScreenCaptureKitによる予期しない停止
   - `SCStreamDelegate.stream(_:didStopWithError:)` からWriter確定処理へ進みます。
3. 録画対象ウィンドウの閉鎖
   - 2秒間隔の存在確認でウィンドウIDが見つからない場合、予期しない停止と同じ処理へ進みます。

ウィンドウ存在確認は `onScreenWindowsOnly: false` を使用します。対象が別のSpaceに移動して画面上に見えていないだけの場合は、閉鎖として扱いません。

## 録画後パイプライン

録画ファイルが確定すると、UI上の新しい録画操作を妨げない独立した `Task` で後処理を開始します。

1. 出力フォルダへのSecurity-Scoped Accessを取得
2. 録画からWAVを抽出
3. Whisper CLIを `-l ja` で実行し、日本語で文字起こし
4. 文字起こしMarkdownを先に保存
5. 要約モデルが設定されていれば、Ollamaへ日本語固定プロンプトで要約を要求
6. 日時と会議タイトルからファイル名を生成
7. 録画、文字起こし、要約を出力フォルダへ保存
8. 完了状態をUIへ反映し、ローカル通知を送信

録画停止ごとに `PipelineJob` を追加し、文字起こし・要約・保存・完了・失敗の状態をメニューバーへ表示します。複数の録画後処理は独立したタスクとして並行実行され、実行中の全項目と直近5件の完了・失敗結果を確認できます。加えて、出力フォルダを走査して完成済み録画の日時・会議名・文字起こし/要約の有無を履歴表示し、項目からFinderで録画ファイルを開けます。失敗時は対象ジョブへエラーメッセージを表示し、診断ログへエラーのdomain、code、descriptionを残します。

## 診断ログ

診断ログは次の場所に保存されます。

```text
~/Library/Application Support/MeetingScribe/Logs/<bundle-id>.log
```

- Release: `com.shu-pf.MeetingScribe.log`
- Debug: `com.shu-pf.MeetingScribe.dev.log`
- 1ファイル最大5MB
- 3世代のバックアップを保持
- DEBUGレベルは性能への影響を避けるためOSLogのみに出力
- INFO、WARN、ERRORをローカルファイルへ永続保存
- 会議の文字起こし本文や要約本文は記録しない

設定画面の「診断ログ」からログファイルを直接開くか、Finderで表示できます。

## 調査時に確認するログ

録画が突然終了した場合は、該当時刻付近を次の順で確認します。

1. `[MenuBar] 録画開始操作`
2. `[Recording] 録画開始要求`
3. `[Recording] 録画開始成功`
4. `[Recording] ストリームが停止しました` または `録画元ウィンドウが存在しない`
5. `[Recording] handleStreamStoppedUnexpectedly`
6. `[MenuBar] 録画ストリームが予期せず停止`
7. `[Pipeline]` または `[MenuBar] 録画後パイプライン`

エラー行には可能な範囲でNSErrorのdomain、code、descriptionを含めます。
