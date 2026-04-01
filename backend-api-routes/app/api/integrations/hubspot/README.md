# HubSpot integration (FLYR backend)

## Env vars

| Variable | Required | Description |
|----------|----------|-------------|
| `HUBSPOT_CLIENT_ID` | Yes | HubSpot app client ID |
| `HUBSPOT_CLIENT_SECRET` | Yes | HubSpot app client secret |
| `OAUTH_STATE_SECRET` or `CRM_ENCRYPTION_KEY` | Yes | HMAC secret for signed OAuth `state` |
| `HUBSPOT_OAUTH_SCOPE` | No | Space-separated scopes (default includes contacts, notes, tasks, meetings) |
| `HUBSPOT_OAUTH_REDIRECT_URI` | No | Override callback URL (default: `{origin}/api/integrations/hubspot/oauth/callback`) |
| `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Yes | Same as other integration routes |

## Routes

- `GET /api/integrations/hubspot/oauth/start?platform=ios&workspaceId=…` — Bearer JWT (optional `token` / `access_token` query for Safari-only edge cases)
- `GET /api/integrations/hubspot/oauth/callback` — HubSpot redirect target; redirects to `flyr://oauth?provider=hubspot&status=success|error`
- `GET /api/integrations/hubspot/status` — connection snapshot
- `POST /api/integrations/hubspot/test` — lightweight CRM API probe
- `POST /api/integrations/hubspot/push-lead` — create/update contact, optional note/task/meeting; uses `crm_object_links` for `crm_type=hubspot`
- `POST` or `DELETE /api/integrations/hubspot/disconnect` — removes tokens and HubSpot links

## QA checklist (manual)

1. Set HubSpot app redirect URI to your deployed callback URL.
2. iOS: Integrations → Connect HubSpot → complete OAuth → return to app via `flyr://oauth`.
3. `GET status` or refresh Integrations — shows connected.
4. Tap **Test connection** (Integrations) or run Sync Settings test lead flow.
5. Capture a field lead with email/name and confirm HubSpot contact + optional note/task/meeting.
6. Disconnect and confirm status disconnected.

## Notes

- Access tokens are refreshed server-side when within ~5 minutes of expiry (when `refresh_token` is present).
- If notes/tasks/meetings fail with 403, expand scopes in the HubSpot developer app to match `HUBSPOT_OAUTH_SCOPE`.
