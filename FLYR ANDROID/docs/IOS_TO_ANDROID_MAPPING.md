# FLYR iOS to Android Mapping

This folder is the Android sibling to `FLYR IOS`.

## Product shell mapping

The current iOS `MainTabView.swift` maps directly to the Android bottom navigation shell:

- `HomeView` -> `features/home/HomeScreen.kt`
- `RecordHomeView` -> `features/record/RecordScreen.kt`
- `ContactsHubView` -> `features/leads/LeadsScreen.kt`
- `LeaderboardTabView` -> `features/leaderboard/LeaderboardScreen.kt`
- `SettingsView` -> `features/settings/SettingsScreen.kt`

## Architecture mapping

### iOS

- SwiftUI Views
- Hook-style `Use*` classes
- `ObservableObject` stores
- `*API` clients
- `*Service` classes

### Android

- Compose screens
- `ViewModel` classes
- immutable `UiState` with `StateFlow`
- repositories for remote/local data access
- services for SDK or platform integrations
- root route handling through `AuthGate` + `FlyrAppViewModel`

## Suggested feature port order

1. Auth bootstrap and session restoration
2. Main tab shell
3. Campaign list and campaign context
4. Record + map session flow
5. Leads / contacts
6. Leaderboard and stats
7. Settings, billing, integrations

## Shared concepts to preserve

- app-wide auth/session state
- workspace context
- campaign-driven map flows
- live session recording
- CRM lead sync
- leaderboard/stats snapshots

## Android module direction

For now everything lives in one `app` module so the project can move quickly. If the Android app grows, split later into:

- `core`
- `core-ui`
- `data`
- `feature-auth`
- `feature-campaigns`
- `feature-map`
- `feature-leads`
- `feature-stats`
- `feature-settings`
