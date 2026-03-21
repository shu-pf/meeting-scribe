#!/usr/bin/env bash
# MeetingScribe を署名・公証し、DMG を作成するスクリプト。
# 事前に Xcode で Release ビルドしておくこと。
#
# 必要な環境変数（リポジトリ直下の .env に書くか、事前に export）:
#   NOTARY_APPLE_ID    … Apple ID メール
#   NOTARY_TEAM_ID     … チーム ID（例: 3R3JQ22JJF）
#   NOTARY_PASSWORD    … アプリ用パスワード（https://appleid.apple.com で発行）
#   NOTARY_IDENTITY    … "Developer ID Application: Your Name (TEAM_ID)"
#
# セットアップ:
#   cp .env.example .env   # 編集して値を入れる
#
# 使用例:
#   ./scripts/notarize_and_dmg.sh
#
# または Release .app のパスを指定:
#   ./scripts/notarize_and_dmg.sh /path/to/MeetingScribe.app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${NOTARY_ENV_FILE:-$REPO_ROOT/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

APP_NAME="MeetingScribe"
WORK_DIR="/tmp"
STAGING_APP="$WORK_DIR/$APP_NAME.app"
DMG_PATH="$WORK_DIR/${APP_NAME}.dmg"

# notarytool は Rejected でも終了コード 0 になることがあるため、出力で Accepted を確認する。
submit_notary_and_require_accept() {
  local artifact="$1"
  local label="$2"
  local SUBMIT_OUTPUT
  SUBMIT_OUTPUT=$(xcrun notarytool submit "$artifact" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait 2>&1)
  echo "$SUBMIT_OUTPUT"

  if ! echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "Error: Notarization was not accepted (${label})."
    local SUB_ID
    SUB_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $NF}')
    if [[ -n "$SUB_ID" ]]; then
      xcrun notarytool log "$SUB_ID" \
        --apple-id "$NOTARY_APPLE_ID" \
        --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD"
    fi
    exit 1
  fi
}

# 必須の環境変数
for var in NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD NOTARY_IDENTITY; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set. Create $REPO_ROOT/.env from .env.example or export it."
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
echo "[1] Copying app to $WORK_DIR and clearing xattr..."
rm -rf "$STAGING_APP"
ditto --norsrc "$RELEASE_APP" "$STAGING_APP"
xattr -cr "$STAGING_APP"

# 2. すべての dylib と whisper、.app を hardened runtime で署名（.app への --deep は使わない）
echo "[2] Signing all dylibs, whisper, and app..."
for f in "$STAGING_APP/Contents/Resources/"*.dylib; do
  [[ -e "$f" ]] || continue
  codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$f"
done
codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$STAGING_APP/Contents/Resources/whisper"
codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$STAGING_APP"

echo "[3] Verifying code signature and Gatekeeper assessment..."
codesign --verify --verbose --strict "$STAGING_APP"
spctl --assess --type execute --verbose "$STAGING_APP"

# 4. 公証用 zip を提出
echo "[4] Submitting app to Apple for notarization..."
ZIP_PATH="$WORK_DIR/$APP_NAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$STAGING_APP" "$ZIP_PATH"
submit_notary_and_require_accept "$ZIP_PATH" "app (zip)"

# 5. スタンプ
echo "[5] Stapling notarization ticket to app..."
xcrun stapler staple "$STAGING_APP"
xcrun stapler validate "$STAGING_APP" || { echo "Staple validation failed."; exit 1; }

# 6. DMG 作成（create-dmg がインストールされている場合）
echo "[6] Creating DMG..."
if command -v create-dmg &>/dev/null; then
  rm -f "$DMG_PATH"
  create-dmg \
    --identity "$NOTARY_IDENTITY" \
    --overwrite \
    --no-version-in-filename \
    --dmg-title "$APP_NAME" \
    "$STAGING_APP" \
    "$WORK_DIR"
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: Expected DMG not found at $DMG_PATH (check create-dmg output)."
    exit 1
  fi

  echo "[7] Submitting DMG for notarization..."
  submit_notary_and_require_accept "$DMG_PATH" "DMG"

  echo "[8] Stapling DMG and moving to Desktop..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH" || { echo "DMG staple validation failed."; exit 1; }

  mv "$DMG_PATH" "$HOME/Desktop/"
  echo "Done. DMG saved to: $HOME/Desktop/$(basename "$DMG_PATH")"
else
  echo "create-dmg not found. Skipping DMG. Signed app is at: $STAGING_APP"
  echo "Install create-dmg (e.g. brew install create-dmg) and run create-dmg manually, or copy $STAGING_APP to Desktop."
fi
