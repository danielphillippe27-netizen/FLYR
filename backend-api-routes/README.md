# WolfGrid Sales web app and backend API

Copy the contents of `app/api/integrations/fub/` into your Next.js App Router project:

- `connect/route.ts` → `app/api/integrations/fub/connect/route.ts`
- `disconnect/route.ts` → `app/api/integrations/fub/disconnect/route.ts`

Ensure env vars: `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `CRM_ENCRYPTION_KEY` (32-byte hex or base64 for AES-256), `CRM_ENCRYPTION_KEY_VERSION` (e.g. `1`).

**Apple billing (App Store Server API):** For `/api/billing/apple/verify`, set `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_PRIVATE_KEY` (full .p8 file contents), `APPLE_BUNDLE_ID`, and optionally `APP_APPLE_ID` (numeric app id for production). See `.env.example`.

**Telnyx dialer:** `/api/dialer/token` issues short-lived Telnyx Voice SDK JWTs for the native iOS dialler. Set `TELNYX_API_KEY` to a Telnyx secret API key and set either `TELNYX_IOS_TELEPHONY_CREDENTIAL_ID` or `TELNYX_TELEPHONY_CREDENTIAL_ID` to a Telnyx telephony credential ID, not an API key ID (`SKe...`) and not the secret API key (`KEY...`). Optional env vars: `TELNYX_IOS_PUSH_CREDENTIAL_ID`, `TELNYX_FROM_NUMBER`, `DIALER_ENABLED_WORKSPACE_IDS`, and `DIALER_ENABLED_EMAILS`.

**Telnyx messaging:** `/api/dialer/leads/[leadId]/sms` sends and lists lead text messages for iOS/web. `/api/webhooks/telnyx/messages` receives Telnyx `message.received`, `message.sent`, and `message.finalized` webhooks. Required env vars: `TELNYX_API_KEY`, `TELNYX_DEFAULT_SMS_FROM_NUMBER` (or `TELNYX_FROM_NUMBER`), `TELNYX_MESSAGING_PROFILE_ID`, `TELNYX_PUBLIC_KEY`, and `TELNYX_DEFAULT_WORKSPACE_ID` (or a single `DIALER_ENABLED_WORKSPACE_IDS` value). Configure the Telnyx Messaging Profile webhook URL as `https://sales.wolfgrid.app/api/webhooks/telnyx/messages`.

**Telnyx calls and recordings:** `/api/dialer/calls` records native iOS call events and `/api/webhooks/telnyx/calls` ingests Telnyx call lifecycle and `call.recording.*` webhooks. Answered dialler calls start a dual-channel MP3 recording; the recording ID is retained so web playback can request a fresh Telnyx download URL after the original signed URL expires. Missed inbound calls are stored in `dialer_calls` and surfaced in the shared iOS/web inbox. Configure the Telnyx credential connection webhook URL as `https://sales.wolfgrid.app/api/webhooks/telnyx/calls` and enable Advanced/Call Control events on that credential connection.

**Managed email:** WolfGrid uses Resend for email from the iOS and web inboxes. Set `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `RESEND_INBOUND_DOMAIN`, and `RESEND_WEBHOOK_SECRET`. The sending/receiving domain must be verified in Resend. Configure the Resend webhook URL as `https://sales.wolfgrid.app/api/webhooks/resend` and subscribe to `email.received`, `email.delivered`, `email.bounced`, `email.failed`, `email.complained`, and `email.suppressed`. A reply mailbox is provisioned automatically the first time a salesperson sends an email.

Meeting invitations reply to the salesperson's active Apple mailbox. `MEETING_REPLY_TO_EMAIL` can be set to a verified fallback mailbox when no Apple mailbox is connected; do not point it at a sending-only address.

**Apple/iCloud-hosted email:** For an iCloud Custom Email Domain such as `@wolfgrid.app`, set `EMAIL_ENCRYPTION_KEY` (or reuse `CRM_ENCRYPTION_KEY`). The iOS connection screen verifies the user's Apple app-specific password against `imap.mail.me.com` and `smtp.mail.me.com`, then stores it encrypted in `email_connections`. `/api/cron/email-sync` imports incoming messages; the existing inbox sender uses iCloud SMTP while that connection is active. Keep the domain's MX records pointed at Apple—do not also configure the same domain as a Resend inbound domain.

## WolfSocial publishing

WolfSocial uses the same `/api/social/*` contract for the web workspace and
WolfGrid Sales iOS app. Apply these Supabase migrations in order before
deploying the API:

1. `20260805150000_social_publishing.sql`
2. `20260805210000_wolfsocial_workspaces.sql`
3. `20260806010000_wolfsocial_linkedin.sql`

The deployment needs `NEXT_PUBLIC_SALES_APP_URL`,
`NEXT_PUBLIC_SOCIAL_APP_URL`, `SOCIAL_TOKEN_ENCRYPTION_KEY`,
`SOCIAL_MEDIA_URL_SECRET`, `CRON_SECRET`, and the existing Supabase server
credentials. Provider credentials are `META_APP_ID`, `META_APP_SECRET`,
`META_WEBHOOK_VERIFY_TOKEN`, optional Instagram-specific client credentials,
`TIKTOK_CLIENT_KEY`, `TIKTOK_CLIENT_SECRET`, `YOUTUBE_CLIENT_ID`,
`YOUTUBE_CLIENT_SECRET`, `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`,
`LINKEDIN_API_VERSION`, and `LINKEDIN_ORGANIZATION_SCOPES`.

Register each provider callback at:

`https://sales.wolfgrid.app/api/social/oauth/{platform}/callback`

where `platform` is `facebook`, `instagram`, `tiktok`, `youtube`, or
`linkedin`. Native OAuth returns through `wolfgridsales://social/oauth-complete`.

Vercel runs `/api/cron/social-publish` and `/api/cron/social-sync` every minute.
Both require Vercel's `Authorization: Bearer $CRON_SECRET` header. Meta webhook
events are received at `/api/social/webhooks/meta` and verified using
`META_WEBHOOK_VERIFY_TOKEN` plus the request signature.

For TikTok Content Posting review, verify this URL prefix in the TikTok
developer portal before testing Direct Post:

`https://social.wolfgrid.app/api/social/media/`

The web and iOS composers both fetch live creator information when the TikTok
account is selected, require a manually selected privacy value, default all
interaction controls off, hide Duet/Stitch for photos, show an editable media
preview, collect commercial-content disclosures and the required policy/music
confirmation, enforce the creator's current maximum video duration, and report
asynchronous processing status. Server-hosted photos and videos are sent using
TikTok's `PULL_FROM_URL` mode. Re-record the complete flow on both surfaces for
the provider review whenever this UX changes.

Run `npm run test:social` for the provider contract, encryption, and post-media
validation tests. Run `npm run build` before deploying.
