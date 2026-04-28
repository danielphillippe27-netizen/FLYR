# FLYR Android

Initial Android framework for bringing the existing `FLYR IOS` product to Android with Kotlin and Jetpack Compose.

## What is here

- Kotlin DSL Gradle project scaffold
- Android `app` module using Jetpack Compose
- Official Gradle wrapper files checked into the project
- BuildConfig placeholders for Supabase and Mapbox values
- Real Supabase email/password auth wiring with local session restore
- Backend-driven access route resolution from FLYR `/api/access/state` and `/api/access/redirect`
- Owner onboarding form wired to `POST /api/onboarding/complete`
- Subscribe/paywall routing that distinguishes owner checkout from `member-inactive` access loss
- Owner Stripe checkout bootstrap wired to `POST /api/billing/stripe/checkout`
- Bottom-tab shell mirroring the iOS app's primary navigation:
  - Home
  - Record
  - Leads
  - Leaderboard
  - Settings
- Package boundaries for the first Android translation of the iOS architecture:
  - `app`
  - `core`
  - `navigation`
  - `data`
  - `features`
  - `designsystem`

## Architecture direction

The iOS app uses a Hooks / Stores / Views pattern. This Android scaffold maps that to:

- `Composable` screens for views
- `ViewModel` + `UiState` for hooks/stores
- repositories and services in `data/`
- shared app state in `core/`
- an auth/route gate in `app/` to mirror iOS `AuthGate` + `AppRouteState`
- Supabase-backed session restore with `SharedPreferences` preserving Android-only preview state

See [docs/IOS_TO_ANDROID_MAPPING.md](/Users/danielphillippe/Desktop/FLYR/FLYR%20ANDROID/docs/IOS_TO_ANDROID_MAPPING.md) for the cross-platform mapping.

## Open next steps

1. Add real Supabase sign-up, password reset, and OAuth providers
2. Add invite validation and accept flows for team onboarding links
3. Confirm Stripe return handling more explicitly after checkout and add billing management routes
4. Add Mapbox Android SDK and port the record/map flows
5. Move campaign, lead, and stats APIs behind Android repositories

## Notes

- I assumed "kovlin" meant `Kotlin`.
- This is a framework scaffold, not a finished parity build yet.
- Set `flyr.supabase.url`, `flyr.supabase.anonKey`, and `flyr.mapbox.publicToken` in `local.properties`.
- Optionally set `flyr.pro.apiUrl` in `local.properties` if you need a non-production backend.
- If Supabase credentials are present, the login screen now uses real email/password auth and restores the local session on launch.
- Owner checkout opens the Stripe session URL externally and refreshes access on app resume so Android can pick up newly granted access.
