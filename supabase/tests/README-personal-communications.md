# Personal communication isolation regression

`personal-communications.mjs` runs the migration in an isolated PGlite database,
with intentionally permissive legacy workspace policies still enabled. It checks
that two users see only their own threads/events/calls/texts and cannot change
someone else's data or transfer ownership. It also checks mixed-thread splitting
and quarantine of historical Telnyx events without verified recipient ownership.

Install `@electric-sql/pglite` in a temporary directory, then run this test with
`PGLITE_MODULE_PATH` pointing to its `dist/index.js`. The test never connects to
Supabase. Backend route tests are in
`backend-api-routes/lib/dialer/__tests__/personal-communications.test.ts`.

Apply `20260909010000_personal_communications_rls.sql` together with the backend
release. The database migration alone cannot secure service-role API queries.
Unknown historical owners remain quarantined; do not backfill them from current
lead assignments or current phone assignments. Reconcile using historical provider
records and assignment evidence. No historical communication is deleted.

Users need personal active phone numbers and voice credentials. Shared voice
credential and SMS-number fallbacks are intentionally unavailable for personal
communication. Release the iOS changes to clear cached inbox/voice state when
accounts or workspaces change.

## Full personal-isolation release sequence

`personal-isolation-combined.mjs` applies all twelve `20260909010000` through
`20260909120000` migrations, in order, to one ephemeral database. It keeps broad
legacy workspace policies and tests two users sharing that workspace. Assertions
cover communication history, CRM, salesperson metrics, private voicemail storage,
legacy contacts/session rows, and valid direct lead claims under the combined RLS.

```sh
PGLITE_MODULE_PATH=/tmp/wolfgrid-personal-rls/node_modules/@electric-sql/pglite/dist/index.js \
  node supabase/tests/personal-isolation-combined.mjs
```

Run from the repository root after the documented temporary PGlite installation.
The focused tests also cover rejection cases and migration-specific behavior:

- `personal-communications.mjs`
- `personal-sales-metrics.mjs`
- `personal-crm-records.mjs`
- `personal-voicemail-drops.mjs`
- `personal-legacy-records.mjs`
- `personal-dialer-claim.mjs`
- `personal-communication-references.mjs`

These fixtures include the actual canonical communication table definitions but
simplified surrounding modules. They prove policy/trigger interaction on the
fixture schema; they do not establish compatibility with every deployed schema,
PostgREST embedded-relation behavior, or production enforcement. Those checks and
the coordinated backend/database release remain required.

`personal-push-device.mjs` also verifies ambiguous-token quarantine and one active user per device/environment.

`personal-booking-access.mjs` checks personal privacy from workspace owners and team read/edit separation.

The dedicated local `personal-postgrest.mjs` check also passed on a schema-only export of the live sales project after applying these migrations. It checks communication RLS and left-embedded contact filtering, not every API surface or production state.

From backend-api-routes, `./node_modules/.bin/tsx lib/salesperson/api-isolation.integration.mts` checks real contact/task handlers against the dedicated local exported schema. Authentication contexts are injected; database requests and route code are real.
