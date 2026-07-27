#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <MeetingScribe.app path>" >&2
  exit 2
fi

app_path=$1
if [ ! -d "$app_path" ]; then
  echo "ERROR: app bundle not found: $app_path" >&2
  exit 2
fi

signing_info=$(codesign -dvvv --requirements - "$app_path" 2>&1)

if echo "$signing_info" | grep -q 'Signature=adhoc'; then
  echo "ERROR: Debug app is ad-hoc signed." >&2
  echo "Create an Apple Development certificate and build without CODE_SIGN_IDENTITY=-." >&2
  exit 1
fi

if ! echo "$signing_info" | grep -q 'Authority=Apple Development:'; then
  echo "ERROR: Debug app is not signed with an Apple Development certificate." >&2
  exit 1
fi

if ! echo "$signing_info" | grep -q 'TeamIdentifier=3R3JQ22JJF'; then
  echo "ERROR: unexpected signing team; expected 3R3JQ22JJF." >&2
  exit 1
fi

if echo "$signing_info" | grep -q 'designated => cdhash'; then
  echo "ERROR: Designated Requirement is tied to a changing CDHash." >&2
  exit 1
fi

echo "PASS: stable Apple Development signature (Team 3R3JQ22JJF)"
