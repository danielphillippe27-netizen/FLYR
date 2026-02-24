# Backend API routes for FLYR (copy to Next.js app at flyrpro.app)

Copy the contents of `app/api/integrations/fub/` into your Next.js App Router project:

- `connect/route.ts` → `app/api/integrations/fub/connect/route.ts`
- `disconnect/route.ts` → `app/api/integrations/fub/disconnect/route.ts`

Ensure env vars: `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `CRM_ENCRYPTION_KEY` (32-byte hex or base64 for AES-256), `CRM_ENCRYPTION_KEY_VERSION` (e.g. `1`).

**Apple billing (App Store Server API):** For `/api/billing/apple/verify`, set `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_PRIVATE_KEY` (full .p8 file contents), `APPLE_BUNDLE_ID`, and optionally `APP_APPLE_ID` (numeric app id for production). See `.env.example`.
