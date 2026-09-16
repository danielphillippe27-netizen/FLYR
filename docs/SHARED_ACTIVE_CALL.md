# Shared active call — implementation plan

Let a signed-in salesperson see who they are calling on iOS and web at the same time.

1. Add a private, workspace/user/device-scoped presence table with a 90-second lease.
2. Add an authenticated `PUT /api/dialer/active-call` endpoint that renews or clears this device's snapshot and returns calls on the user's other devices.
3. Publish iOS SDK state centrally so lead calls, manual calls, and answered incoming calls work without depending on the dialer screen being open.
4. Publish browser SDK state and render a companion card throughout the Sales web app. Render the corresponding banner above the iOS tabs.
5. Verify the native JSON contract, both directions, status updates, hangup, abandoned sessions, identity isolation, builds, and browser rendering.

## Behavior

- The calling device supplies contact name, phone number, connecting/connected status, and timestamps. Duration starts when connected.
- The other device displays the call within a polling interval (three seconds plus network time). Audio and controls remain on the calling device.
- Manual calls display the dialed number when no contact name is available.
- An idle device clears only its own presence. Multiple tabs/devices cannot clear one another's calls.
- Network failures show an unavailable state instead of claiming the last snapshot is live. Presence expires after 90 seconds without renewal.
- Hidden idle web tabs and background idle iOS sessions skip polling; active calls continue renewing while the OS allows execution. A suspended/killed app eventually expires.
- Account/workspace changes hide old results and prevent publishing an old call into the new scope.
- Presence is separate from durable call history. Clients never directly access the presence table; all requests use the existing cookie/bearer authentication and workspace membership checks.

## Release order

1. Apply `supabase/migrations/20260909190000_dialer_active_devices.sql` to the Sales Supabase database.
2. Deploy the Sales web/API source in `backend-api-routes`.
3. Build/install the updated WolfGrid Sales iOS app.

No new environment variables or telecom configuration are needed. Local implementation does not itself deploy the web app, apply production migrations, or distribute an iOS build.

## Verification

Completed locally: Sales web TypeScript check; seven API regression tests; Swift JSON encoding/decoding checks; iOS simulator build for arm64 and x86_64; browser checks using the real component with controlled SDK/API fixtures for contact display, status, hangup, account changes, network failure, and expiry. The production schema migration was applied and verified on September 9, 2026; live phone calls have not been exercised.

- API regression tests: `cd backend-api-routes && npx tsx --test lib/dialer/__tests__/active-call.test.ts`
- Swift payload check: compile `WolfGridSales/App/Features/Salesperson/SharedCallSnapshot.swift` with `scripts/test-shared-call-payload.swift`, then run the executable.
- Real-device acceptance after release: sign into the same workspace/account on both devices; start a call on each in turn; confirm name, phone, phase, duration, and clearing after hangup. Repeat with a manual number, backgrounded calling device, disconnected device, and a workspace/account switch. Live audio calls require a controlled test recipient.

## Migration applied — September 9, 2026

Applied `20260909190000_dialer_active_devices` to the linked WolfGrid project (`yxxuazvosddtajwitlxu`) and recorded it in migration history in the same transaction. Verified the table, both foreign keys, expiry index, enabled RLS, blocked direct anon/authenticated access, and service-role access. Web/API deployment and the updated iOS installation remain release steps.
