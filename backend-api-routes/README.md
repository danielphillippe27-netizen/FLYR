# Backend API routes for FLYR (copy to Next.js app at flyrpro.app)

Copy the contents of `app/api/integrations/fub/` into your Next.js App Router project:

- `connect/route.ts` → `app/api/integrations/fub/connect/route.ts`
- `disconnect/route.ts` → `app/api/integrations/fub/disconnect/route.ts`

Ensure env vars: `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `CRM_ENCRYPTION_KEY` (32-byte hex or base64 for AES-256), `CRM_ENCRYPTION_KEY_VERSION` (e.g. `1`).
