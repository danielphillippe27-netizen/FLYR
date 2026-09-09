# User-first data isolation

Personal app endpoints must bind identity to the authenticated auth user ID first,
then the requested workspace. Workspace owner/founder status does not grant access
to another user's personal communications or performance. Explicit administration
and intentionally shared team collaboration are separate surfaces and must never
supply the personal dashboard.

## Plan and verification gates

1. Audit identity resolution, profile/demo defaults and user-switch state. Remove
   email/name-based account selection and test Daniel Hughes versus another Daniel.
2. Count calls, messages, email and successfully sent demos by the actor who sent
   them, independently of contact/lead ownership. Deduplicate canonical and legacy
   copies and exclude failed/draft events. Verify current/prior date ranges.
3. Verify revenue, referrals, subscriptions and historical MRR snapshots resolve
   through the authenticated user's salesperson ID. Check both API and RLS access.
4. Audit personal leads, contacts, pipeline, follow-up, calendar, notifications,
   demo tracking and social inbox routes; block foreign IDs and owner overrides.
5. Audit database policies and data-producing webhooks, including existing mixed
   data. Quarantine uncertain attribution without assigning it to a current user.
6. Run two-user/same-workspace and cross-workspace regression tests, the isolated
   RLS migration test, TypeScript checks and the iOS build. Record release state
   separately; local verification does not establish production protection.

## Current verification status (2026-09-09)

- 86 backend unit/regression tests pass; TypeScript and the final iOS simulator build
  pass. The build is not proof of runtime account-switch or APNs delivery behavior.
- Eighteen isolation migrations execute together locally. Actual PostgREST and
  selected real API handlers pass against a read-only export of the live sales
  schema, using synthetic two-user/new-account fixtures. Auth context is injected
  in the API harness; full sign-in/middleware is not covered by that harness.
- Real database checks cover contacts, tasks, bookings, inbox, outreach/demo counts,
  revenue snapshots, direct foreign-reference writes, RPC privileges, and historical
  CRM link/summary repair. No customer rows or production data were mutated.
- All changes remain local. Release and native runtime verification are outstanding,
  as is completion of the remaining producer/auxiliary access audit. The progress
  entries below are chronological evidence; older counts are superseded here.

## Implementation progress (2026-09-09)

- Strict `salespeople.user_id` identity resolution replaces display-email/name
  selection in the central resolver and personal salesperson tools.
- Demo center no longer forces DANIELPHILLIPPE for other Daniels. Drafts use the
  actual salesperson name. Demo sends are classified on recorded outbound
  communications; performance counts canonical and legacy sender-owned records,
  deduplicates provider IDs, paginates beyond 1,000 rows and excludes draft/failure
  states. Current/prior ranges and MRR snapshots retain personal attribution.
- Personal CRM, tasks, bookings, pipeline and lead-import lookups now apply user
  ownership. New migrations restrict salesperson revenue/demo/settings records and
  personal CRM records. Security-definer merge procedures reject foreign owners
  and spoofed actors. Per-owner company/source uniqueness allows independent data.
- Verification so far: 64 combined backend tests, TypeScript clean, and isolated
  communication, salesperson-metric and CRM RLS tests pass. No production changes.

## Still-open audit items

- Verify native account switching, password recovery, push delivery and inbound call
  behavior with distinct accounts; successful compilation alone does not prove this.
- Finish the producer/auxiliary API inventory and actual-auth regression coverage;
  distinguish explicitly shared team collaboration from personal data surfaces.
- Prepare and review the release independently of unrelated dirty-worktree changes.
  Local tests and migrations are not deployed protection.

### Voicemail follow-through

- Voicemail library reads, activation, deletion and live-call selection now filter
  both workspace and authenticated user. A foreign activation ID is checked before
  changing any active recording.
- Migration 20260909040000 makes the voicemail bucket private and restricts object
  access to the workspace/user path, including when legacy permissive policies exist.
  The API authorizes row and object ownership before issuing 15-minute playback URLs.
- Verification: 65 backend tests pass, TypeScript passes, and the additional isolated
  voicemail RLS/storage test passes for two coworkers and anonymous access.
- All changes remain local. Remaining linked-record, legacy API and combined/live
  schema gates above remain open; this is not a claim that all live data is isolated.

### Linked personal records

- Tasks, bookings and canonical inbox thread GETs now filter embedded contacts/leads
  by owner and workspace while preserving the personal parent row.
- New task references and inbox relinking reject foreign IDs. Managed SMS/email
  validates contact/lead ownership before sending. Task completion and booking
  outcomes validate legacy references before mutations or automation side effects.
- Added reference-validator and task/booking API regression tests, including a
  workspace-owner user attempting foreign links. Backend suite: 67 passing tests;
  TypeScript clean. The embedded PostgREST behavior still needs integration evidence.
- Remaining: other legacy inbox/producers and CRM references, direct database
  relationship integrity, combined migrations and production schema/release checks.

### Inbound contact matching and legacy inbox

- Both Telnyx webhook handlers now resolve legacy/canonical contacts and leads
  through the persisted communication owner (or verified number owner for a new
  record). Unknown recipients remain unmatched. A caller's number no longer
  selects a coworker's contact.
- Legacy inbox contact maps filter user ownership, canonical embeds filter owner,
  and legacy sends no longer bypass lead ownership for owner/admin roles.
  Email enrichment writes filter owner; legacy SMS rejects inaccessible contacts.
- Added same-number/two-user and foreign embedded-contact regression coverage.
  TypeScript passes; 69 backend tests pass. Embedded relations use a modeled left
  join in these tests, so real PostgREST integration remains an open gate.

### Legacy contacts and dialer sessions

- Generic contacts GET always filters user_id, plus the selected workspace, and
  rejects inaccessible explicitly requested workspaces. Added API regression test.
- Session response/next-lead contact and call lookups filter the session user and
  workspace rather than trusting child foreign keys alone.
- New 20260909050000 migration restricts contacts, field_leads, dialer_sessions and
  session child records. Its isolated test verifies same-workspace read/delete
  separation and rejects foreign-contact writes. An ambiguous SQL reference caught
  by the test was qualified and the test rerun successfully.
- Backend suite now has 70 passing tests; TypeScript passes. No live changes.
- Still open: generic contact linked-address validation, session claiming RPC audit,
  remaining producers/relationship integrity, metrics placeholders, full combined
  migration and PostgREST/live schema integration, and coordinated release.

### Direct dialer claiming

- Located the actual SECURITY DEFINER claim function in the sibling system-tests
  schema snapshot. It trusted p_user_id and granted anonymous execution.
- Migration 20260909060000 validates authenticated identity (or service-role calls),
  validates session owner/workspace, and claims only contacts owned by that user in
  that workspace. Anonymous execute privileges are revoked.
- New direct-RPC database test passes: spoofed users, foreign sessions, foreign
  contacts and anonymous calls are rejected; an own-user claim succeeds.
- Docker was stopped when checked. Started Docker Desktop to enable the stronger
  local Supabase/PostgREST verification gate; readiness is not yet verified.

### Integration preparation and contact creation

- Prepared an isolated Supabase stack at /tmp/wolfgrid-personal-isolation-stack
  (ports 56320–56329) from the sibling schema snapshot, required additive schemas
  and all six personal-isolation migrations. It has not started or passed.
- Docker Desktop/VM processes are live, but Docker API info/list/ping returned 500
  while the engine remained starting. Integration is temporarily unavailable;
  independent implementation work remains possible.
- Contact creation now verifies linked address campaign ownership, and explicit
  campaign/farm owner plus workspace, before saving or pushing to a CRM.
- 71 backend tests pass, including foreign campaign/farm rejection before side
  effects; TypeScript passes. Real PostgREST joins remain to be verified.

### Personal demo performance

- Replaced performance response demoVideo/link-open placeholders with personally
  attributed, date-bounded demo/click queries. Demo-event reads paginate; session
  watch time uses per-session maxima rather than summing progress snapshots.
- Added current/prior link-open comparisons. Missing salesperson identity yields
  empty metrics; query failures fail explicitly rather than showing fake zeros.
- Revenue lookup failure no longer falls through to saving a zero-MRR snapshot.
- 73 backend tests pass, including >1000 personal demo events, foreign-user and
  date-boundary exclusion, and watch-time aggregation. TypeScript checked.
- Docker socket ping still timed out after five seconds. Integration remains open;
  this does not prevent remaining independent ownership audits.

### Shared communication writer and database references

- appendCommunication now validates contact/lead owner and workspace for every
  producer. Unverified links are detached while retaining the incoming event;
  foreign lead automation and activity writes are prevented. Outbound managed
  sends still reject invalid references before sending.
- New 20260909070000 migration detaches invalid historical contact/lead links from
  events/threads, preserving message bodies, and adds triggers rejecting future
  owner mismatches even on privileged writes. Isolated migration test passes.
- Updated same-contact regression verifies that a different user and an unowned
  event cannot retain that contact reference. All 73 backend tests and TypeScript
  pass. Added migration to the prepared isolated integration stack.

### CRM company links and recording leads

- Shared reference validation now supports companies. CRM contact create/update
  rejects foreign company IDs; CRM contact/company embeds filter both user and
  workspace on child relations. Added create/update rejection regression.
- Recording library and per-lead recording lookup now require assigned_user_id
  even for owner/admin roles or matching legacy assigned_salesperson_id. Call
  ownership remains required too. Added foreign-lead owner-bypass regression.
- 75 backend tests pass and TypeScript passes. Database company-link integrity and
  PostgREST join checks remain open alongside previously recorded release gates.

### Email ingestion and delivery attribution

- iCloud and Resend inbound contact/lead lookups now filter mailbox owner. Inbound
  provider IDs are mailbox-scoped; Resend processes all addressed managed
  mailboxes rather than only the first. Actor-scoped legacy-ID checks prevent
  replay duplicates while allowing another user's copy of the same message.
- Resend delivery/bounce updates resolve the original outbound event and owner,
  preserve existing metadata, and restrict preference changes to that event's
  personally owned contact. Removed global recipient-email contact lookup.
- Added two-mailbox/same-message regression. 76 backend tests and TypeScript pass;
  deployment and combined/live integration gates remain outstanding.

### Combined migration evidence

- Added personal-isolation-combined.mjs: all seven migrations execute in release
  order in one isolated PostgreSQL database with permissive legacy policies still
  present. Two-user assertions cover communications, CRM, metrics, private storage,
  legacy contacts/sessions and valid lead claims under all policies together.
- Combined test passes. README records commands, focused tests and scope limits.
  This closes the simplified-schema migration-interaction check, but does not
  replace full deployed-schema or PostgREST integration. Those remain outstanding.

### Independent personal imports

- Removed CSV import's cross-rep phone collision query and its helper. The same
  prospect can exist independently in two users' personal datasets; duplicate
  filtering still checks the importing user's own records. Existing response field
  claimedByOtherRep stays zero for client compatibility without querying coworkers.
- Added CSV API regression: coworker's matching prospect imports successfully,
  then a repeated import for the same user is skipped. Backend checks rerun.
- No native Postgres/PostGIS/PostgREST installation was found under Homebrew;
  Docker-independent full integration still needs a runnable database environment.

### Device account switching

- Push-token registration now disables other users' registration for the same
  device/environment before registering the current user; DELETE unregisters only
  the authenticated user's token. Added switch/logout API regression.
- iOS registration cache includes user identity, cleans up stale in-flight uploads,
  retries registration after a user switch, and unregisters before sign-out.
- Migration 20260909080000 disables ambiguous historical registrations and permits
  only one active user per token/platform/environment. Focused database test and
  updated eight-migration combined test pass. 78 backend tests pass.
- iOS simulator build is running (exec session 15152, log
  /tmp/personal-communications-ios-build.log); do not claim its result yet.
- Background automation audit found remaining owner/reference checks needed in
  triggerSalesAutomations and cron execution, including assignment steps.

### Background automation ownership

- The iOS account-switch/sign-out build completed successfully (BUILD SUCCEEDED).
- Automation creation/editing/listing is personal to created_by_user_id. Triggering
  validates lead/contact owner and selects only that owner's definitions.
- Cron execution validates enrollment workspace/owner, personal references and
  definition creator before side effects; reply checks are actor-scoped. It rejects
  cross-user assignment and foreign nested automation definitions.
- Migration 20260909090000 adds restrictive ownership policies to definitions,
  versions, enrollments and executions; claim RPC execution is service-role-only.
- Combined nine-migration test passes, including per-user automation rows and
  denied authenticated scheduler-claim execution. 79 backend tests and TypeScript
  pass. Live/full-schema integration and remaining gates still open.

### Sales screen identity lifecycle

- SalespersonMainTabView now keys all tab content by auth-user/workspace, resetting
  nested view state across identity changes rather than only resetting Inbox.
- Shared sales API requests bypass cached responses and reject mismatched auth
  tokens plus responses arriving after user/workspace changes, including retries.
- Simulator build for these changes is running in exec session 40717 with log
  /tmp/personal-communications-ios-build.log. Earlier build success does not cover
  this latest change until the current result is checked. Runtime switching test
  remains to be performed.
- Public booking contact/lead lookup now scopes to the assigned meeting owner,
  allowing each user an independent prospect record for the same guest email.
- Booking-links API still needs personal-owner/member checks on GET/PATCH and
  validation of proposed round-robin members before creation; explicitly shared
  team links must remain distinguishable from personal links.

### Booking-link API and client build correction

- Booking-link GET excludes coworkers' personal links; team links require member
  participation or workspace administration. PATCH rejects foreign personal links
  even for admins; team edits remain admin-only. Creation validates every proposed
  member belongs to the workspace before writes. Availability defaults are created
  only for the current user. Added API rejection regression.
- Latest iOS build failed on four missing awaits for MainActor workspace reads in
  the new API guard. Corrected them; replacement build is running (session 4990).
- Prior TypeScript check finished clean. Updated backend tests and TypeScript run
  are in session 14777; outputs /tmp/user-data-isolation-tests.log and
  /tmp/user-data-isolation-tsc.log. Do not assume completion until inspected.
- Direct database booking-link policies still require the same personal/team
  boundary; real account-switching and PostgREST integration remain open.

### Booking database access and final client build result

- Corrected account-switch guard build completed successfully; latest backend
  checks show 80 tests passed and TypeScript clean.
- Migration 20260909100000 restricts personal booking links and availability to
  their owner, separates team-member reads from administrator edits, and rejects
  adding another user to a personal booking link. Uses an auth-scoped boolean
  predicate to avoid recursive link/member RLS. Focused test passes.
- Combined test now applies all ten migrations and passes. Added migration to
  prepared integration stack. Real PostgREST/deployed-schema verification and
  runtime user-switch verification remain outstanding.

### Full-stack integration resumed

- Docker recovered: bounded socket ping returned OK. Started the prepared isolated
  stack via supabase start (exec session 90861; log
  /tmp/personal-isolation-stack-start.log). It is pulling images; readiness and
  migration success are not established yet. Do not restart it based on silence.
- Added personal-postgrest.mjs for the dedicated local ports 56321/56322. It uses
  synthetic users/workspace and validates real authenticated RLS plus service-role
  embedded-contact filtering on deliberately modeled historical bad linkage.
  It refuses a nonlocal or differently ported API and cleans its exact fixtures.
- After startup succeeds, save `supabase status --workdir
  /tmp/wolfgrid-personal-isolation-stack -o json` to
  /tmp/personal-isolation-stack-status.json (do not print credentials), then run
  the integration script. This script has been prepared but not executed.

### Live schema metadata verification

- Confirmed API env hosts and CLI project ref both target yxxuazvosddtajwitlxu.
  Read-only live OpenAPI metadata saved to /tmp/personal-isolation-live-openapi.json.
  No customer rows were read or live changes made.
- Live sales_contacts has owner_user_id but no user_id. Fixed migration 0300 to
  conditionally backfill only where the legacy column exists; added current-schema
  regression. It passes along with the updated combined test.
- user_push_tokens is not exposed by live metadata (absence versus missing grants
  not yet established). Migration 0800 now creates it if absent, revokes direct
  client access, and grants the service role access for the authenticated API.
  Existing-table push regression and combined test pass.
- Live social tables use social_workspace_id, not workspace_id; performance's
  social-count paths must be reconciled before claiming complete metrics.
- Read-only CLI schema dump is running (session 31912), currently pulling its
  image; output /tmp/personal-isolation-live-public-schema.sql, log
  /tmp/personal-isolation-schema-dump.log. Stack start 90861 is still live.

### Real PostgREST verification

- Original full schema snapshot plus all ten migrations applied successfully in
  the dedicated local Supabase stack. personal-postgrest.mjs passed real HTTP/RLS
  checks for both users and service-role embedded contact filters.
- Fresh live sales schema export finished at
  /tmp/personal-isolation-live-public-schema.sql (read-only export; no live data).
- Replaced only the dedicated local stack's baseline with that live schema and
  started `supabase db reset --local` there (session 85441; log
  /tmp/personal-isolation-live-schema-reset.log). Prior baseline copies preserved
  outside migrations in /tmp/personal-isolation-original-baseline.
- Next: inspect reset result and rerun personal-postgrest.mjs against this schema.
  Do not claim the live-schema variant passed until checked.
- Personal DM metrics now use user ownership and real social schema; outbound
  message replies count, comment replies do not. 81 backend tests/TypeScript pass.

### Exported live-schema integration result

- Reset from the exported live sales schema completed successfully. Applied the
  additional 20260909110000 migration locally, then personal-postgrest.mjs passed
  against this schema: both users isolated, including workspace owner; service-role
  embeds remove foreign contact details. No production mutations.
- Migration 1100 protects private merge snapshots, requested research/batches,
  booking reminders, communication preferences and contact-campaign links. These
  still had workspace-wide live policies. Eleven-migration combined test passes
  with both users' auxiliary rows included.
- Current verified: 81 backend tests, TypeScript clean, latest iOS build succeeds,
  combined 11-migration fixture and actual PostgREST checks on both historical and
  current exported schemas.
- Still not verified: complete runtime account switching, full two-user API flow
  for every personal surface, final producer/auxiliary read audit, and production
  release. Do not treat schema compatibility as deployed protection.

### Actual API handlers against exported schema

- Added backend lib/salesperson/api-isolation.integration.mts. It executes actual
  CRM contacts, legacy contacts and tasks handlers with the local service-role
  client, synthetic two-user/new-user fixtures and mocked auth contexts. It checks
  per-user lists and denial of a foreign task update even with owner context.
- It found a missing sales_leads→sales_contacts FK in the live schema, causing CRM
  embed reads to fail. Migration 20260909120000 adds the missing relationship NOT
  VALID, preserving old orphan rows while enforcing new links. Applied locally.
- It also found legacy contacts selecting absent name/company columns and masking
  column errors as missing tables. Corrected selected fields and error detection.
- API handler integration now passes. Full backend/TypeScript and updated combined
  12-migration checks running in session 89697; inspect before claiming results.
- Remaining API integration should cover bookings, inbox, revenue/demo queries and
  producer behaviors; this test does not simulate complete authentication/UI.

### Extended real API and metric verification

- Actual bookings and inbox handlers now pass the two-user/new-account integration,
  including denied foreign updates with workspace-owner auth context.
- Added actual outreach queries and messenger identity resolution to that test.
  Removed messenger's email/workspace fallback: identity now requires the user's
  account ID and workspace. Notification profile lookup also uses account IDs.
- Outreach integration exposed a missing contact_activities → contacts FK in the
  live sales schema. Migration 20260909130000 adds the relationship NOT VALID to
  preserve historical orphans; applied only to the dedicated local stack.
- Actual outreach totals pass for both coworkers and an empty new account. A new
  user cannot impersonate an existing salesperson with matching email or missing
  email. Thirteen migrations pass together in the combined database fixture.
- TypeScript passed after the messenger change. Production remains unchanged;
  remaining gates include native account-switch verification, remaining producer/
  auxiliary audit, full revenue flow verification, and coordinated release.

### Revenue ownership verification

- Revenue loading and snapshot writes now validate salesperson_id/user_id against
  the salespeople account mapping. Performance, cron and billing sync callers pass
  the explicit owner. Mismatched identity fails before revenue access or writes.
- Stripe subscription lookup failure now rejects the total; missing configuration
  with existing subscriptions also rejects instead of saving a false zero. Empty
  referral sets still correctly yield zero without a provider request.
- Actual local database integration checks separate snapshots for both coworkers,
  no snapshot for a new user, denied mismatched revenue read/write, and unchanged
  victim snapshot after an attempted overwrite. No live Stripe calls made.
- 82 backend tests pass, including mocked provider-failure coverage. Full TypeScript
  verification is running in session 27537. Native recovery-session signout was
  inspected: it bypasses the ordinary push unregister path and restores a prior
  session; review its device-registration lifecycle before changing this flow.

### Push lifecycle follow-up

- Signout now clears the visible account/workspace before awaiting push cleanup,
  preventing a concurrent token upload from treating the departing user as active.
- Push upload requires the visible user to match Supabase and is suppressed during
  password recovery. Recovery entry/exit unregisters first; failure restores the
  previous session; registration resumes after restoration.
- Authorized APNs registration resumes after signout/restore even when no token is
  cached. In-flight registration retries after generation/account/token changes;
  guards are rechecked after notification-settings awaits.
- iOS build session 64514 is still running in /tmp/personal-communications-ios-build.log.
  The push source received two small race guards while that build ran; run a final
  incremental build after it completes to ensure latest sources were compiled.
- Backend TypeScript session 27537 completed successfully. Native APNs account
  switch delivery still requires runtime device verification, beyond build checks.

### Security-definer function audit

- Live schema exposed create_sales_booking_hold to direct clients and exposed
  claim_due_company_research_jobs to anonymous/authenticated callers. Both bypassed
  normal API ownership/validation. Migration 20260909140000 limits these and all
  scheduler claim functions to service_role, and removes anonymous/PUBLIC execution
  of ensure_social_workspace. Existing authenticated social identity check remains.
- Applied only to dedicated localhost database. Integration now asserts actual
  function privileges for anon, authenticated and service_role; two-user API/metric
  tests pass. All fourteen migrations pass together in the database fixture.
- iOS build 64514 remains active and has advanced to x86_64 compilation. Do not
  restart it; poll its existing handle. A final incremental build is still needed
  afterward because the push source was edited while the build was running.

### Final native build and inbound metrics

- Build 64514 completed successfully; final incremental build 28816 also succeeded
  with the latest push lifecycle guards (/tmp/personal-communications-ios-final-build.log).
- Replaced performance inboundMessages:0 with personally owned received SMS totals.
  Canonical/legacy copies deduplicate by provider message identity; unowned or foreign
  messages cannot contribute. Date filtering uses the same exclusive period end.
- Actual exported-schema API integration passes including canonical + legacy inbound
  duplicates, both coworkers and an empty new account. 83 backend tests pass.
- TypeScript session 99306 is running; inspect completion before claiming it passed.
- Remaining completion gates include native runtime account-switch/APNs verification,
  final service-role producer/read audit and direct database reference integrity
  outside communication rows, plus coordinated release (no production changes).

### CRM database references and summary isolation

- Migration 20260909150000 validates owner/workspace for contact, lead and company
  links on CRM contacts, leads, tasks and bookings, including service-role writes.
- Replaced sales_pro_refresh_next_action's unscoped task aggregation: it refreshes
  old/new references only for matching owner/workspace and considers only that
  owner's tasks. Historical foreign task links cannot supply summary titles/dates.
- Actual local integration proves rejection of foreign task/contact and booking/lead
  links; a simulated historical bad task link is ignored when refreshing the victim
  lead. Fixture cleanup now deletes tasks/bookings/leads before workspace stages;
  the failed run's synthetic fixtures were explicitly cleaned from localhost.
- Integration and combined fifteen-migration test pass. Existing stale denormalized
  summaries and historical CRM links still need migration reconciliation; the new
  trigger protects future refreshes but does not by itself repair stored summaries.
- TypeScript check 99306 completed successfully. Latest iOS build remains green.

### Historical CRM reconciliation

- Migration 20260909160000 detaches invalid CRM references after writing only link
  metadata to a service-role-only quarantine table. Records/bodies are preserved.
  Validation triggers are suspended under table locks inside the transaction and
  restored before commit. Only summaries affected by detached task links refresh.
- Actual local integration simulates a contaminated summary and bad task link,
  applies the repair, then verifies the correct personal summary, preserved source
  task, unchanged unrelated manual follow-up, and inaccessible quarantine audit.
- Actual integration and combined sixteen-migration test pass. Production unchanged.

### Real authentication verification

- Explicit invalid/malformed bearer authentication no longer falls back to a
  potentially different browser-cookie account. Valid bearer and cookie-only web
  authentication retain their own paths. Regression tests cover both.
- Added auth-api-isolation.integration.mts: creates three local test users without
  email delivery, signs in through GoTrue, then executes the actual request-user,
  workspace context and CRM handler. No injected user identity in this harness.
- Two coworkers and a new user see only personal contacts; inaccessible workspace
  returns 403; invalid bearer returns 401. Test users/workspace cleaned afterward.
  Next cookie adapter is stubbed empty; browser cookie sessions and native runtime
  account switching remain outside this integration's scope.
- 85 backend tests pass. TypeScript verification running in session 37967.

### Timeline and calendar audit

- CRM timeline now validates contact/lead ownership before querying and before
  attaching a note. Campaign data is fetched only for the user's campaigns in the
  workspace, without assuming an embedded FK exists in the standalone sales schema.
- Actual handler integration proves a foreign campaign attached to an owned contact
  is excluded; foreign-contact timeline reads and note writes return 404.
- Migration 20260909170000 adds own-user calendar access plus a restrictive boundary.
  The exported sales schema enabled calendar RLS without an access policy; the new
  policy allows personal native calendar reads while preventing broader old policies
  from exposing coworkers' events.
- Actual GoTrue/RLS integration verifies each coworker's calendar, an empty new-user
  calendar, and zero rows updated for foreign IDs. Fixtures are removed afterward.
- Rechecking combined 17 migrations and TypeScript after these changes. Public
  booking calendar-reference writes and meeting contact validation remain to audit.

### Booking and meeting calendar references

- Public cancellation/reschedule validates calendar event owner + workspace before
  mutations or Zoom operations. Calendar queries and updates carry those filters;
  cancellation checks its booking update and reminder deletion is workspace-scoped.
- Meeting creation validates an optional legacy/CRM contact belongs to the current
  user/workspace before accessing Zoom or sending invitations.
- Actual local API integration proves a foreign event link returns 409 for cancel
  and reschedule with no victim changes, and own-event cancellation succeeds. A
  foreign meeting contact returns 404. No Zoom/provider requests or messages sent.
- TypeScript check 8513 passed. Full backend regression command passed after changes.
  No native source changes since the final successful iOS build; production unchanged.

### Demo and signup producer attribution

- Demo-link pipeline lookup now resolves the link's salesperson to an account in
  the same workspace and filters leads by assigned_user_id. Signup email matching
  also requires this account; legacy salesperson/pipeline_owner fields cannot widen it.
- Pipeline mutations include owner/workspace filters. Demo/signup activity rows now
  carry the lead owner's actor_user_id rather than null, making personal timelines
  consistent with the matching owner.
- Actual local test creates two users' leads with the same legacy contact/email and
  misleading legacy salesperson fields. Demo-open and signup changes affect only
  the correct owner's lead; demo activity is stamped with that account. Passed.
- TypeScript 75015 passed; full backend tests passed. No native source changes.
- Simulator inventory: no booted simulator. Config reads Supabase/API URLs from
  built Info.plist; native verification would need an isolated configured app copy,
  local backend, and test accounts. None launched or changed in this turn.

### Explicit user-specific lists requirement

- Removed smart-list import owner/admin bypass and legacy salesperson OR condition;
  both saved lists and their lead contents now filter by the authenticated owner.
  Changed the API's shared-workspace description to Your list.
- List research requires the list creator and filters lead membership by that same
  user. Local lists use workspace+user storage keys; legacy cache migration includes
  only explicitly owned rows, never old anonymous/local-owner rows. Creation stamps
  the actual session user; reads/deletes cannot access another account's cache.
- Migration 20260909180000 enables personal list access with a restrictive creator
  boundary even when older workspace policies exist.
- Actual API tests prove owner/member/new-user list separation; real auth/RLS tests
  prove private list reads and denied foreign deletes. Local-cache switch/delete
  regression passes. 86 backend tests, TypeScript and all 18 migrations pass locally.
- Native verification setup remains unfinished: dedicated simulator
  1C16527A-1D50-4DA6-AC79-70E5ECB82C74, copied app/config/test users under
  /tmp/personal-isolation-native. Original copy signed in but lost keychain sessions;
  experimental local entitlements caused a launch rejection. No production app or
  accounts changed. Local Next backend session 55768 was running on 56330; inspect
  its handle before reuse. The browser startup check passed and its session closed.
