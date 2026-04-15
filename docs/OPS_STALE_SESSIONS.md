# Stale open sessions (operations)

## App behavior

- If an **active** session is restored from Supabase and is older than **6 hours**, the app shows **Resume session** or **End & save session** before live GPS resumes.
- Implementation: [`FLYR/Features/Map/SessionManager.swift`](../FLYR/Features/Map/SessionManager.swift), [`FLYR/Features/Map/Views/StaleActiveSessionResolutionView.swift`](../FLYR/Features/Map/Views/StaleActiveSessionResolutionView.swift), [`FLYR/MainTabView.swift`](../FLYR/MainTabView.swift).

## Server safety net

Migration: [`supabase/migrations/20260415120000_close_stale_open_sessions.sql`](../supabase/migrations/20260415120000_close_stale_open_sessions.sql)

Function: `public.close_stale_open_sessions(p_idle_hours integer default 8, p_max_open_hours integer default 48) returns integer`

- Closes rows in `public.sessions` where `end_time IS NULL` and either:
  - `updated_at` is older than `p_idle_hours`, or
  - `start_time` is older than `p_max_open_hours`.
- **Execute as `service_role`** (e.g. scheduled job). Not granted to `authenticated` clients.

Example (SQL editor):

```sql
SELECT public.close_stale_open_sessions(8, 48);
```

Optional: schedule with **pg_cron** in the Supabase project to run hourly/daily.

## After bulk closes

Normally each closed row fires the existing session → `user_stats` / `leaderboard_rollups` trigger. If you ever backfill or repair inconsistently, you can rebuild rollups:

```sql
SELECT public.rebuild_leaderboard_rollups();
```

Run only during maintenance; it truncates and rebuilds `leaderboard_rollups`.

## Challenge rolling leaderboard

Migration: [`supabase/migrations/20260415121000_challenge_rolling_leaderboard_ended_sessions_only.sql`](../supabase/migrations/20260415121000_challenge_rolling_leaderboard_ended_sessions_only.sql)

RPCs `get_challenge_rolling_leaderboard` / `count_challenge_rolling_participants` score **ended sessions only** (last 30 days), aligned with finalized session semantics.
