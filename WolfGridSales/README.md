# WolfGrid Sales

`WolfGrid Sales` is a private, self-contained iPhone app target. Its complete
copy of the connected iOS source and resources lives under `App/`, while the
target keeps its own bundle identity, entitlements, Info.plist, background
modes, app icon, and build version.

## App split

`WolfGrid Sales` is no longer a selectable mode inside the public app. It has
its own fixed root in `SalespersonMainTabView.swift` and always shows the
Sales experience: Home, Phone, Messages, Emails, Contacts, List, and Follow Up.

The public `WolfGrid` target now has only the regular field/campaign tab root.
The copied app includes the authentication, API models, design components,
Sales data services, dialler, messaging, tasks, Telnyx voice integration,
notifications, and other dependencies that were connected in the original
iOS app. It still talks to the same deployed backend and Supabase services.

The Sales target compiles `WolfGridSales/App` and does not compile files from
the neighboring `WolfGrid` source folder.

## Run it

1. Open `WolfGridSales/WolfGridSales.xcodeproj`.
2. Select the `WolfGrid Sales` scheme.
3. Select Daniel's physical iPhone.
4. Open the `WolfGrid Sales` target's Signing & Capabilities tab and confirm
   team `2AR5T8ZYAS` with automatic signing.
5. Build and run.
6. Sign in with the existing salesperson email/password account.

The Sales build defines `WOLFGRID_SALES`, so a signed-in workspace opens the
dedicated Sales root. The public `WolfGrid` target has no Sales mode.

## Bundle configuration

- Display name: `WolfGrid Sales`
- Bundle ID: `com.danielphillippe.wolfgrid.sales`
- URL scheme: `wolfgridsales`
- Initial version: `1.0 (1)`
- Background modes: `audio`, `location`, `voip`

## Apple Developer setup

The new bundle ID needs an App ID and development provisioning profile. Xcode
can create these when automatic signing is enabled and the target is first run
on a registered device.

Enable these capabilities for `com.danielphillippe.wolfgrid.sales`:

- Push Notifications
- Sign in with Apple
- Associated Domains
- HealthKit

For a private installation, run directly from Xcode or export an Ad Hoc build
for the registered iPhone. App Store submission is not required.

## Telnyx incoming-call setup

Outbound calls can use the existing backend Telnyx telephony credential.
Incoming calls while the app is backgrounded require a new VoIP Services
certificate because the Sales app has a new bundle ID.

1. Create a VoIP Services certificate for
   `com.danielphillippe.wolfgrid.sales` in Apple Certificates, Identifiers &
   Profiles.
2. Export the certificate and private key.
3. Create a new iOS push credential in Telnyx.
4. Attach that credential to the Telnyx SIP Connection's WebRTC iOS settings.
5. Set the deployed backend's `TELNYX_IOS_PUSH_CREDENTIAL_ID` to the new
   Telnyx push credential ID.
6. Test an incoming call with the app backgrounded and with the phone locked.

Debug builds use APNs sandbox; Release and Ad Hoc builds use APNs production.

## Authentication notes

Email/password sign-in uses the existing Supabase account and requires no new
OAuth client.

The new bundle ID must be added to the existing Sign in with Apple setup if the
same Apple-backed user identity should work in both apps. Google sign-in may
also require a separate iOS OAuth client registered for
`com.danielphillippe.wolfgrid.sales`; until that is configured, use the
existing salesperson email/password login.
