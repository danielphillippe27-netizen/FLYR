# Android map changes

The earlier `android-map-parity.patch` is now present in `/Volumes/Samsung SSD/WolfGrid/WolfGrid-ANDROID`. Its current `docs/MAP_2D_PARITY.md` records a successful full debug build, 319 unit tests and device-test compilation. Do not apply that original patch again.

## New: standard 2D location marker

`android-2d-location.patch` replaces the 2D wolf portrait with a blue location dot, GPS accuracy circle and live direction cone on campaign and active-session maps. It uses the existing compass sensor independently of GPS fixes, pauses sensor updates when the app leaves the foreground, and retains the wolf on the 3D map.

This new patch is prepared against the current Android working tree, preserving the newer networking edits. **The new location change has not been applied to the Android folder from this chat**, because that folder remains read-only here.

From the Android project:

```sh
git apply --check '../WolfGrid-IOS/android-parity/android-2d-location.patch'
git apply '../WolfGrid-IOS/android-parity/android-2d-location.patch'
./gradlew :app:testProductionDebugUnitTest :app:assembleProductionDebug
```

The three modified/new Kotlin files compile against the cached Android, Google Maps, Mapbox and Compose SDKs. The existing 22 focused map regression tests pass. This validation uses cached project classes for unchanged dependencies and is not a full APK build of the new location change. The new patch passes `git apply --check --whitespace=error` against the current Android folder.

`android-2d-location-manifest.json` records baseline and resulting hashes. Recheck the patch if the Android project changes before applying it.

On a real device, verify the blue dot and accuracy circle at your location, turn the stationary phone to check the cone, background/foreground the app to check sensor cleanup, and switch to 3D to confirm the wolf remains there. No device/emulator interaction test was run in this chat.
