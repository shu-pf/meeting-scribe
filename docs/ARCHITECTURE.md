# MeetingScribe アーキテクチャ

## 1. アプリの全体像

- **種類**: macOS メニューバー常駐アプリ（メインウィンドウは設定用、日常操作はステータスメニューから実行）
- **処理フロー**: 録画終了 → 自動で Whisper 文字起こし → 自動でローカル LLM 要約 → 指定フォルダへ出力

## 2. 技術選定

| 領域 | 選定 | 理由 |
|------|------|------|
| 画面・ウィンドウ録画 | ScreenCaptureKit (macOS 12.3+) | 公式API。ウィンドウ/ディスプレイ単位のキャプチャとアプリ音声・システムオーディオの取得が可能。 |
| 文字起こし | whisper.cpp をアプリに組み込み | 実行エンジンはアプリに同梱。初回/未設定時にモデル選択ダイアログで非同期ダウンロード。モデルは Application Support 配下。 |
| 要約（LLM） | Ollama を HTTP API で利用 | アプリにモデルを含めず、ユーザが Ollama でモデルを追加ダウンロード。 |
| 設定・永続化 | UserDefaults / AppStorage | モデル選択・出力フォルダ・起動時ログイン等。 |

## 3. レイヤー構成

- **Presentation**: SwiftUI の View と ViewModel。設定画面・ステータスメニュー（録画開始/停止・ウィンドウ選択）。
- **Domain**: 録画結果などのモデルと、録画 → 文字起こし → 要約のオーケストレーター（RecordingPipeline）。
- **Services**: I/O と外部プロセス/API。RecordingService、TranscriptionService、SummaryService、SettingsService。プロトコルで抽象化しテスト時にモック差し替え可能。

## 4. ディレクトリ構造

```
MeetingScribe/
├── App/
│   └── MeetingScribeApp.swift     # @main, MenuBarExtra + WindowGroup
├── Features/
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── SettingsViewModel.swift
│   └── MenuBar/
│       ├── MenuBarView.swift
│       ├── MenuBarViewModel.swift
│       └── WindowPickerView.swift
├── Domain/
│   ├── Models/
│   │   └── RecordingResult.swift
│   └── Pipeline/
│       └── RecordingPipeline.swift
├── Services/
│   ├── RecordingService.swift
│   ├── TranscriptionService.swift
│   ├── SummaryService.swift
│   └── SettingsService.swift
├── Assets.xcassets
└── ContentView.swift              # 設定ウィンドウのルート（SettingsView を表示）
```

## 5. データフロー（録画〜出力まで）

1. ユーザがステータスメニューでウィンドウ（または「全体」）を選び「録画開始」。
2. RecordingService が ScreenCaptureKit でキャプチャ開始し、指定パスに動画を書き出す。
3. ユーザが「録画終了」→ RecordingService が停止しファイルを確定。
4. RecordingPipeline が確定した動画を TranscriptionService に渡す。アプリ同梱の whisper で文字起こし。
5. 取得したテキストを SummaryService に渡し、Ollama API で要約を生成。
6. 録画ファイル・文字起こし・要約を出力フォルダに保存。

## 6. 次のステップ（開発手順 3〜5）

- **手順 3（画面録画）**: RecordingService と ScreenCaptureKit、MenuBar の録画 UI を実装。
- **手順 4（文字起こし）**: Whisper エンジンのアプリ同梱、モデル選択・非同期ダウンロード UI、TranscriptionService と同梱バイナリの連携。
- **手順 5（要約）**: SummaryService と Ollama、パイプラインの仕上げと出力フォルダへの保存。
