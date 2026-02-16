# Connect Follow Up Boss – Wiring

## Auth: Bearer token for all FUB API calls
The iOS app uses **Bearer JWT** (Supabase access token) for every FLYR integration endpoint. The backend resolves the user with `Authorization: Bearer <token>` and does **not** rely on cookies. Native Connect and lead push work from the app without a WebView.

## Where the key is stored
When the user connects via the native **Connect Follow Up Boss** flow:
- The backend validates the FUB API key, **encrypts** it, and stores it in **`crm_connection_secrets`** (one row per connection, keyed by `crm_connections.id`).
- Status (connected/disconnected) is stored in **`crm_connections`** (provider `fub`). The app never reads or stores the raw API key; it is only sent once to the FLYR API at connect time.

## Lead sync: use the key in `crm_connection_secrets`
Lead sync for users who connected natively **must** use the key stored in `crm_connection_secrets`. The app does this by calling the FLYR backend **push-lead** and **sync-crm** endpoints (Bearer auth). The backend decrypts the key and calls Follow Up Boss. The Supabase Edge Function `crm_sync` reads **`user_integrations`** only, so it does **not** see keys stored by the native Connect flow. Pushing leads from the app goes through the FLYR API (`POST /api/integrations/fub/push-lead`) so that native-Connect users’ leads are sent to Follow Up Boss.

## Where the modal is shown
- **Screen**: Settings → **CRM Integrations** (IntegrationsView).
- **Trigger**: User taps **Connect** on the **Follow Up Boss** card.
- **Flow**: `handleConnect(provider: .fub)` sets `showConnectFUB = true`; the sheet presents `ConnectFUBView`. The backend uses the **Bearer JWT** in the request for the user.

## Where “Connected ●” is shown
- **FUB card** on the same Integrations screen: connected state comes from **CRMConnectionStore** (table `crm_connections`), not from `user_integrations`.
- **IntegrationCardView** gets `crmConnection: crmStore.fubConnection` for the FUB provider and shows “Connected ●” when `crmConnection?.isConnected == true`.

## After connect
- On success, the modal dismisses, `CRMConnectionStore.shared.refresh(userId:)` and `loadIntegrations()` run so the FUB card updates without leaving the screen.

## Disconnect
- Tapping **Disconnect** on the FUB card calls **FUBConnectAPI.shared.disconnect()** (backend `DELETE /api/integrations/fub/disconnect`). The backend deletes the row in `crm_connections` (and the secret in `crm_connection_secrets`); the app then refreshes the store and integrations list.

## Backend routes (copy to Next.js app)
Copy `backend-api-routes/app/api/integrations/fub/` and `backend-api-routes/app/api/leads/` into your flyrpro.app App Router. All routes require **Bearer** token in `Authorization` header.

| Method | Path | Purpose |
|--------|------|--------|
| POST | `/api/integrations/fub/connect` | Connect FUB; body `{ "api_key" }`. |
| DELETE | `/api/integrations/fub/disconnect` | Disconnect; deletes `crm_connections` row and secret. |
| GET | `/api/integrations/fub/status` | Return connected, status, lastSyncAt, lastError. |
| POST | `/api/integrations/fub/test` | Test stored key (FUB /me). |
| POST | `/api/integrations/fub/test-push` | Send a test lead to FUB. |
| POST | `/api/integrations/fub/push-lead` | Push one lead to FUB; body: firstName, lastName, email, phone, address, message, source, etc. (at least one of email or phone). |
| POST | `/api/leads/sync-crm` | Sync existing contacts to FUB (backend fetches from `contacts` and pushes each). |

Shared helper: `app/lib/crm-auth.ts` (decrypt, getFubApiKeyForUser). Env: `CRM_ENCRYPTION_KEY` (32 bytes hex), `CRM_ENCRYPTION_KEY_VERSION`, Supabase URL/keys.

## Supabase
- Run migration `supabase/migrations/20250209100000_create_crm_connections.sql` to create `crm_connections` and `crm_connection_secrets`.
