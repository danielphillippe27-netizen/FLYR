# iOS First 30 Days Challenge Wiring

This README explains how to wire the new challenge badge, streak, and share-card system into the iOS app.

The goal is to hook iOS into the same backend used by web:

- Rolling First 30 Days leaderboard
- Live badges
- Current streak display
- Server-generated post-session share cards
- Weekly accountability cards

## Backend Prerequisites

Make sure these backend pieces are deployed before wiring iOS:

- Supabase migration:
  - `supabase/migrations/20260408233000_challenge_badges_streaks_share_cards.sql`
- Edge Functions:
  - `supabase/functions/evaluate-badges`
  - `supabase/functions/challenge-engagement-cron`
- Web API routes:
  - `app/api/share-card/route.ts`
  - `app/api/accountability-card/route.ts`
  - `app/api/accountability-card/latest/route.ts`
  - `app/api/accountability-card/share/route.ts`

The iOS app expects:

- `get_challenge_rolling_leaderboard(...)` to return:
  - `user_id`
  - `display_name`
  - `score`
  - `rank`
  - `active_badges`
  - `current_streak`
  - `accountability_posted`
  - `latest_session_id`
- `count_challenge_rolling_participants(...)` to exist
- Edge Function `evaluate-badges` to accept:
  - `{ "user_id": "<uuid>", "challenge_id": "<optional uuid>" }`
- Public share-card endpoint:
  - `GET /api/share-card?user_id=...&session_id=...&challenge_id=...`

## iOS Areas To Wire

There are 3 iOS surfaces involved:

1. Challenge home
2. Session save / session end
3. Share-card presentation

The files below are the main integration points.

## 1. Challenge Home

Use the existing challenge module instead of the generic leaderboard module.

Relevant files:

- `FLYR/Features/Challenges/Models/Challenge.swift`
- `FLYR/Features/Challenges/Services/ChallengeService.swift`
- `FLYR/Features/Challenges/ViewModels/ChallengesViewModel.swift`
- `FLYR/Features/Challenges/Views/ChallengesHomeView.swift`

### What to add

In `Challenge.swift` add:

- `ChallengeBadgeID`
- `RollingChallengeLeaderboardEntry`
- `RollingChallengeLeaderboardSnapshot`

These should model:

- active badge IDs
- current streak
- posted indicator
- latest session ID

### What to fetch

In `ChallengeService.swift` add a method that calls:

- `count_challenge_rolling_participants`
- `get_challenge_rolling_leaderboard`

Recommended method:

- `fetchFirst30RollingLeaderboard(limit: Int = 50)`

It should return:

- active challenge ID
- title
- participant count
- leaderboard rows

### Where to store it

In `ChallengesViewModel.swift` add:

- `@Published private(set) var rollingLeaderboard: RollingChallengeLeaderboardSnapshot?`

Load it alongside:

- stats
- my challenges
- searchable challenges

### How to render it

In `ChallengesHomeView.swift`, render the live leaderboard under the main 30 Day hero card.

Recommended row contents:

- rank
- display name
- active badge emoji inline
- `🔥 {streak}` pill when `currentStreak >= 2`
- `📤 Posted` pill when `accountabilityPosted == true`
- homes score on the right

Important:

- Keep this on the challenge screen, not the generic Stats leaderboard
- The challenge leaderboard is a different data source than `get_leaderboard`

## 2. Badge Evaluation After Session Save

Relevant files:

- `FLYR/Features/Map/SessionManager.swift`
- `FLYR/Features/Map/Services/SessionsAPI.swift`

Badge evaluation should run after a successful session save, not before.

### Building-session flow

For building sessions, hook badge evaluation after:

- `persistEndedBuildingSession(...)`

Recommended call:

- `await ChallengeService.shared.evaluateBadges(for: userId)`

Also warm the share card right away:

- `await ChallengeService.shared.warmShareCard(userID: userId, sessionID: sid)`

### Non-building-session flow

For the plain insert flow in `saveToSupabase()`:

- change the insert to `.select("id").single()` so you get the new `session.id`
- then call:
  - `evaluateBadges(for:)`
  - `warmShareCard(userID:sessionID:)`

Why:

- badges depend on the just-saved session being queryable
- the share UI needs the real server-generated image, keyed by `session_id`

## 3. Share Card Presentation

Relevant files:

- `FLYR/Features/Map/Models/SessionRecord.swift`
- `FLYR/MainTabView.swift`
- `FLYR/Features/Map/Views/EndSessionSummaryView.swift`
- `FLYR/Feautures/Home/Views/ActivityView.swift`
- `FLYR/Feautures/Campaigns/Views/NewCampaignDetailView.swift`

### Carry the session ID

Update `EndSessionSummaryItem` in `SessionRecord.swift` so it includes:

- `sessionID: UUID?`

This matters because the share view needs the actual saved session ID to request the remote image.

### Pass the session ID through presenters

When constructing `EndSessionSummaryItem`, pass:

- `sessionManager.pendingSessionSummarySessionId`
- `SessionManager.lastEndedSessionId`
- `session.id` from activity/campaign reopen flows

The main places are:

- `MainTabView.swift`
- `ActivityView.swift`
- `NewCampaignDetailView.swift`

### Use the server image first

In `EndSessionSummaryView.swift`, update `ShareActivityGateView`:

- add `sessionID: UUID?`
- if both `AuthManager.shared.user?.id` and `sessionID` exist:
  - call `ChallengeService.shared.fetchShareCardImage(...)`
- if remote fetch fails:
  - fall back to the local `ShareCardGenerator.generateShareImages(...)`

This keeps the current UX working while preferring the canonical backend-rendered card.

## 4. Challenge Service Networking

Add these helpers to `ChallengeService.swift`.

### Rolling leaderboard

Add a method to call the rolling RPCs:

- `fetchFirst30RollingLeaderboard(limit:)`

### Evaluate badges

Add a method to call the Edge Function directly:

- `evaluateBadges(for:challengeID:)`

Implementation details:

- URL: `\(SUPABASE_URL)/functions/v1/evaluate-badges`
- Headers:
  - `Authorization: Bearer <access token>`
  - `apikey: <anon key>`
  - `Content-Type: application/json`

### Share card fetch

Add:

- `fetchShareCardImage(userID:sessionID:challengeID:)`
- `warmShareCard(userID:sessionID:challengeID:)`

Use:

- `FLYR_PRO_API_URL`
- normalize `flyrpro.app` to `https://www.flyrpro.app` like the other iOS backend clients do

Expected endpoint:

- `/api/share-card`

## 5. Weekly Accountability Card

The minimal iOS wiring does not need to generate the weekly card locally.

Backend owns:

- weekly data aggregation
- card generation
- storage
- notification row creation

iOS only needs to consume it later when you add the notification entry point.

Recommended future hook:

- add an app route or notification destination that opens the remote weekly card in a full-screen preview
- use the same share sheet pattern as session cards

## 6. What Not To Wire Into

Do not put First 30 Days challenge data into:

- `FLYR/Features/Stats/Services/LeaderboardService.swift`
- `FLYR/Features/Stats/ViewModels/LeaderboardViewModel.swift`
- `FLYR/Features/Stats/Views/LeaderboardView.swift`

Reason:

- those files are for the generic app leaderboard
- the challenge leaderboard uses a different query shape and different UI rules

## 7. Recommended Wiring Order

1. Deploy backend migration and functions
2. Add challenge leaderboard models in `Challenge.swift`
3. Add challenge service fetch methods in `ChallengeService.swift`
4. Load rolling leaderboard in `ChallengesViewModel.swift`
5. Render challenge leaderboard in `ChallengesHomeView.swift`
6. Pass `sessionID` through summary/share presenters
7. Call `evaluateBadges` after session saves
8. Prefer remote share-card images in `ShareActivityGateView`

## 8. Verification Checklist

### Challenge screen

- Open Challenges
- Confirm the 30 Day hero card still loads
- Confirm the live leaderboard appears
- Confirm badge emoji render inline
- Confirm streak pill only shows when streak is 2 or more

### Session end

- End a session with homes reached
- Confirm the session saves successfully
- Confirm the share flow opens
- Confirm the server image loads when `sessionID` exists
- Confirm local fallback still works if remote fetch fails

### Badge behavior

- Hit a threshold like 25 homes total
- Confirm `evaluate-badges` is called after save
- Refresh challenge screen
- Confirm the badge appears

### Reopen flows

- Open a past session from Activity
- Open a past session from Campaign Detail
- Confirm the share preview still works using the saved `sessionID`

## 9. Current Assumptions

- First 30 Days is backed by `challenge_templates`, not the private `challenges` table
- `challenge_badges.challenge_id` points to `challenge_templates.id`
- iOS already has valid `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `FLYR_PRO_API_URL`
- web hosts the image-generation endpoints

## 10. Files You Will Most Likely Touch

- `FLYR/Features/Challenges/Models/Challenge.swift`
- `FLYR/Features/Challenges/Services/ChallengeService.swift`
- `FLYR/Features/Challenges/ViewModels/ChallengesViewModel.swift`
- `FLYR/Features/Challenges/Views/ChallengesHomeView.swift`
- `FLYR/Features/Map/SessionManager.swift`
- `FLYR/Features/Map/Models/SessionRecord.swift`
- `FLYR/Features/Map/Views/EndSessionSummaryView.swift`
- `FLYR/MainTabView.swift`
- `FLYR/Feautures/Home/Views/ActivityView.swift`
- `FLYR/Feautures/Campaigns/Views/NewCampaignDetailView.swift`

## 11. Reference Backend Files

These are useful when checking the contract from the iOS side:

- `../FLYR-PRO/supabase/migrations/20260408233000_challenge_badges_streaks_share_cards.sql`
- `../FLYR-PRO/supabase/functions/evaluate-badges/index.ts`
- `../FLYR-PRO/supabase/functions/challenge-engagement-cron/index.ts`
- `../FLYR-PRO/app/api/share-card/route.ts`
- `../FLYR-PRO/app/api/accountability-card/route.ts`

