# Backend API routes for FLYR (copy to Next.js app at flyrpro.app)

Copy the contents of `app/api/integrations/fub/` into your Next.js App Router project:

- `connect/route.ts` → `app/api/integrations/fub/connect/route.ts`
- `disconnect/route.ts` → `app/api/integrations/fub/disconnect/route.ts`

Ensure env vars: `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `CRM_ENCRYPTION_KEY` (32-byte hex or base64 for AES-256), `CRM_ENCRYPTION_KEY_VERSION` (e.g. `1`).

**Apple billing (App Store Server API):** For `/api/billing/apple/verify`, set `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_PRIVATE_KEY` (full .p8 file contents), `APPLE_BUNDLE_ID`, and optionally `APP_APPLE_ID` (numeric app id for production). See `.env.example`.

**Telnyx dialer:** `/api/dialer/token` issues short-lived Telnyx Voice SDK JWTs for the native iOS dialler. Set `TELNYX_API_KEY` to a Telnyx secret API key and set either `TELNYX_IOS_TELEPHONY_CREDENTIAL_ID` or `TELNYX_TELEPHONY_CREDENTIAL_ID` to a Telnyx telephony credential ID, not an API key ID (`SKe...`) and not the secret API key (`KEY...`). Optional env vars: `TELNYX_IOS_PUSH_CREDENTIAL_ID`, `TELNYX_FROM_NUMBER`, `DIALER_ENABLED_WORKSPACE_IDS`, and `DIALER_ENABLED_EMAILS`.

**Telnyx messaging:** `/api/dialer/leads/[leadId]/sms` sends and lists lead text messages for iOS/web. `/api/webhooks/telnyx/messages` receives Telnyx `message.received`, `message.sent`, and `message.finalized` webhooks. Required env vars: `TELNYX_API_KEY`, `TELNYX_DEFAULT_SMS_FROM_NUMBER` (or `TELNYX_FROM_NUMBER`), `TELNYX_MESSAGING_PROFILE_ID`, `TELNYX_PUBLIC_KEY`, and `TELNYX_DEFAULT_WORKSPACE_ID` (or a single `DIALER_ENABLED_WORKSPACE_IDS` value). Configure the Telnyx Messaging Profile webhook URL as `https://www.flyrpro.app/api/webhooks/telnyx/messages`.
