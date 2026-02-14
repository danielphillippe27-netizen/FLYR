# Connect Follow Up Boss – Wiring

## Where the modal is shown
- **Screen**: Settings → **CRM Integrations** (IntegrationsView).
- **Trigger**: User taps **Connect** on the **Follow Up Boss** card.
- **Flow**: `handleConnect(provider: .fub)` sets `showConnectFUB = true`; the sheet presents `ConnectFUBView`. No `user_id` is sent from the app; the backend uses the JWT for the user.

## Where “Connected ●” is shown
- **FUB card** on the same Integrations screen: connected state comes from **CRMConnectionStore** (table `crm_connections`), not from `user_integrations`.
- **IntegrationCardView** gets `crmConnection: crmStore.fubConnection` for the FUB provider and shows “Connected ●” when `crmConnection?.isConnected == true`.

## After connect
- On success, the modal dismisses, `CRMConnectionStore.shared.refresh(userId:)` and `loadIntegrations()` run so the FUB card updates without leaving the screen.

## Disconnect
- Tapping **Disconnect** on the FUB card calls **FUBConnectAPI.shared.disconnect()** (backend `DELETE /api/integrations/fub/disconnect`). The backend deletes the row in `crm_connections` (and the secret); the app then refreshes the store and integrations list.

## Backend routes (copy to Next.js app)
- Copy `backend-api-routes/app/api/integrations/fub/` into your flyrpro.app App Router:
  - `connect/route.ts` → POST, body `{ "api_key" }`, JWT required.
  - `disconnect/route.ts` → DELETE, JWT required.
- Env: `CRM_ENCRYPTION_KEY` (32 bytes), `CRM_ENCRYPTION_KEY_VERSION`, Supabase URL/keys.

## Supabase
- Run migration `supabase/migrations/20250209100000_create_crm_connections.sql` to create `crm_connections` and `crm_connection_secrets`.
