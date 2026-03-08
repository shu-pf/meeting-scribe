#!/usr/bin/env bash
# Build whisper.cpp for macOS arm64 and copy the binary to MeetingScribe/Resources/whisper.
# Run from the repository root: ./scripts/build_whisper.sh

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WHISPER_DIR="${WHISPER_CPP_DIR:-$REPO_ROOT/whisper.cpp}"
OUTPUT_BINARY="$REPO_ROOT/MeetingScribe/Resources/whisper"

if [[ $(uname -m) != "arm64" ]]; then
  echo "This script is intended for Mac Silicon (arm64). Current arch: $(uname -m)"
  exit 1
fi

if [[ ! -d "$WHISPER_DIR" ]]; then
  echo "Cloning whisper.cpp..."
  git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi
cd "$WHISPER_DIR"

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

echo "Done: $OUTPUT_BINARY"
