# HubSpot integration (FLYR backend)

## Env vars

| Variable | Required | Description |
|----------|----------|-------------|
| `HUBSPOT_CLIENT_ID` | Yes | HubSpot app client ID |
| `HUBSPOT_CLIENT_SECRET` | Yes | HubSpot app client secret |
| `OAUTH_STATE_SECRET` or `CRM_ENCRYPTION_KEY` | Yes | HMAC secret for signed OAuth `state` |
| `HUBSPOT_OAUTH_SCOPE` | No | Space-separated scopes. Default matches HubSpot’s **developer-platform** scope picker: **`oauth`**, **`crm.objects.contacts.read`**, **`crm.objects.contacts.write`**, **`crm.schemas.appointments.read`**, **`crm.schemas.appointments.write`**, **`crm.objects.appointments.read`**, **`crm.objects.appointments.write`**. (Granular `crm.objects.notes.write` / tasks / meetings often do not appear in search—FLYR still calls notes/tasks APIs with contacts scopes.) The install URL must list every scope your app marks **Required** and must not request scopes your app does not expose. |
| `HUBSPOT_OAUTH_REDIRECT_URI` | No | Override callback URL (default: `{origin}/api/integrations/hubspot/oauth/callback`) |
| `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Yes | Same as other integration routes |

## Routes

- `GET /api/integrations/hubspot/oauth/start?platform=ios&workspaceId=…` — Bearer JWT (optional `token` / `access_token` query for Safari-only edge cases)
- `GET /api/integrations/hubspot/oauth/callback` — HubSpot redirect target; redirects to `flyr://oauth?provider=hubspot&status=success|error`
- `GET /api/integrations/hubspot/status` — connection snapshot
- `POST /api/integrations/hubspot/test` — lightweight CRM API probe
- `POST /api/integrations/hubspot/push-lead` — create/update contact, optional note/task/**appointment** (CRM appointments object, not legacy meetings); uses `crm_object_links` for `crm_type=hubspot`
- `POST` or `DELETE /api/integrations/hubspot/disconnect` — removes tokens and HubSpot links

## QA checklist (manual)

1. Set HubSpot app redirect URI to your deployed callback URL.
2. iOS: Integrations → Connect HubSpot → complete OAuth → return to app via `flyr://oauth`.
3. `GET status` or refresh Integrations — shows connected.
4. Tap **Test connection** (Integrations) or run Sync Settings test lead flow.
5. Capture a field lead with email/name and confirm HubSpot contact + optional note/task/appointment.
6. Disconnect and confirm status disconnected.

## Notes

- Access tokens are refreshed server-side when within ~5 minutes of expiry (when `refresh_token` is present).
- If OAuth shows **“mismatch between the scopes in the install URL and the app's configured scopes”**: add the same scopes as the default list above to your HubSpot app **Auth** tab (or set **`HUBSPOT_OAUTH_SCOPE`** to match your required list **exactly**—no extra scopes HubSpot doesn’t list on the app).
- If OAuth shows **“scopes are missing [crm.schemas.appointments.write]”** (or similar), either add that scope to **`HUBSPOT_OAUTH_SCOPE`** or remove the requirement from the HubSpot app’s **Auth** tab so the authorize request and app config match.
- If notes or tasks return 403 after connect, HubSpot may require additional scopes for your account tier; try adding related CRM scopes from the picker or contact HubSpot support—those granular names often **do not show up** in scope search.
- Sparse field leads (address-only) are enriched server-side in `push-lead` via [`crm-sparse-enrich.ts`](../../../lib/crm-sparse-enrich.ts): synthetic `field+{id-prefix}@capture.flyrpro.app` plus a readable **Property: …** name when needed. iOS applies the same rules before calling this route.
