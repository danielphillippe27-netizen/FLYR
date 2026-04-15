# BoldTrail / kvCORE CRM Integration MVP

## Scope

This integration adds a token-based BoldTrail / kvCORE CRM connection for iOS and web.

- Connection model: manual API token entry
- Sync direction: FLYR -> BoldTrail
- MVP sync type: contact/lead
- Save behavior: non-blocking, local save always wins

## User Flow

1. User opens CRM integrations in FLYR iOS or FLYR-PRO web.
2. User selects `BoldTrail / kvCORE`.
3. User pastes a BoldTrail API token.
4. FLYR calls the backend `test` endpoint.
5. If validation succeeds, the user can save the token.
6. Backend encrypts and stores the token in `crm_connection_secrets`.
7. Later lead saves push normalized lead data to the backend `push-lead` endpoint.
8. Backend creates or updates the BoldTrail contact and persists the remote mapping in `crm_object_links`.

## Backend Routes

- `POST /api/integrations/boldtrail/test`
- `POST /api/integrations/boldtrail/connect`
- `POST /api/integrations/boldtrail/disconnect`
- `GET /api/integrations/boldtrail/status`
- `POST /api/integrations/boldtrail/push-lead`

## Data Storage

- Connection status and metadata: `crm_connections`
- Encrypted token: `crm_connection_secrets`
- Remote object mapping: `crm_object_links`

## Environment

- `CRM_ENCRYPTION_KEY`
- `CRM_ENCRYPTION_KEY_VERSION`
- `SUPABASE_SERVICE_ROLE_KEY`
- Optional: `BOLDTRAIL_API_BASE`

Default API base is `https://api.kvcore.com`.

## MVP Limitations

- No OAuth flow
- No two-way sync
- No remote search/dedupe beyond stored remote ID reuse
- No notes, follow-up tasks, or appointments yet
- Exact BoldTrail field mapping may need refinement against live tenant behavior

## Extension Points

- `backend-api-routes/app/lib/boldtrail.ts`
- `backend-api-routes/app/api/integrations/boldtrail/*`
- `FLYR/Features/Integrations/Services/BoldTrailConnectAPI.swift`
- `FLYR/Features/Integrations/Services/BoldTrailPushLeadAPI.swift`
- `web/src/components/ConnectBoldTrailModal.tsx`
- `web/src/lib/integrations.ts`
