# Wolfy Home

The field iOS target now opens Wolfy Home. The former Home grid lives in More,
with Calendar and an explicit Back to More control. Session, campaign creation,
Leads, assignment routing, and profile/Settings retain their existing destinations.

## Data and rollout

Apply `supabase/migrations/20260915150000_wolfy_home.sql` to the field app's
Supabase project before releasing the app. This migration has been tested in an
isolated PostgreSQL runtime; it has not been applied to a hosted project.
Do not push unrelated pending migrations from this checkout.

- Personal targets use `user_profiles.weekly_door_goal` and the new nullable
  `daily_door_goal`. Blank clears a target; positive integers set one.
- `wolfy_save_personal_goals` checks the expected user against the authenticated
  user and derives ownership from the token. A trigger prevents other authenticated
  users from changing personal targets even under broader profile update policies.
- `wolfy_home_metrics` is security-invoker, checks workspace membership, and filters
  activity to the authenticated user and selected workspace.
- Daily/weekly doors use dated session events, deduplicated per session and target;
  the latest undo removes a target. Conversations exclude no-answer/do-not-knock
  outcomes. Leads count field contacts created that day; appointments count meeting
  activities created that day, independently of their scheduled date.
- Day/week boundaries use the device's timezone, with Monday as the first day.
  Historical sessions without timestamped visit events are not guessed from totals.
- XP/streaks are existing personal all-time stats; leaderboard uses the existing
  weekly door leaderboard. Neither is presented as a workspace daily metric.
- Follow-up and appointment reads use strict, paginated remote loading for Home;
  other activity screens retain their existing cache fallback behavior.
- Home uses the existing Wolfy coach endpoint for a short insight, with a deterministic fallback. Ask Wolfy opens a chat sheet; no automatic outreach is performed.
- Unsynced offline events are not included. Unavailable sections have retry states.

## Verification

```
swiftc WolfGrid/Feautures/Home/WolfyHomePolicy.swift scripts/test-wolfy-home.swift -o /tmp/test-wolfy-home
/tmp/test-wolfy-home
PGLITE_MODULE=/path/to/@electric-sql/pglite/dist/index.js node supabase/tests/wolfy_home.mjs
```

Tests cover Monday/Sunday, midnight, DST, goal pace, goal persistence and clearing,
invalid targets, foreign-owner and anonymous rejection, workspace authorization,
event deduplication and undo. The database test creates only an isolated in-memory
database and never connects to a hosted project.

The field simulator build and install/launch were verified. The simulator is signed
out. Authenticated navigation, real-account data comparison, device installation,
and light/dark/Dynamic Type inspection of Home remain release checks.


## Weekly progress redesign (September 15)

Home now follows one hierarchy: greeting, weekly goal ring, weekly funnel, compact
Today row, Wolfy insight and chat input, assigned campaign rows and Campaigns button.
The Today row uses the existing daily doors, conversations, leads and appointment
counts; unavailable values display a dash. It wraps to two columns on narrow
screens or with larger text. The daily dashboard card, separate weekly card,
attention list and extra navigation links have been removed from Home. Goal editing still supports daily and weekly
targets. The existing bottom navigation is unchanged.

The ring shows weekly doors, target, remaining doors, daily requirement through
Sunday, completion percentage and calendar-week pacing. Pace compares with an
even target across completed calendar days; no hourly work schedule is invented.
Progress animates, respects Reduce Motion and gives optional haptics when a new
quarter-goal milestone is crossed, with success feedback on completion. Initial
loads do not trigger milestone haptics. Wolfy celebrates weekly completion.

Funnel values use personal `scope.week` facts from the existing field intelligence
response, even when the chat is switched to team analysis. Talks, leads and
appointments share the same period; sales displays verified weekly revenue and
closed count when sales tracking is enabled. Activity ratios compare period
counts, not matched customer conversion cohorts. Missing data displays a dash,
not zero. No monthly revenue is substituted for weekly revenue.

The smaller red Campaigns button always opens the campaign list. Active campaign
assignments appear as compact clickable rows immediately above it; each row opens
that campaign's existing detail screen. These use CampaignAssignmentsAPI and keep
the existing assignment badge store in sync. Rows include the signed-in user's
assignments and whole-team assignments for the selected workspace, exclude terminal
assignment/campaign states, and refresh on foreground, pull-to-refresh and every
30 seconds while Home is active. Failed refreshes retain the last rows with a retry
message. Account/workspace changes discard Home state; late responses are checked
against the current scope. The old recent-campaign selection and progress query
have been removed from Home.

Ask Wolfy remains an overlay with compact, medium and large native detents, drag
to dismiss and an explicit close control. The chat has suggested questions,
conversation input, loading/retry states and optional expanded coaching context.
The mascot opens the existing illustrated Den separately. Its small vector sprite
reacts to resting, focused, ahead, alert, proud and completed states.

Validation: full Debug simulator build passed after the weekly redesign. Policy
tests passed for week/date/DST boundaries, pacing and milestone crossings. The
actual weekly ring component was compiled into a temporary simulator host and
visually inspected (`art/weekly-home-redesign/weekly-ring.png`). Xcode previews
cover active, completed and no-goal states. Live authenticated Home, AI response,
physical-device haptics and iPhone installation remain unverified. This source
change does not deploy the backend or apply migrations; existing Home and field
intelligence backend requirements above still apply.
