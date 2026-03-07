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

echo "Building whisper-cli (Release, arm64)..."
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build --config Release --target whisper-cli

if [[ ! -f build/bin/whisper-cli ]]; then
  echo "Build failed: build/bin/whisper-cli not found"
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_BINARY")"
mkdir -p "$OUTPUT_DIR"
cp -f build/bin/whisper-cli "$OUTPUT_BINARY"

# whisper-cli は libwhisper.1.dylib のみ参照するため、それだけコピーする
dylib="$(find build -maxdepth 4 -name 'libwhisper.1.dylib' 2>/dev/null | head -1)"
if [[ -n "$dylib" && -f "$dylib" ]]; then
  cp -f "$dylib" "$OUTPUT_DIR/"
  echo "Copied libwhisper.1.dylib to $OUTPUT_DIR"
fi
echo "Done: $OUTPUT_BINARY"
