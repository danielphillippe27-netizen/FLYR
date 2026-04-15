# FLYR Demo Mode Implementation Plan

## Recommendation

The best path for FLYR is **not** a fully separate app and **not** hardcoded local mock data as the primary demo experience.

The best path is:

1. Create **real demo workspaces** in Supabase.
2. Seed them with **deterministic, believable data**.
3. Add a lightweight **Demo Mode / Explore Demo** entry point in iOS and web.
4. Make demo accounts **read-only or resettable** so the experience stays polished.

That gives you one source of truth for:

- iPhone walkthroughs
- web dashboard demos
- App Store screenshots
- sales calls
- screen recordings

It also avoids maintaining two products.

---

## Why This Fits The Current Codebase

The current app already leans the right way:

- Workspace state is persisted in [`FLYR/Core/WorkspaceContext.swift`](/Users/danielphillippe/Desktop/FLYR IOS/FLYR/Core/WorkspaceContext.swift)
- Workspace resolution already exists in [`FLYR/Features/Routes/Services/RoutePlansAPI.swift`](/Users/danielphillippe/Desktop/FLYR IOS/FLYR/Features/Routes/Services/RoutePlansAPI.swift)
- Campaign reads are already workspace-aware in [`FLYR/Feautures/Campaigns/CampaignsAPI.swift`](/Users/danielphillippe/Desktop/FLYR IOS/FLYR/Feautures/Campaigns/CampaignsAPI.swift)
- Session reads/writes already support `workspace_id` in [`FLYR/Features/Map/Services/SessionsAPI.swift`](/Users/danielphillippe/Desktop/FLYR IOS/FLYR/Features/Map/Services/SessionsAPI.swift)
- Leads already support workspace scoping in [`FLYR/Features/Leads/Services/FieldLeadsService.swift`](/Users/danielphillippe/Desktop/FLYR IOS/FLYR/Features/Leads/Services/FieldLeadsService.swift) and [`web/src/lib/fieldLeads.ts`](/Users/danielphillippe/Desktop/FLYR IOS/web/src/lib/fieldLeads.ts)
- The web app already exposes leaderboard, stats, leads, and integrations in [`web/src/App.tsx`](/Users/danielphillippe/Desktop/FLYR IOS/web/src/App.tsx)

So the platform already has the core tenancy model needed for a demo tenant.

---

## What To Build

### 1. Demo Tenant Model

Add one or two dedicated workspaces:

- `FLYR Demo Solo`
- `FLYR Demo Team`

Recommended additions:

- `workspaces.is_demo boolean default false`
- `workspaces.demo_persona text null`
- optional `workspaces.demo_reset_at timestamptz`

If you do not want schema churn immediately, you can skip the new columns and just keep fixed demo workspace IDs in config for v1.

### 2. Deterministic Seed Script

Create a repeatable seed script that always writes the same IDs and same relationships.

Use fixed UUIDs for:

- workspace
- users
- campaigns
- sessions
- contacts
- QR codes

Make the script **idempotent**:

- upsert workspace
- upsert users/profiles
- upsert workspace membership
- delete and rebuild child demo records, or upsert them by fixed IDs

Best home for this is a single script such as:

- `scripts/seed_demo_workspace.ts`

or a SQL + script combo:

- `supabase/seed/demo_workspace.sql`
- `scripts/run_demo_seed.sh`

### 3. Demo Entry Point

Add a clear entry point:

- `Explore Demo`
- `View Solo Demo`
- `View Team Demo`

Recommended behavior:

- iOS: demo sign-in or demo workspace switcher after auth
- web: `/demo` route or demo login that lands in a demo workspace

For v1, the fastest version is a dedicated demo account that always resolves to a demo workspace.

### 4. Demo Safety Rules

In demo mode:

- hide destructive actions where possible
- disable account deletion / CRM pushes / external sends
- show a small `Demo Mode` badge
- optionally allow edits, but provide a one-click reset

If you want the demo to feel interactive, allow safe local edits and reset the workspace nightly.

### 5. Reset Strategy

Use one of these:

- nightly reset job
- manual `Reset Demo Data` admin action
- re-seed on every demo deploy

Nightly reset is the best default. It keeps the app alive during demos without long-term drift.

---

## Seeded Data To Include

### Solo Demo

Use one believable agent persona with 3 active campaigns and recent activity.

Suggested stats:

- 1,248 homes reached
- 9 completed sessions
- 18 follow-ups
- 5 appointments
- 36 conversations
- 74 QR scans
- 11.8% conversation rate

Suggested campaigns:

- `Oakridge Spring Flyer Drop`
- `Courtice Downs Door Knock`
- `Listing Alert QR Run`

Suggested map state:

- some untouched homes
- some `delivered`
- some `no_answer`
- some `talked`
- a few `appointment`
- a few `hot_lead`
- visible route/session path

Suggested lead/contact mix:

- hot seller lead
- future seller
- curious neighbor
- appointment booked
- QR-scan-only contact

### Team Demo

Use 5 to 6 agents in one brokerage-style workspace.

Suggested stats:

- 4 territories
- 6 agents
- 4,820 homes reached
- 61 sessions
- 92 conversations
- 31 follow-ups
- 14 appointments

Suggested leaderboard names:

- Ava Chen
- Marcus Reid
- Sofia Patel
- Liam Brooks
- Chloe Martin
- Ethan Walker

Suggested team shape:

- one top closer
- one volume knocker
- one QR-heavy rep
- one newer rep with lower totals

That makes the leaderboard feel real instead of flat.

---

## Tables Worth Seeding First

Start with the smallest set that produces the biggest visual payoff.

Priority 1:

- `workspaces`
- `workspace_members`
- `campaigns`
- `campaign_addresses`
- `address_statuses`
- `sessions`
- `contacts`

Priority 2:

- `qr_codes`
- `qr_code_scans`
- `contact_activities`
- performance report / leaderboard rollup tables or RPC inputs

Priority 3:

- invites
- integrations
- share cards
- route plans

If a metric can be derived from lower-level activity, prefer seeding the lower-level activity instead of faking summary counters in isolation.

---

## Demo UX Rules

### iOS

The iPhone demo should land fast and feel alive within 10 seconds.

Recommended first-open sequence:

1. Open app
2. Tap `Explore Demo`
3. Land on preloaded home/dashboard
4. Open a campaign that already has color-coded homes
5. Tap into a completed session
6. Open leads/follow-ups

Important:

- preload at least one campaign with buildings/addresses already provisioned
- avoid any empty-state first impression
- avoid forcing campaign creation before value is visible

### Web

The current web app already supports:

- leaderboard
- stats
- leads
- integrations

It does **not** yet appear to have a dedicated campaign coverage map route in [`web/src/App.tsx`](/Users/danielphillippe/Desktop/FLYR IOS/web/src/App.tsx), so the fastest web demo is:

1. Use seeded leaderboard/stats/leads immediately
2. Add a dedicated read-only demo dashboard page after that

If you want the strongest brokerage presentation, build a `/demo` dashboard that combines:

- KPI cards
- leaderboard
- territory progress
- recent sessions
- follow-up pipeline
- QR activity

---

## Best Technical Approach

### Phase 1: Seeded Demo Workspace

Build this first.

- one demo login
- one demo workspace
- one seed script
- existing app surfaces show non-empty data

This gets you usable demos fastest.

### Phase 2: Demo Mode Flag

Then add app behavior on top:

- `Demo Mode` badge
- hide destructive actions
- special onboarding bypass
- switch between Solo and Team demo personas

### Phase 3: Public Demo Dashboard

Then build a polished web route for sales/marketing:

- read-only
- no auth friction if desired
- curated KPIs
- cleaner narrative than the raw product UI

---

## What To Avoid

- Do not fork the app into a separate demo codebase.
- Do not hardcode fake arrays throughout the UI as the main solution.
- Do not rely on a blank workspace plus manual clicking before a demo.
- Do not seed data that looks mathematically perfect; some unevenness sells realism.
- Do not let demo data mix with production workspaces.

---

## Suggested First Sprint

If the goal is speed, this is the order:

1. Create one `FLYR Demo Team` workspace in Supabase
2. Seed campaigns, addresses, statuses, sessions, contacts, QR scans
3. Create one demo login account
4. Add `Explore Demo` entry in iOS
5. Add a simple web demo login path
6. Add a reset script

That alone is enough for:

- phone demos
- desktop demos
- screenshots
- screen recordings

---

## Final Call

For FLYR, the best way to go about this is:

**Use real backend-backed demo workspaces with seeded data, then layer a simple Demo Mode UX on top.**

That gives you realism, reuse, and the least maintenance burden while keeping both iOS and web aligned.
