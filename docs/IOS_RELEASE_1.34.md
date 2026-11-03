# WolfGrid iOS 1.34 — build 21

Prepared November 3, 2026.

## App Store release notes draft

This update improves your farm maps and door-knocking sessions:

- Better address matching and house-number labels, including homes linked to parcels without building outlines.
- Improved map editing, with refinements to adding homes, splitting townhouses, and saving address changes.
- Session progress follows your chosen goal, and adding homes to the map keeps that goal unchanged.
- Fixes for farm and campaign deletion, list loading, and session summaries.

## Build identity

- Main app: `com.danielphillippe.FLYR`
- Version: `1.34`
- Build: `21`
- App and Live Activity extension versions match.
- WolfGrid Sales retains its separate version and build.
- Source baseline: `0f0d4f385`, plus the existing local session-goal and parcel-label changes and this release version update. The archive was built before the release commit from the matching app sources; no release tag has been created.

## Validation

- Final regression run: 408 tests, 405 passed, 3 skipped, 0 failures (`ReleaseReadinessTests.xcresult`). The skipped tests require a local Bowmanville performance fixture that is unavailable.
- Corrected a stale map-colour test expectation; made the Google Maps camera test use a visible window and wait for its camera update; made the cached-demo test wait for observable progress within its existing starvation limit.
- Earlier failing runs are retained in the build folder for comparison. These follow-up changes affect tests only; no app code changed after the successful archive.
- Release archive: succeeded; strict, deep code-signature verification passed.
- App Store export: succeeded with Apple Distribution signing; main app and Live Activity extension both verified as 1.34 (21) inside the IPA.
- Archive: `build/app-store-1.34-21/WolfGrid.xcarchive`
- IPA: `build/app-store-1.34-21/export/WolfGrid.ipa`
- Local build recovery: all temporarily relocated directories were restored to original Xcode paths; rebuildable device Debug outputs were cleared for space.
- Physical iPhone smoke test: pending.
- App Store Connect: sign-in required; latest version/build and review state have not been verified in this session.
- App Store Connect upload: succeeded November 3, 2026 at 11:32 a.m. Toronto time through the saved Xcode account. Apple reported “Uploaded package is processing” and “Upload succeeded.” Receipt: `build/app-store-1.34-21/upload-retry.log`.
- First upload failed with a corrupt-package error under low disk space. After clearing completed compiler intermediates, the retry succeeded. The signed archive and IPA remain intact.
- Non-blocking upload warnings: missing third-party dSYMs for MapboxCommon, MapboxCoreMaps, and WebRTC; crash reports inside those frameworks may lack full symbol names.
- Release source commit: `304ab3439`, pushed to `origin/main`.
- Review submission and public release: not performed.

## Physical iPhone checks before submission

- Open a large existing farm and a small campaign; verify map readiness, addresses, and labels.
- Add a parcel-linked home without a roof, reopen the map, and verify its number remains visible.
- Add/remove an address and split a townhouse; confirm changes survive reopening.
- Start a session with a goal smaller than the farm; verify progress and Live Activity follow the goal when homes are added.
- End a session and check the summary; confirm campaign/farm swipe deletion and cancellation behave correctly.
- Check sign-in, subscription restore, and offline campaign loading.

## Submission handoff

Verify the current App Store Connect version and highest build before upload. Review the draft notes, select the processed build, and resolve any metadata or encryption questions using the binary's actual behavior. This app uses standard encryption; do not describe it as containing no encryption algorithms.
