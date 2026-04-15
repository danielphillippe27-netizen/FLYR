#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FLYR.xcodeproj"
SCHEME="${SCHEME:-FLYR}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-$ROOT_DIR/build/app-store}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ARCHIVE_ROOT/${SCHEME}.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ARCHIVE_ROOT/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ARCHIVE_ROOT/ExportOptions.plist}"
LOCAL_CONFIG_PATH="$ROOT_DIR/Config.local.xcconfig"
TEAM_ID="${TEAM_ID:-2AR5T8ZYAS}"

SKIP_UPLOAD=0
CLEAN_BUILD=0
GENERATED_LOCAL_CONFIG=0
TEMP_KEY_PATH=""

usage() {
  cat <<'EOF'
Usage:
  scripts/release_ios_app_store.sh [--skip-upload] [--clean]

What it does:
  1. Ensures a local Mapbox token is available for archive builds.
  2. Archives the FLYR iOS app for generic iOS devices.
  3. Exports an App Store Connect IPA.
  4. Uploads the IPA to App Store Connect unless --skip-upload is passed.

Required for archive:
  - Either an existing Config.local.xcconfig file, or MAPBOX_ACCESS_TOKEN in the environment.

Required for upload:
  - APP_STORE_CONNECT_KEY_ID
  - APP_STORE_CONNECT_ISSUER_ID
  - One of:
      APP_STORE_CONNECT_KEY_PATH
      APP_STORE_CONNECT_PRIVATE_KEY

Examples:
  export MAPBOX_ACCESS_TOKEN='pk....'
  export APP_STORE_CONNECT_KEY_ID='ABC123XYZ9'
  export APP_STORE_CONNECT_ISSUER_ID='00000000-0000-0000-0000-000000000000'
  export APP_STORE_CONNECT_KEY_PATH="$HOME/Downloads/AuthKey_ABC123XYZ9.p8"
  scripts/release_ios_app_store.sh

  MAPBOX_ACCESS_TOKEN='pk....' scripts/release_ios_app_store.sh --skip-upload
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

cleanup() {
  if [[ "$GENERATED_LOCAL_CONFIG" -eq 1 && -f "$LOCAL_CONFIG_PATH" ]]; then
    rm -f "$LOCAL_CONFIG_PATH"
  fi
  if [[ -n "$TEMP_KEY_PATH" && -f "$TEMP_KEY_PATH" ]]; then
    rm -f "$TEMP_KEY_PATH"
  fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-upload)
      SKIP_UPLOAD=1
      shift
      ;;
    --clean)
      CLEAN_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command xcodebuild
require_command xcrun

mkdir -p "$ARCHIVE_ROOT"

if [[ "$CLEAN_BUILD" -eq 1 ]]; then
  log "Cleaning previous archive artifacts"
  rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$EXPORT_OPTIONS_PLIST"
fi

if [[ ! -f "$LOCAL_CONFIG_PATH" ]]; then
  [[ -n "${MAPBOX_ACCESS_TOKEN:-}" ]] || fail "Missing Config.local.xcconfig and MAPBOX_ACCESS_TOKEN is not set."
  log "Creating temporary Config.local.xcconfig from MAPBOX_ACCESS_TOKEN"
  printf 'MAPBOX_ACCESS_TOKEN = %s\n' "$MAPBOX_ACCESS_TOKEN" > "$LOCAL_CONFIG_PATH"
  GENERATED_LOCAL_CONFIG=1
fi

MAPBOX_LINE="$(grep '^MAPBOX_ACCESS_TOKEN[[:space:]]*=' "$LOCAL_CONFIG_PATH" | tail -n 1 || true)"
if [[ -z "$MAPBOX_LINE" ]]; then
  fail "Config.local.xcconfig exists but does not define MAPBOX_ACCESS_TOKEN."
fi

MAPBOX_VALUE="${MAPBOX_LINE#*=}"
MAPBOX_VALUE="$(printf '%s' "$MAPBOX_VALUE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -z "$MAPBOX_VALUE" || "$MAPBOX_VALUE" == "YOUR_MAPBOX_PUBLIC_TOKEN" || "$MAPBOX_VALUE" == "REPLACE_WITH_YOUR_MAPBOX_PUBLIC_TOKEN" ]]; then
  fail "Config.local.xcconfig defines MAPBOX_ACCESS_TOKEN, but the value is empty or still a placeholder."
fi

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

log "Archiving ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

log "Exporting IPA for App Store Connect"
rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print -quit)"
[[ -n "$IPA_PATH" ]] || fail "Export succeeded but no IPA was found in $EXPORT_PATH."

log "IPA ready at $IPA_PATH"

if [[ "$SKIP_UPLOAD" -eq 1 ]]; then
  log "Skipping upload as requested"
  exit 0
fi

[[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]] || fail "APP_STORE_CONNECT_KEY_ID is required for upload."
[[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] || fail "APP_STORE_CONNECT_ISSUER_ID is required for upload."

if [[ -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
  [[ -f "$APP_STORE_CONNECT_KEY_PATH" ]] || fail "APP_STORE_CONNECT_KEY_PATH does not exist: $APP_STORE_CONNECT_KEY_PATH"
  KEY_PATH="$APP_STORE_CONNECT_KEY_PATH"
elif [[ -n "${APP_STORE_CONNECT_PRIVATE_KEY:-}" ]]; then
  TEMP_KEY_PATH="$ARCHIVE_ROOT/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$TEMP_KEY_PATH"
  KEY_PATH="$TEMP_KEY_PATH"
else
  fail "Provide APP_STORE_CONNECT_KEY_PATH or APP_STORE_CONNECT_PRIVATE_KEY for upload."
fi

log "Uploading IPA to App Store Connect"
xcrun altool \
  --upload-app \
  --file "$IPA_PATH" \
  --type ios \
  --api-key "$APP_STORE_CONNECT_KEY_ID" \
  --api-issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --p8-file-path "$KEY_PATH" \
  --show-progress \
  --output-format json

log "Upload complete. Finish release steps in App Store Connect."
