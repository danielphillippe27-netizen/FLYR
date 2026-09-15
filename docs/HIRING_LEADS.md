# Hiring Leads — WolfGrid Sales

## Product

Sales → Leads → Hiring Leads shows employer hiring signals in Canada and the USA.
The connected-search target is door-to-door, canvasser/canvassing, D2D, field sales,
and outside sales. Country, discovery window, text, and personal review filters
are available. Saved/contacted/dismissed decisions belong to the signed-in user.

Job details preserve company website, original posting URL/date, source listing,
salary when supplied, closure date, and attributed hiring-team names, roles and
profile links. Missing email and phone values remain empty. Company enrichment
is not proof that a named person has a particular email or phone.

## TheirStack connection

Saved search: https://app.theirstack.com/workspace/203494/search/jobs/66398

Receiver: `POST /api/webhooks/hiring/theirstack`

- `THEIRSTACK_WEBHOOK_SECRET`: server-only random secret (at least 16 characters).
- `HIRING_THEIRSTACK_ENABLED=true`: display the connected source after delivery is configured.
- `X-TheirStack-Signature-256` authenticates the exact request bytes using HMAC-SHA256.
- Supports `job.new` and `job.closed`. Provider job IDs deduplicate deliveries.
- Closure tombstones and transaction locks preserve closure-before-arrival events.
- Body limit 1 MiB. Operational failures return 500 for provider retry.
- Add `?validate_only=1` only for signed endpoint testing: no database writes.
- No provider API key is required by the receiving endpoint.

Create a provider webhook for the saved search, new postings from activation time,
not the full 90-day history. If using a daily event cap, tell the operator explicitly:
TheirStack drops events above that cap; it does not queue them for tomorrow.
Check trial/paid balances and expected volume before activation. API/webhook
credits are separate from website company-reveal credits. Never repeatedly fetch
historical API pages merely to check whether anything changed.

TheirStack coverage is not exhaustive across all job boards. Its source URL is
provenance supplied by the provider, not an independently verified guarantee of
coverage. Hiring-team profiles are optional. The integration does not initiate
outreach or infer contact details.

## Optional Adzuna fallback

`HIRING_ADZUNA_ENABLED=true`, `ADZUNA_APP_ID`, and `ADZUNA_APP_KEY` enable the older
collector when TheirStack is disabled. Daily 11:00 UTC cron scans up to 10 pages
of 50 records per country over a three-day overlap, all industries. Runs report
partial results and rejected records rather than claiming exhaustive coverage.
With TheirStack enabled, the cron reads delivery summary only; source webhooks
provide new records continuously.

## Database / authorization

Migration: `20260915110000_hiring_leads.sql`.

All data access goes through the existing authenticated active-salesperson check.
RLS is enabled and public/anon/authenticated direct table and RPC access is revoked.
The service role performs ingestion and user-scoped review mutations. The API derives
review ownership from the authenticated session; request bodies cannot choose an owner.

Postings are grouped by normalized country/company/title/location. Importing an
existing provider ID does not change its first-seen date or make it a fresh signal.
A genuinely new provider posting can resurface an existing signal without resetting
personal review status. Paging uses a stable discovery timestamp and UUID order.

## Validation

- `npm run test:hiring`: parser, deduplication, collector outcomes, cron authentication,
  official HMAC fixture, unsigned/malformed events, and signed validation-only requests.
- `tsc --noEmit --incremental false` in the backend.
- `HIRING_TEST_PGLITE_MODULE=/absolute/path/to/pglite/dist/index.js node supabase/tests/hiring_leads.mjs`
  uses a disposable embedded PostgreSQL database; checks migration, private reviews,
  grants, pagination, duplicate ingestion, closure ordering and rollback.
- Signed iOS build uses scheme `WolfGrid Sales`; if the current Swift compiler crashes
  in batched compilation, pass `SWIFT_ENABLE_BATCH_MODE=NO`, `ARCHS=arm64`,
  `ONLY_ACTIVE_ARCH=YES` and an isolated derived-data directory.

## Release status — 2026-09-15

Production migration applied and recorded on `yxxuazvosddtajwitlxu`; RLS/grants verified.
Backend deployment `dpl_5nZaRHvyHq1xxVNszKYpLRQbouFZ` is live at
https://sales.wolfgrid.app. Unauthorized feed/cron requests return 401; unsigned
webhooks return 403; signed validation-only CA/USA requests return 200 without writes.
Ten backend tests, TypeScript, PostgreSQL migration/behavior checks passed.
Signed iOS device build passed. Installed and launched on Daniel’s iPhone 16 Pro
(bundle `com.danielphillippe.wolfgrid.sales`, process 7478). The transient developer
disk-image mount issue cleared on the install attempt. Automatic source activation
is now active as described below. Authenticated in-app interaction has not been visually verified.
Two already-revealed Leaf Home jobs were manually seeded from TheirStack pages:
Ontario `842740793` and Kansas `842807932`, with company website and posting links.
Neither supplied a hiring contact. No API credits were used. Signed manual replay
of the real Ontario job through the production receiver returned 200 without duplication.
The actual Swift models also decoded the SQL enrichment contract successfully. No paid source subscription has been purchased. The user supplied the setup API key;
automatic trial delivery is now configured.


## Source activation — 2026-09-15

- TheirStack webhook `6130` is active, uses the saved search `66398`, signs deliveries,
  and scans hourly from activation (`2026-09-15T13:58:17Z`). It subscribes to `job_new`.
- Trial limit is **50 new postings per UTC day**, all postings rather than one per company.
  Extra matches are dropped, not queued. Volume estimate: 364 new postings/day.
- `HIRING_THEIRSTACK_ENABLED=true` and `HIRING_THEIRSTACK_NOTICE` expose the trial
  limit in the app's coverage details. Exhausted source credits stop further delivery.
- The provider's own signed webhook test returned 200 using validation-only mode.
- Initial API retrieval fetched 5 CA and 5 US jobs from the last 7 days with
  `property_exists_and: ["hiring_team"]`. All 10 records validated and imported via
  the live receiver. The ongoing webhook keeps all matching jobs, including those
  without hiring contacts; the initial contact filter does not narrow daily coverage.
- Trial API credits: 10 used, 190 remaining at verification. The 2 original manual
  records remain. Initial imports are distinct from the first scheduled webhook batch.
- The provider reported zero scheduled delivery events at activation verification;
  the first hourly batch remains to be observed. API import and signed provider test
  both passed. No automatic top-up or paid subscription was enabled.
- The setup API token is not committed or needed in the receiving backend. The
  independent webhook signing secret is stored as a sensitive production variable.

Activation deployment `dpl_CydSSgpsMnUPJZ4ptuCH35pDLjJJ` is live at sales.wolfgrid.app;
final signed validation-only check returned 200. The temporary setup API token was removed.
