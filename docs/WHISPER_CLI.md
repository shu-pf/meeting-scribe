# 同梱 Whisper CLI 仕様

MeetingScribe は [whisper.cpp](https://github.com/ggerganov/whisper.cpp) の CLI をアプリに同梱し、録画後の音声を文字起こしするために使用します。

## 対応アーキテクチャ

- **Mac Silicon（arm64）のみ**。Intel Mac（x86_64）は対象外です。

## バンドル内の起動パス

- 実行ファイルはアプリバンドルの `Contents/Resources/whisper` に配置されます。
- 起動パス: `Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/whisper")`

## 引数仕様

whisper.cpp の CMake ビルドで生成される `whisper-cli` を、同梱時に `whisper` にリネームして配置しています。

| 引数 | 説明 |
|------|------|
| `-m <path>` | 使用する ggml モデルファイルのパス（Application Support 配下の .bin） |
| `-f <path>` | 入力音声ファイルのパス（WAV 推奨。MP4 の場合は事前に AVFoundation で音声抽出すること） |
| `-otxt` | テキストを標準出力に出力する |
| `-t N` | スレッド数（省略時はデフォルト） |
| `-l auto` | 言語（auto で自動検出） |

## テキストの取得方法

- `-otxt` を指定した場合、転写結果は **標準出力** に出力されます。
- Swift 側では `Process` で起動し、標準出力を読み取って文字列として取得します。

## ビルド方法

同梱用バイナリのビルド手順は `scripts/build_whisper.sh` を実行してください。arm64 向けに CMake でビルドし、`MeetingScribe/Resources/whisper` にコピーします。
