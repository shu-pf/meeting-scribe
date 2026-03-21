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
# 任意:
#   DIST_DIR, SPARKLE_BIN_DIR
#   APP_VERSION … 例 1.2.0。指定時、dist の .app の版情報を署名前に上書きし、
#                 appcast 用 URL は GitHub Releases（shu-pf/meeting-scribe）向けに自動設定する
#   DOWNLOAD_URL_PREFIX … appcast 用 URL を手で上書きしたいときのみ
#   appcast の出力先は docs/appcast.xml のみ（dist には残さない）
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

# APP_VERSION があるとき、appcast 用（DOWNLOAD_URL_PREFIX 未指定なら GitHub Releases を仮定）
if [[ -z "${DOWNLOAD_URL_PREFIX:-}" && -n "${APP_VERSION:-}" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/shu-pf/meeting-scribe/releases/download/v${APP_VERSION}/"
fi

APP_NAME="MeetingScribe"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
STAGING_APP="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
DOCS_APPCAST="$REPO_ROOT/docs/appcast.xml"

# Sparkle ツールのディレクトリ（自動検出 or 環境変数）
if [[ -z "$SPARKLE_BIN_DIR" ]]; then
  SPARKLE_BIN_DIR="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)"
fi

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

mkdir -p "$DIST_DIR"

echo "Using app:     $RELEASE_APP"
echo "Identity:      $NOTARY_IDENTITY"
echo "Output dir:    $DIST_DIR"
if [[ -n "${APP_VERSION:-}" ]]; then
  echo "APP_VERSION:   $APP_VERSION (will patch staging Info.plist before signing)"
fi
if [[ -n "${DOWNLOAD_URL_PREFIX:-}" ]]; then
  echo "Download URL:  ${DOWNLOAD_URL_PREFIX}<MeetingScribe.dmg>"
fi
echo "---"

# 1. dist にコピーして拡張属性を削除
echo "[1] Copying app to $DIST_DIR and clearing xattr..."
rm -rf "$STAGING_APP"
ditto --norsrc "$RELEASE_APP" "$STAGING_APP"
xattr -cr "$STAGING_APP"

# 1.5 APP_VERSION を staging の Info.plist に反映（ビルド番号は git のコミット数）
if [[ -n "${APP_VERSION:-}" ]]; then
  STAGING_PLIST="$STAGING_APP/Contents/Info.plist"
  BUILD_NUM="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
  echo "[1.5] Patching $STAGING_PLIST → CFBundleShortVersionString=$APP_VERSION CFBundleVersion=$BUILD_NUM"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$STAGING_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$STAGING_PLIST"
fi

# 2. すべてのバイナリを hardened runtime で署名（内側から外側の順に署名する）
echo "[2] Signing all binaries..."

# 2a. Resources 内の dylib と whisper
for f in "$STAGING_APP/Contents/Resources/"*.dylib; do
  [[ -e "$f" ]] || continue
  codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$f"
done
codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$STAGING_APP/Contents/Resources/whisper"

# 2b. Sparkle フレームワーク内のバイナリ（XPC Services → Updater.app → Autoupdate → フレームワーク本体の順）
SPARKLE_FW="$STAGING_APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  echo "  Signing Sparkle framework binaries..."
  # XPC Services
  for xpc in "$SPARKLE_FW/Versions/B/XPCServices/"*.xpc; do
    [[ -d "$xpc" ]] || continue
    codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$xpc"
  done
  # Updater.app
  if [[ -d "$SPARKLE_FW/Versions/B/Updater.app" ]]; then
    codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$SPARKLE_FW/Versions/B/Updater.app"
  fi
  # Autoupdate
  if [[ -f "$SPARKLE_FW/Versions/B/Autoupdate" ]]; then
    codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$SPARKLE_FW/Versions/B/Autoupdate"
  fi
  # Sparkle フレームワーク本体
  codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$SPARKLE_FW"
fi

# 2c. アプリ本体（最後に署名）
codesign --force --options runtime --sign "$NOTARY_IDENTITY" "$STAGING_APP"

echo "[3] Verifying code signature..."
codesign --verify --verbose --strict "$STAGING_APP"

# 4. 公証用 zip を提出
echo "[4] Submitting app to Apple for notarization..."
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$STAGING_APP" "$ZIP_PATH"
submit_notary_and_require_accept "$ZIP_PATH" "app (zip)"
rm -f "$ZIP_PATH"

# 5. スタンプ
echo "[5] Stapling notarization ticket to app..."
xcrun stapler staple "$STAGING_APP"
xcrun stapler validate "$STAGING_APP" || { echo "Staple validation failed."; exit 1; }

echo "[5.1] Verifying Gatekeeper assessment..."
spctl --assess --type execute --verbose "$STAGING_APP"

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
    "$DIST_DIR"
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: Expected DMG not found at $DMG_PATH (check create-dmg output)."
    exit 1
  fi

  echo "[7] Submitting DMG for notarization..."
  submit_notary_and_require_accept "$DMG_PATH" "DMG"

  echo "[8] Stapling DMG..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH" || { echo "DMG staple validation failed."; exit 1; }

  echo "DMG created: $DMG_PATH"
else
  echo "create-dmg not found. Skipping DMG."
  echo "Signed & stapled app: $STAGING_APP"
  echo "Install create-dmg (e.g. brew install create-dmg) to build a DMG in $DIST_DIR."
fi

# 9. appcast.xml → docs/ のみ（Sparkle はアーカイブディレクトリ内の既存 appcast をマージするため、一時的に dist に置く）
GENERATE_APPCAST="${SPARKLE_BIN_DIR}/generate_appcast"
if [[ -x "$GENERATE_APPCAST" ]]; then
  echo "[9] Generating docs/appcast.xml..."
  APPCAST_ARGS=(-o "$DOCS_APPCAST" "$DIST_DIR")
  if [[ -n "$DOWNLOAD_URL_PREFIX" ]]; then
    APPCAST_ARGS=(--download-url-prefix "$DOWNLOAD_URL_PREFIX" "${APPCAST_ARGS[@]}")
  fi
  if [[ -f "$DOCS_APPCAST" ]]; then
    cp "$DOCS_APPCAST" "$DIST_DIR/appcast.xml"
  fi
  if ! "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}"; then
    rm -f "$DIST_DIR/appcast.xml"
    exit 1
  fi
  rm -f "$DIST_DIR/appcast.xml"
  echo "  $DOCS_APPCAST"
else
  echo "generate_appcast not found. Skipping appcast generation."
  echo "Set SPARKLE_BIN_DIR or ensure Sparkle SPM package is resolved in Xcode."
fi

echo ""
echo "Done."
echo "  App: $STAGING_APP"
[[ -f "$DMG_PATH" ]] && echo "  DMG: $DMG_PATH"
[[ -f "$DOCS_APPCAST" ]] && echo "  Appcast: $DOCS_APPCAST (git commit → Pages)"
