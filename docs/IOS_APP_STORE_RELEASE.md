# iOS App Store Release

This repo now supports local-only secret injection for archive and App Store Connect upload.

## What changed

- Tracked `Config.xcconfig` keeps placeholders.
- Ignored `Config.local.xcconfig` holds machine-only secrets like `MAPBOX_ACCESS_TOKEN`.
- `scripts/release_ios_app_store.sh` archives and exports the iOS app, then uploads the IPA to App Store Connect.

## One-time setup

1. Make sure Xcode can sign for team `2AR5T8ZYAS`.
2. Put the Mapbox token in local config:

```xcconfig
MAPBOX_ACCESS_TOKEN = pk....
```

3. Get an App Store Connect API key:
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - the `.p8` private key file

## Release command

```sh
export APP_STORE_CONNECT_KEY_ID='YOUR_KEY_ID'
export APP_STORE_CONNECT_ISSUER_ID='YOUR_ISSUER_ID'
export APP_STORE_CONNECT_KEY_PATH="$HOME/Downloads/AuthKey_YOUR_KEY_ID.p8"

./scripts/release_ios_app_store.sh
```

If you do not want to keep a local config file on a CI machine, inject the Mapbox token as an environment variable for the build:

```sh
export MAPBOX_ACCESS_TOKEN='pk....'
./scripts/release_ios_app_store.sh
```

## Helpful flags

```sh
./scripts/release_ios_app_store.sh --skip-upload
./scripts/release_ios_app_store.sh --clean
```

## Output

- Archive: `build/app-store/FLYR.xcarchive`
- IPA: `build/app-store/export/*.ipa`

## After upload

The script gets the binary into App Store Connect. From there you still handle the usual App Store Connect steps for:

- TestFlight internal or external distribution
- release notes / metadata
- review submission
- manual or scheduled App Store release
