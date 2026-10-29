#!/usr/bin/env bash
# MeetingScribe をリリースする。
# Release ビルド → 署名・公証・DMG（notarize_and_dmg.sh）→ GitHub Release → appcast のコミット・push
# → Homebrew tap（shu-pf/homebrew-tap）の cask 更新、までを順に行う。
#
# 使用例:
#   ./scripts/release.sh 1.4.7 /path/to/release-notes.md
#
# 前提:
#   - main で、作業ツリーがきれいで、origin/main と一致している
#   - MARKETING_VERSION が引数の版と一致している（"Bump version to x.y.z" のコミット済み）
#   - .env に公証用の値がある（.env.example 参照）。APP_VERSION は引数で上書きする
#   - Sparkle の EdDSA 秘密鍵がログインキーチェーンにある
#   - gh が shu-pf/meeting-scribe と shu-pf/homebrew-tap に書き込める

set -euo pipefail

VERSION="${1:-}"
NOTES_FILE="${2:-}"
if [[ -z "$VERSION" || -z "$NOTES_FILE" ]]; then
  echo "Usage: $0 <version> <release-notes.md>"
  exit 1
fi
if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Error: release notes not found: $NOTES_FILE"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG="v$VERSION"
TAP_REPO="shu-pf/homebrew-tap"
CASK_PATH="Casks/meeting-scribe.rb"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
RELEASE_APP="$DERIVED_DATA/Build/Products/Release/MeetingScribe.app"
DMG_PATH="$REPO_ROOT/dist/MeetingScribe.dmg"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "[0] Checking repository state..."
if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
  echo "Error: release from main."
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean."
  exit 1
fi
git fetch origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Error: HEAD is not origin/main."
  exit 1
fi
MARKETING_VERSIONS="$(grep -E 'MARKETING_VERSION = ' MeetingScribe.xcodeproj/project.pbxproj | sed -E 's/.*= (.*);/\1/' | sort -u)"
if [[ "$MARKETING_VERSIONS" != "$VERSION" ]]; then
  echo "Error: MARKETING_VERSION is '$MARKETING_VERSIONS', expected '$VERSION'."
  exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Error: release $TAG already exists."
  exit 1
fi

echo "[1] Building Release..."
rm -rf "$DERIVED_DATA"
xcodebuild build \
  -project MeetingScribe.xcodeproj \
  -scheme "MeetingScribe - Release" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA"

echo "[2] Signing, notarizing and creating DMG..."
APP_VERSION="$VERSION" \
  SPARKLE_BIN_DIR="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin" \
  ./scripts/notarize_and_dmg.sh "$RELEASE_APP"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: DMG not found: $DMG_PATH"
  exit 1
fi
if ! grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" docs/appcast.xml; then
  echo "Error: docs/appcast.xml does not contain $VERSION."
  exit 1
fi
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

echo ""
echo "Ready to publish $TAG"
echo "  DMG:     $DMG_PATH ($DMG_SHA256)"
echo "  Notes:   $NOTES_FILE"
echo "  Appcast: docs/appcast.xml"
read -r -p "Publish the GitHub Release, push appcast, and update the Homebrew cask? [y/N] " answer
if [[ "$answer" != "y" ]]; then
  echo "Stopped before publishing. Built files are in dist/ and docs/appcast.xml."
  exit 1
fi

echo "[3] Creating GitHub Release $TAG..."
gh release create "$TAG" "$DMG_PATH" \
  --target main \
  --title "MeetingScribe $TAG" \
  --notes-file "$NOTES_FILE"

echo "[4] Committing and pushing appcast..."
git add docs/appcast.xml
git commit -m "Release $TAG"
git push origin main

echo "[5] Updating Homebrew cask..."
CASK_JSON="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH")"
CASK_SHA="$(jq -r .sha <<<"$CASK_JSON")"
NEW_CASK="$(jq -r .content <<<"$CASK_JSON" | base64 -d \
  | sed -E "s/^  version \".*\"/  version \"$VERSION\"/" \
  | sed -E "s/^  sha256 \".*\"/  sha256 \"$DMG_SHA256\"/")"
if ! grep -q "version \"$VERSION\"" <<<"$NEW_CASK" || ! grep -q "sha256 \"$DMG_SHA256\"" <<<"$NEW_CASK"; then
  echo "Error: failed to rewrite the cask."
  exit 1
fi
gh api --method PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
  -f message="Update MeetingScribe cask to $VERSION" \
  -f content="$(base64 <<<"$NEW_CASK")" \
  -f sha="$CASK_SHA" >/dev/null

echo ""
echo "Released $TAG"
echo "  https://github.com/shu-pf/meeting-scribe/releases/tag/$TAG"
echo "  https://github.com/$TAP_REPO/blob/main/$CASK_PATH"
