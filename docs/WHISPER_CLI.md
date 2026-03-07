# 同梱 Whisper CLI 仕様

MeetingScribe は [whisper.cpp](https://github.com/ggerganov/whisper.cpp) の CLI をアプリに同梱し、録画後の音声を文字起こしするために使用します。

## 対応アーキテクチャ

- **Mac Silicon（arm64）のみ**。Intel Mac（x86_64）は対象外です。

## バンドル内の起動パス

- 実行ファイルはアプリバンドルの `Contents/Resources/whisper` に配置されます。
- `whisper-cli` は `libwhisper.1.dylib` に動的リンクしているため、同じ `Contents/Resources/` に dylib も必要です。起動時に `DYLD_LIBRARY_PATH` を Resources に設定して読み込みます。

## 引数仕様

whisper.cpp の CMake ビルドで生成される `whisper-cli` を、同梱時に `whisper` にリネームして配置しています。

| 引数 | 説明 |
|------|------|
| `-m <path>` | 使用する ggml モデルファイルのパス（Application Support 配下の .bin） |
| `-f <path>` | 入力音声ファイルのパス（WAV 推奨。MP4 の場合は事前に AVFoundation で音声抽出すること） |
| `-otxt` | テキストを標準出力に出力する |
| `-t N` | スレッド数（省略時はデフォルト） |
| `-l ja` | 言語（本アプリでは日本語固定） |

## テキストの取得方法

- `-otxt` を指定した場合、転写結果は **標準出力** に出力されます。
- Swift 側では `Process` で起動し、標準出力を読み取って文字列として取得します。

## ビルド方法

同梱用バイナリのビルド手順は `scripts/build_whisper.sh` を実行してください。arm64 向けに CMake でビルドし、`MeetingScribe/Resources/` に以下をコピーします。

- `whisper`（whisper-cli のリネーム）
- `libwhisper.1.dylib`（および libwhisper.*.dylib）— 上記実行ファイルが依存する共有ライブラリ

## トラブルシューティング・ログの確認

文字起こしで「音声ファイルが存在しません」や「input file not found」が出る場合、原因切り分けのためログを確認してください。

### ログの見方

1. **Xcode から実行している場合**  
   デバッグコンソール（Run 時のコンソール）に `Transcription` カテゴリのログが出ます。

2. **アプリを直接起動している場合**  
   - ターミナルで `log stream --predicate 'subsystem == "com.sh... (Bundle ID)"' --level debug` を実行してからアプリを起動する。  
   - または **Console.app** を開き、左でアプリ名を選択して「Transcription」でフィルタする。

### ログで確認すること

- **NSTemporaryDirectory / cachesDir**  
  パスに `Containers` が含まれる → サンドボックス有効で動作している（Xcode の Run は署名によりサンドボックスが有効になることがある）。
- **WAV 作業ディレクトリ**  
  `tmp` と `caches` のどちらが選ばれたか。`tmp` が選ばれていればコンテナ外の可能性が高い。
- **WAV 作成後 fileExists**  
  `true` なのに後で「音声ファイルが存在しません」になる → アプリ側のチェックは通っているが、子プロセス（whisper）が別の環境でそのパスを読めていない。
- **Process 終了 stderr**  
  whisper が標準エラーに出力したメッセージ（例: `error: input file not found`）がそのまま出ます。

### サンドボックスを無効にしている場合

entitlements で `com.apple.security.app-sandbox` を `false` にしていても、**Xcode の Run ではサンドボックスが有効になることがあります**。  
実際の挙動を試すには **Product → Archive** でビルドし、Organizer から「Show in Finder」で出した .app をダブルクリックして起動してください。
