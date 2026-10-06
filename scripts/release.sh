#!/usr/bin/env bash
# Release ビルドから GitHub Release・appcast の公開までを一括で行う。
# バージョンは project.pbxproj の MARKETING_VERSION を使う。リリースノートは引数のファイル。
#
# 前提:
#   - .env に NOTARY_KEYCHAIN_PROFILE と NOTARY_IDENTITY（notarize_and_dmg.sh を参照）
#   - `gh` でリポジトリへ push / release できること
#   - main がクリーンで、リリースする変更をコミット済みであること
#
# 使用例:
#   ./scripts/release.sh /path/to/release-notes.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NOTES_FILE="${1:?リリースノートのファイルを指定してください}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/MeetingScribe-release-dd}"

cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: 未コミットの変更があります。" >&2
  exit 1
fi

APP_VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' MeetingScribe.xcodeproj/project.pbxproj | sort -u)"
if [[ -z "$APP_VERSION" || "$APP_VERSION" == *$'\n'* ]]; then
  echo "Error: MARKETING_VERSION を1つに決められません: $APP_VERSION" >&2
  exit 1
fi
TAG="v$APP_VERSION"
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Error: $TAG はすでにリリース済みです。" >&2
  exit 1
fi
echo "Releasing $TAG"

echo "[release] Release ビルド"
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project MeetingScribe.xcodeproj \
  -scheme "MeetingScribe - Release" -configuration Release \
  -derivedDataPath "$DERIVED_DATA" -quiet

# notarize_and_dmg.sh は create-dmg/create-dmg（シェル版）の引数を使う。
# npm 版の create-dmg が PATH の先にあると失敗するため、Homebrew 版を優先する。
export PATH="/opt/homebrew/bin:$PATH"
export APP_VERSION
export SPARKLE_BIN_DIR="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"

echo "[release] 署名・公証・DMG・appcast"
"$SCRIPT_DIR/notarize_and_dmg.sh" \
  "$DERIVED_DATA/Build/Products/Release/MeetingScribe.app"

echo "[release] GitHub Release"
gh release create "$TAG" "$REPO_ROOT/dist/MeetingScribe.dmg" \
  --title "MeetingScribe $TAG" \
  --notes-file "$NOTES_FILE"

echo "[release] appcast を公開"
git add docs/appcast.xml
git commit -m "Release $TAG"
git push origin main

echo "Released $TAG"
