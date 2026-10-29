#!/usr/bin/env bash
# Build whisper.cpp for macOS arm64 and copy the binary to MeetingScribe/Resources/whisper.
# Also downloads the Silero VAD model to MeetingScribe/Resources/.
# Run from the repository root: ./scripts/build_whisper.sh

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WHISPER_CPP_VERSION="v1.9.5"
WHISPER_DIR="${WHISPER_CPP_DIR:-$REPO_ROOT/whisper.cpp}"
OUTPUT_BINARY="$REPO_ROOT/MeetingScribe/Resources/whisper"
VAD_MODEL_NAME="ggml-silero-v6.2.0.bin"
VAD_MODEL_URL="https://huggingface.co/ggml-org/whisper-vad/resolve/main/$VAD_MODEL_NAME"
VAD_MODEL_SHA256="2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"

if [[ $(uname -m) != "arm64" ]]; then
  echo "This script is intended for Mac Silicon (arm64). Current arch: $(uname -m)"
  exit 1
fi

if [[ ! -d "$WHISPER_DIR" ]]; then
  echo "Cloning whisper.cpp $WHISPER_CPP_VERSION..."
  git clone --depth 1 --branch "$WHISPER_CPP_VERSION" https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi
cd "$WHISPER_DIR"

CURRENT_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
if [[ "$CURRENT_TAG" != "$WHISPER_CPP_VERSION" ]]; then
  echo "whisper.cpp at $WHISPER_DIR is not $WHISPER_CPP_VERSION (found: ${CURRENT_TAG:-untagged})."
  echo "Remove the directory and re-run, or check out $WHISPER_CPP_VERSION."
  exit 1
fi
rm -rf build

echo "Building whisper-cli (Release, arm64, macOS 15.0+)..."
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
cmake --build build --config Release --target whisper-cli

if [[ ! -f build/bin/whisper-cli ]]; then
  echo "Build failed: build/bin/whisper-cli not found"
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_BINARY")"
mkdir -p "$OUTPUT_DIR"
cp -f build/bin/whisper-cli "$OUTPUT_BINARY"

# libwhisper.1.dylib と、その依存である libggml 系 dylib をすべてコピー
# 注: build 内の *.0.dylib はシンボリックリンクなので -type f にしない。cp -fL で実体をコピーする。
for name in libwhisper.1.dylib libggml.0.dylib libggml-base.0.dylib libggml-cpu.0.dylib libggml-blas.0.dylib libggml-metal.0.dylib; do
  f="$(find build -name "$name" 2>/dev/null | head -1)"
  if [[ -n "$f" && -e "$f" ]]; then
    cp -fL "$f" "$OUTPUT_DIR/"
    echo "Copied $name to $OUTPUT_DIR"
  fi
done

# .app 内の Contents/Resources で実行されても dylib を読めるよう、@executable_path を rpath に追加
# （ビルド時の絶対パス rpath は別マシンやクリーン後に無効になるため）
install_name_tool -add_rpath "@executable_path" "$OUTPUT_BINARY"
echo "Added @executable_path rpath to whisper binary"

VAD_MODEL_PATH="$OUTPUT_DIR/$VAD_MODEL_NAME"
echo "Downloading $VAD_MODEL_NAME..."
curl -fL --retry 3 -o "$VAD_MODEL_PATH" "$VAD_MODEL_URL"
echo "$VAD_MODEL_SHA256  $VAD_MODEL_PATH" | shasum -a 256 -c -

echo "Done: $OUTPUT_BINARY ($WHISPER_CPP_VERSION), $VAD_MODEL_PATH"
