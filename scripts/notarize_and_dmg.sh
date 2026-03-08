#!/usr/bin/env bash
# MeetingScribe を署名・公証し、DMG を作成するスクリプト。
# 事前に Xcode で Release ビルドしておくこと。
#
# 必要な環境変数（実行前に export するか .env を source する）:
#   NOTARY_APPLE_ID    … Apple ID メール
#   NOTARY_TEAM_ID     … チーム ID（例: 3R3JQ22JJF）
#   NOTARY_PASSWORD    … アプリ用パスワード（https://appleid.apple.com で発行）
#   NOTARY_IDENTITY    … "Developer ID Application: Your Name (TEAM_ID)"
#
# 使用例:
#   export NOTARY_APPLE_ID="your@email.com"
#   export NOTARY_TEAM_ID="3R3JQ22JJF"
#   export NOTARY_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export NOTARY_IDENTITY="Developer ID Application: Shugo Furuse (3R3JQ22JJF)"
#   ./scripts/notarize_and_dmg.sh
#
# または Release .app のパスを指定:
#   ./scripts/notarize_and_dmg.sh /path/to/MeetingScribe.app

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MeetingScribe"
WORK_DIR="/tmp"
STAGING_APP="$WORK_DIR/$APP_NAME.app"

# 必須の環境変数
for var in NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD NOTARY_IDENTITY; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set. Export it before running this script."
    exit 1
  fi
done

# Release .app のパスを決定（引数 > 環境変数 > 自動検出）
if [[ -n "$1" && -d "$1" ]]; then
  RELEASE_APP="$1"
elif [[ -n "$RELEASE_APP_PATH" && -d "$RELEASE_APP_PATH" ]]; then
  RELEASE_APP="$RELEASE_APP_PATH"
else
  RELEASE_APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Release/$APP_NAME.app" -type d 2>/dev/null | head -1)"
  if [[ -z "$RELEASE_APP" || ! -d "$RELEASE_APP" ]]; then
    echo "Error: Release $APP_NAME.app not found."
    echo "Build in Xcode with Scheme set to Release, or pass the path: $0 /path/to/MeetingScribe.app"
    exit 1
  fi
fi

echo "Using app: $RELEASE_APP"
echo "Identity:  $NOTARY_IDENTITY"
echo "---"

# 1. /tmp にコピーして拡張属性を削除
echo "[1/6] Copying app to $WORK_DIR and clearing xattr..."
rm -rf "$STAGING_APP"
ditto --norsrc "$RELEASE_APP" "$STAGING_APP"
xattr -cr "$STAGING_APP"

# 2. すべての dylib と whisper、.app を hardened runtime で署名
echo "[2/6] Signing all dylibs, whisper, and app..."
for f in "$STAGING_APP/Contents/Resources/"*.dylib; do
  [[ -e "$f" ]] || continue
  codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$f"
done
codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$STAGING_APP/Contents/Resources/whisper"
codesign --force --deep --options runtime --sign "$NOTARY_IDENTITY" "$STAGING_APP"

# 3. 公証用 zip を提出
echo "[3/6] Submitting to Apple for notarization..."
ZIP_PATH="$WORK_DIR/$APP_NAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$STAGING_APP" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$NOTARY_APPLE_ID" \
  --team-id "$NOTARY_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

# 4. スタンプ
echo "[4/6] Stapling notarization ticket..."
xcrun stapler staple "$STAGING_APP"
xcrun stapler validate "$STAGING_APP" || { echo "Staple validation failed."; exit 1; }

# 5. DMG 作成（create-dmg がインストールされている場合）
echo "[5/6] Creating DMG..."
if command -v create-dmg &>/dev/null; then
  cd "$WORK_DIR"
  create-dmg --identity "$NOTARY_IDENTITY" "$STAGING_APP"
  DMG_NAME=""
  for d in "$APP_NAME"*.dmg; do
    [[ -f "$d" ]] && DMG_NAME="$d" && break
  done
  if [[ -n "$DMG_NAME" ]]; then
    echo "[6/6] Moving DMG to Desktop..."
    mv "$WORK_DIR/$DMG_NAME" "$HOME/Desktop/"
    echo "Done. DMG saved to: $HOME/Desktop/$DMG_NAME"
  else
    echo "DMG file not found in $WORK_DIR. Check create-dmg output."
  fi
else
  echo "create-dmg not found. Skipping DMG. Signed app is at: $STAGING_APP"
  echo "Install create-dmg (e.g. brew install create-dmg) and run create-dmg manually, or copy $STAGING_APP to Desktop."
fi
