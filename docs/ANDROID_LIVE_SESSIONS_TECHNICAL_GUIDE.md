# Android Live Sessions Technical Guide

This guide is the Android handoff for implementing FLYR live sessions one-to-one with iOS. In this repo, "live session" has three related but distinct pieces:

1. **Session tracking**: the canonical `sessions` row, GPS path, metrics, lifecycle events, and final save.
2. **Shared live canvassing**: teammate presence on the map, join codes, durable participants, and shared home/door state.
3. **Beacon**: public safety/location sharing for a single active session. Beacon uses the same session lifecycle but is not the same thing as teammate shared live canvassing.

Primary iOS references:

- `FLYR/Features/Map/SessionManager.swift`
- `FLYR/Features/Map/Services/SessionsAPI.swift`
- `FLYR/Features/Map/Services/SharedLiveCanvassingService.swift`
- `FLYR/Features/Map/Models/SharedLiveCanvassingModels.swift`
- `FLYR/Features/Map/Services/SessionParticipantsService.swift`
- `FLYR/Features/Invites/Services/InviteService.swift`
- `FLYR/Features/Map/Services/SessionSafetyBeaconService.swift`
- `FLYR/Features/Map/Voice/Services/LiveSessionVoiceService.swift`

Backend references:

- `backend-api-routes/app/api/live-sessions/codes/create/route.ts`
- `backend-api-routes/app/api/live-sessions/codes/join/route.ts`
- `backend-api-routes/app/api/live-sessions/voice/join/route.ts`
- `backend-api-routes/app/lib/live-session-codes.ts`
- `backend-api-routes/app/lib/live-session-membership.ts`
- `backend-api-routes/app/lib/livekit.ts`

Supabase references:

- `supabase/migrations/20260415_shared_live_canvassing.sql`
- `supabase/migrations/20260417123000_create_session_participants.sql`
- `supabase/migrations/20260422113000_create_live_session_codes.sql`
- `supabase/migrations/20260414120000_create_session_safety_beacon.sql`
- `supabase/migrations/20260415153000_beacon_session_doors.sql`

## 1. Core Session Lifecycle

Every live session starts as a normal row in `public.sessions`.

Android must create the session row before attaching shared-live features. While active, the row has `end_time = null`. When the session ends, Android updates the same row with final metrics and `end_time`.

### Session Create Contract

iOS creates the row through `SessionsAPI.createSession(...)`.

Required/important fields:

```json
{
  "id": "session uuid generated on device",
  "user_id": "current auth user uuid",
  "campaign_id": "campaign uuid",
  "workspace_id": "campaign workspace uuid when available",
  "start_time": "ISO-8601 timestamp",
  "end_time": null,
  "doors_hit": 0,
  "distance_meters": 0,
  "active_seconds": 0,
  "session_mode": "door_knocking | flyer",
  "goal_type": "knocks | conversations | appointments | time | flyers",
  "goal_amount": 0,
  "path_geojson": "{\"type\":\"LineString\",\"coordinates\":[]}",
  "target_building_ids": ["target ids"],
  "completed_count": 0,
  "flyers_delivered": 0,
  "conversations": 0,
  "leads_created": 0,
  "auto_complete_enabled": true,
  "auto_complete_threshold_m": 15,
  "auto_complete_dwell_seconds": 5
}
```

Optional fields Android should pass when applicable:

- `notes`
- `route_assignment_id`
- `farm_id`
- `farm_touch_id`

Workspace rule: resolve `workspace_id` from the campaign first. Do not blindly use the currently selected local workspace if the campaign belongs to another workspace.

### Session Update Contract

During the session, Android should periodically sync progress with:

```json
{
  "completed_count": 12,
  "distance_meters": 914.2,
  "active_seconds": 1400,
  "path_geojson": "{\"type\":\"LineString\",\"coordinates\":[[-79.1,43.1]]}",
  "path_geojson_normalized": null,
  "flyers_delivered": 12,
  "conversations": 3,
  "leads_created": 1,
  "doors_hit": 12,
  "auto_complete_enabled": true,
  "is_paused": false
}
```

On final save, include `end_time`.

Door-knocking metric rule:

- For `session_mode = door_knocking`, `flyers_delivered` mirrors the effective door count for leaderboard compatibility.
- `doors_hit` should also be set to the effective door count.
- `completed_count` is the completed target/home count.

### Lifecycle Events

iOS logs lifecycle events through `SessionEventsAPI.logLifecycleEvent(...)`, using RPC `rpc_complete_building_in_session`.

Event types:

- `session_started`
- `session_paused`
- `session_resumed`
- `session_ended`

Android should log these with:

```json
{
  "p_session_id": "session uuid",
  "p_building_id": "",
  "p_event_type": "session_started",
  "p_lat": 43.1,
  "p_lon": -79.1,
  "p_metadata": {
    "client_mutation_id": "optional idempotency id"
  }
}
```

For home/door outcomes, Android should use the existing canonical visit/outcome path already used by iOS so that `address_statuses`, `campaign_addresses.visited`, `session_events`, and realtime subscribers stay in sync.

## 2. Host Shared Live Start

Host flow is triggered from `CampaignMapView.startBuildingSession(...)` and `SessionManager.startBuildingSession(...)`.

Exact order:

1. Generate a device-side UUID for the new session.
2. Create or queue a local session record for offline resiliency.
3. If online, upsert the `sessions` row.
4. Upsert host durable membership into `session_participants`.
5. Start local GPS/timer/session state.
6. Attach Beacon state if the user prepared Beacon before starting.
7. If `enableSharedLiveCanvassing = true`, join shared live canvassing with the session id.
8. Log `session_started`.
9. Create a 6-character join code and show/share it.

### Host Participant Upsert

Use table `public.session_participants`.

```json
{
  "session_id": "host session uuid",
  "campaign_id": "campaign uuid",
  "user_id": "host user uuid",
  "role": "host",
  "joined_at": "ISO-8601 timestamp",
  "left_at": null,
  "last_seen_at": "ISO-8601 timestamp"
}
```

Conflict target:

```text
session_id,user_id
```

If the table is missing, iOS logs a warning and continues. Android should do the same so old backend environments degrade to solo session behavior instead of blocking the user.

### Shared Live Join

For the host, `activeSharedLiveSessionId = local session id`.

Android should then upsert `campaign_presence`:

```json
{
  "campaign_id": "campaign uuid",
  "user_id": "current user uuid",
  "session_id": "active shared live session uuid",
  "lat": 43.1,
  "lng": -79.1,
  "updated_at": "ISO-8601 timestamp",
  "status": "active"
}
```

Conflict target:

```text
campaign_id,user_id
```

## 3. Join Codes

Join codes are the Android entry point for joining a teammate's live session.

Rules:

- Code alphabet: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`
- Length: `6`
- Client input sanitization: uppercase and remove non-alphanumeric characters.
- Server stores `sha256(sanitizedCode)` in `live_session_codes.code_hash`.
- TTL: `15` minutes.
- Creating a new code revokes prior active codes for the same session.
- Codes only work while the source session has `end_time = null`.

### Create Code

Endpoint:

```http
POST /api/live-sessions/codes/create
Authorization: Bearer <supabase access token>
Content-Type: application/json
```

Body:

```json
{
  "session_id": "host session uuid"
}
```

Also accepted by backend:

```json
{
  "sessionId": "host session uuid"
}
```

Success response:

```json
{
  "success": true,
  "code": "ABC123",
  "expires_at": "2026-05-27T15:00:00.000Z",
  "expiresAt": "2026-05-27T15:00:00.000Z",
  "workspace_id": "workspace uuid or null",
  "workspaceId": "workspace uuid or null",
  "campaign_id": "campaign uuid",
  "campaignId": "campaign uuid",
  "campaign_title": "Campaign title",
  "campaignTitle": "Campaign title",
  "session_id": "host session uuid",
  "sessionId": "host session uuid"
}
```

Important errors:

- `401`: missing/invalid Supabase token.
- `403`: only the session host can create a join code.
- `400`: session ended or session is not attached to a campaign.
- `404`: session or campaign not found.
- `500`: missing migration or backend failure.

Android should cache the returned code locally keyed by `session_id` until `expires_at`, matching `LocalStorage.saveLiveSessionCode(...)`.

### Join Code

Endpoint:

```http
POST /api/live-sessions/codes/join
Authorization: Bearer <supabase access token>
Content-Type: application/json
```

Body:

```json
{
  "code": "ABC123"
}
```

Success response:

```json
{
  "success": true,
  "workspace_id": "workspace uuid or null",
  "workspaceId": "workspace uuid or null",
  "campaign_id": "campaign uuid",
  "campaignId": "campaign uuid",
  "campaign_title": "Campaign title",
  "campaignTitle": "Campaign title",
  "session_id": "host session uuid",
  "sessionId": "host session uuid",
  "access_scope": "campaign",
  "accessScope": "campaign",
  "redirect": "dashboard"
}
```

Backend side effects:

- Validates the Supabase user.
- Looks up `live_session_codes` by SHA-256 code hash.
- Rejects revoked/expired codes.
- Rejects ended sessions.
- If the user is not the campaign owner, upserts them into `campaign_members` as `member`.
- Upserts them into `session_participants` for the host session with `role = member`.
- Touches `live_session_codes.last_used_at`.

Important errors:

- `400`: malformed code, expired code, ended source session, or stale campaign/session linkage.
- `401`: missing/invalid Supabase token.
- `403`: user cannot join.
- `404`: invalid code.
- `500`: missing migration or backend failure.

## 4. Invitee Android Join Flow

iOS does not immediately enter the host's session after code validation. It stores a pending handoff and opens the campaign screen.

Android should mirror this behavior:

1. User enters the 6-character code.
2. Call `POST /api/live-sessions/codes/join`.
3. Parse `campaign_id`, `campaign_title`, and source `session_id`.
4. Select/open the returned campaign in the Session tab/map.
5. Prompt user to start a shared live session in that campaign.
6. When they start, create a new local Android `sessions` row for their own metrics.
7. Set `sharedLiveSessionIdOverride` to the host/source `session_id`.
8. Upsert durable membership on the host/source session as `role = member`.
9. Publish `campaign_presence.session_id = host/source session_id`.

This distinction matters:

- The invitee's own `sessions.id` tracks their GPS, metrics, and final save.
- The host/source `session_id` is the shared-live grouping id for teammate presence and voice.
- The invitee may also be inserted as `host` for their own local session row by the generic session start path. That is okay. The shared-live membership that matters is the member row on the host/source session.

## 5. Realtime Shared Live Canvassing

Android needs two Supabase realtime subscriptions while joined:

1. `campaign_presence`, filtered by `campaign_id`.
2. `address_statuses`, filtered by `campaign_id`.

### Presence Snapshot

After subscribing, fetch current presence:

```sql
select *
from public.campaign_presence
where campaign_id = :campaignId
  and session_id = :activeSharedLiveSessionId;
```

The `session_id` filter is important. Users may be active in the same campaign but not in the same shared live session.

### Presence Merge Rules

Use the reducer behavior in `SharedLiveCanvassingReducer`.

- Key rows by `user_id`.
- Ignore incoming rows older than the currently stored row.
- If incoming `status = inactive`, remove that user from local presence.
- Do not show the current user as a teammate.
- Do not show rows whose `session_id` differs from the current shared live session id.
- Do not show rows with invalid coordinates.
- Resolve display name/avatar from `rpc_get_campaign_member_directory`; fallback to `Rep <first 4 chars>`.

Freshness config:

```text
live:   updated less than 60 seconds ago
stale:  updated between 60 and 180 seconds ago
expire: updated at least 180 seconds ago
```

UI behavior:

- Live teammates show normally.
- Stale teammates remain visible but faded.
- Expired teammates are hidden.
- Paused teammates remain visible with paused styling.

### Presence Publish Throttle

Publish presence when any of these is true:

- Forced publish.
- Status changed between `active` and `paused`.
- At least 15 seconds since last publish.
- User moved at least 20 meters from last published location.

Publish on:

- Shared live join.
- Location updates.
- Pause.
- Resume.
- App foreground.
- Periodic active session timer, every 30 seconds with `force = true`.

### Leaving Shared Live

On session end, discard, or explicit leave:

1. Mark `session_participants.left_at` and `last_seen_at` for the current user and active shared session where possible.
2. Delete the current user's `campaign_presence` row:

```sql
delete from public.campaign_presence
where campaign_id = :campaignId
  and user_id = :currentUserId;
```

3. Unsubscribe realtime channels.
4. Clear local teammate and home-state caches.

## 6. Shared Door/Home Status Updates

Shared home status is driven by `address_statuses` realtime.

Android should subscribe to:

```text
schema: public
table: address_statuses
filter: campaign_id = <campaign uuid>
```

Merge behavior:

- Key by campaign address id.
- Prefer the newest `updated_at`.
- Insert/update rows should update map status immediately.
- Delete rows should remove local status for that address.

The canonical write path should populate:

- `address_statuses.status`
- `address_statuses.updated_at`
- `address_statuses.last_action_by`
- `address_statuses.last_session_id`
- `address_statuses.last_home_event_id`
- `campaign_home_events`
- `session_events` when a session id and event type are supplied

Use the existing visit/outcome RPC flow rather than writing unrelated ad hoc rows, otherwise iOS and Android will diverge.

## 7. Database Schema Contracts

### `campaign_members`

Created in `20260415_shared_live_canvassing.sql`.

Purpose: campaign-level access for shared live canvassing.

Important fields:

```text
id uuid primary key
campaign_id uuid not null references campaigns(id)
user_id uuid not null references auth.users(id)
role text not null default 'member' check ('owner','admin','member')
created_at timestamptz not null default now()
unique (campaign_id, user_id)
```

Android normally does not write this directly during code join because the backend join endpoint does it with service role.

### `campaign_presence`

Created in `20260415_shared_live_canvassing.sql`.

Purpose: current teammate map presence.

Important fields:

```text
campaign_id uuid not null references campaigns(id)
user_id uuid not null references auth.users(id)
session_id uuid null references sessions(id)
lat double precision
lng double precision
updated_at timestamptz not null default now()
status text not null default 'active' check ('active','paused','inactive')
primary key (campaign_id, user_id)
```

Realtime publication includes this table.

### `session_participants`

Created in `20260417123000_create_session_participants.sql`.

Purpose: durable active membership for a shared live session and voice authorization.

Important fields:

```text
id uuid primary key
session_id uuid not null references sessions(id)
campaign_id uuid not null references campaigns(id)
user_id uuid not null references auth.users(id)
role text not null default 'member' check ('host','member')
joined_via_invite_id uuid null references workspace_invites(id)
joined_at timestamptz not null default now()
left_at timestamptz null
last_seen_at timestamptz not null default now()
unique (session_id, user_id)
```

### `live_session_codes`

Created in `20260422113000_create_live_session_codes.sql`.

Purpose: short join codes for active shared live sessions.

Important fields:

```text
id uuid primary key
session_id uuid not null references sessions(id)
campaign_id uuid not null references campaigns(id)
workspace_id uuid null references workspaces(id)
created_by uuid not null references auth.users(id)
code_hash text not null unique
expires_at timestamptz not null
revoked_at timestamptz null
last_used_at timestamptz null
created_at timestamptz not null default now()
```

Android should never compute or write `code_hash` directly. Use backend endpoints.

### Beacon Tables

Beacon is public safety/location sharing. It is separate from teammate shared live canvassing.

`session_shares`:

```text
id uuid primary key
session_id uuid not null references sessions(id)
created_by uuid not null references auth.users(id)
share_token_hash text not null unique
viewer_label text
expires_at timestamptz
revoked_at timestamptz
last_viewed_at timestamptz
check_in_interval_minutes integer null check (15,30,60)
created_at timestamptz not null default now()
updated_at timestamptz not null default now()
```

`session_heartbeats`:

```text
id uuid primary key
session_id uuid not null references sessions(id)
share_id uuid null references session_shares(id)
lat double precision not null
lon double precision not null
battery_level double precision
movement_state text not null default 'unknown' check ('moving','stationary','paused','unknown')
device_status jsonb not null default '{}'
recorded_at timestamptz not null default now()
created_at timestamptz not null default now()
```

`session_checkins`:

```text
session_id uuid primary key references sessions(id)
share_id uuid null references session_shares(id)
created_by uuid not null references auth.users(id)
interval_minutes integer not null check (15,30,60)
grace_period_minutes integer not null default 5
status text not null default 'active' check ('active','paused','disabled')
next_prompt_at timestamptz
last_prompted_at timestamptz
last_confirmed_at timestamptz
created_at timestamptz not null default now()
updated_at timestamptz not null default now()
```

`safety_events`:

```text
id uuid primary key
session_id uuid not null references sessions(id)
share_id uuid null references session_shares(id)
created_by uuid not null references auth.users(id)
event_type text not null check ('share_started','share_stopped','check_in_confirmed','missed_check_in','sos')
lat double precision
lon double precision
message text
metadata jsonb not null default '{}'
acknowledged_at timestamptz
created_at timestamptz not null default now()
```

## 8. LiveKit Voice

Voice is optional but should be implemented to match iOS when enabled.

Android joins voice through the backend. Do not mint LiveKit tokens on-device.

Endpoint:

```http
POST /api/live-sessions/voice/join
Authorization: Bearer <supabase access token>
Content-Type: application/json
```

Preferred body for live sessions:

```json
{
  "session_id": "active shared live session uuid",
  "campaign_id": "campaign uuid"
}
```

Success response:

```json
{
  "room_name": "flyr-session-<session uuid lowercase>",
  "participant_identity": "current user uuid",
  "participant_name": "Display Name",
  "livekit_url": "wss://...",
  "token": "livekit jwt",
  "expires_in_seconds": 900
}
```

Authorization rules:

- Source session must exist.
- Source session must have `end_time = null`.
- User must be the session host or an active row in `session_participants` with `left_at is null`.
- If not authorized, backend returns `403`.

Android behavior:

1. Request credentials when the user opens/uses voice.
2. Connect to `livekit_url` with `token`.
3. Connect muted. Do not enable microphone by default.
4. Push-to-talk begins by enabling local microphone.
5. Push-to-talk ends by disabling local microphone.
6. End transmission on app background/inactive.
7. On unexpected disconnect, schedule reconnect after about 2 seconds if the user did not explicitly disconnect.
8. Sort/display participants with speaking users first, then by name.

LiveKit room naming:

```text
flyr-session-<session_id lowercased>
```

Participant metadata includes:

```json
{
  "user_id": "user uuid",
  "campaign_id": "campaign uuid",
  "workspace_id": "workspace uuid or null",
  "session_id": "session uuid",
  "feature": "session_voice"
}
```

## 9. Beacon Public Safety Share

Beacon lets someone outside the team view a public live page. It is not the join-code teammate flow.

Android should mirror `SessionSafetyBeaconService`.

### Create Or Refresh Beacon Link

1. Revoke active unrevoked shares for the session.
2. Generate a random token on-device. iOS uses two UUID strings with dashes removed and concatenated.
3. Store `md5(token)` in `session_shares.share_token_hash`.
4. Save the raw token locally only.
5. Build public URL:

```text
https://www.flyrpro.app/beacon/<raw token>
```

Insert:

```json
{
  "session_id": "session uuid",
  "created_by": "current user uuid",
  "share_token_hash": "md5 hex of raw token",
  "viewer_label": "optional label",
  "check_in_interval_minutes": 15,
  "created_at": "ISO-8601 timestamp"
}
```

After creating a share, insert safety event:

```json
{
  "session_id": "session uuid",
  "share_id": "share uuid",
  "created_by": "current user uuid",
  "event_type": "share_started",
  "message": "Beacon sharing started"
}
```

### Heartbeats

Insert into `session_heartbeats` when Beacon is active or check-ins are enabled.

Throttle:

- Minimum 15 seconds between heartbeats.
- Unless the user moved at least 20 meters.

Payload:

```json
{
  "session_id": "session uuid",
  "share_id": "share uuid or null",
  "lat": 43.1,
  "lon": -79.1,
  "battery_level": 0.82,
  "movement_state": "moving | stationary | paused | unknown",
  "device_status": {
    "horizontal_accuracy": 8.5,
    "speed": 1.2,
    "timestamp": "ISO-8601 location timestamp"
  }
}
```

Movement state rule:

- `paused` if session is paused.
- `moving` if speed is at least `0.5 m/s`.
- `moving` if distance from last heartbeat is at least `8 m`.
- Otherwise `stationary`.

### Check-Ins

Supported intervals:

- `15`
- `30`
- `60`
- off

Grace period:

```text
5 minutes
```

When enabling:

```json
{
  "session_id": "session uuid",
  "share_id": "share uuid or null",
  "created_by": "current user uuid",
  "interval_minutes": 15,
  "grace_period_minutes": 5,
  "status": "active",
  "next_prompt_at": "confirmed_at + interval",
  "last_confirmed_at": "confirmed_at"
}
```

When user confirms check-in:

- Upsert `session_checkins`.
- Insert `safety_events.event_type = check_in_confirmed`.
- Reschedule local notifications.

When grace deadline passes:

- Insert `safety_events.event_type = missed_check_in`.
- Surface a local warning.
- Reschedule next check-in.

### End Beacon

On session end:

1. Revoke active share by setting `session_shares.revoked_at`.
2. Insert `share_stopped` safety event when possible.
3. Delete `session_checkins` for the session.
4. Clear local raw token.
5. Cancel local check-in notifications.

### Public Beacon Viewer

The public web page calls:

```sql
select public.rpc_get_public_session_beacon(:token);
```

The RPC hashes the token with MD5, verifies the share is active, verifies the session has not ended, updates `last_viewed_at`, and returns:

```json
{
  "active": true,
  "share": {
    "id": "share uuid",
    "viewer_label": "label",
    "created_at": "timestamp",
    "check_in_interval_minutes": 15,
    "last_viewed_at": "timestamp"
  },
  "session": {
    "id": "session uuid",
    "start_time": "timestamp",
    "end_time": null,
    "goal_type": "knocks",
    "goal_amount": 100,
    "completed_count": 12,
    "flyers_delivered": 12,
    "conversations": 3,
    "distance_meters": 914.2,
    "is_paused": false,
    "campaign_id": "campaign uuid"
  },
  "latest_heartbeat": {
    "lat": 43.1,
    "lon": -79.1,
    "battery_level": 0.82,
    "movement_state": "moving",
    "device_status": {},
    "recorded_at": "timestamp"
  },
  "breadcrumbs": [],
  "session_doors": [],
  "safety_events": []
}
```

If inactive:

```json
{
  "active": false,
  "reason": "expired"
}
```

## 10. Offline And Failure Behavior

Session tracking can be queued offline. Shared live cannot.

Android should match iOS behavior:

- If offline and user starts a normal session, allow local/offline session tracking if the map/session data is cached.
- If offline and user starts shared live, continue as solo and show a non-blocking reason.
- If `campaign_presence`, `campaign_members`, or `address_statuses` infrastructure is missing, mark shared live unavailable and continue solo.
- If `session_participants` is missing, continue without durable membership but voice may not work for non-host users.
- If join code endpoints return migration/backend messages, surface the API message.
- If final session save fails, keep the session open locally and let the user retry ending.

## 11. Android Implementation Checklist

Build these Android components:

- `SessionsRepository`: creates/updates/finalizes `sessions`, mirrors `SessionsAPI.swift`.
- `SessionParticipantsRepository`: upserts/marks left in `session_participants`.
- `SharedLiveCanvassingRepository`: joins/leaves shared live, publishes `campaign_presence`, subscribes to presence and `address_statuses`.
- `LiveSessionCodesApi`: wraps create/join code backend endpoints.
- `LiveSessionVoiceApi`: wraps voice join endpoint.
- `LiveSessionVoiceController`: LiveKit room connection, muted connect, push-to-talk, reconnect.
- `BeaconRepository`: session shares, heartbeats, check-ins, safety events.
- `LiveSessionCoordinator`: owns the lifecycle ordering so UI code does not accidentally publish presence before the session row exists.

Minimum state Android should expose to UI:

```text
activeSessionId: UUID?
activeSharedLiveSessionId: UUID?
campaignId: UUID?
isActive: Boolean
isPaused: Boolean
teammates: List<Teammate>
homeStatesByAddressId: Map<UUID, AddressStatus>
inviteAvailability: unknown | available | unavailable
liveCode: code + expiresAt
voiceState: idle | connecting | connected | reconnecting | failed
beaconState: active share, share URL, check-in interval, pending check-in
```

## 12. Acceptance Tests

### Host Start

1. Start a shared live session online.
2. Verify `sessions.end_time is null`.
3. Verify `session_participants` has host row.
4. Verify `campaign_presence` has host row with `session_id = host session id`.
5. Verify create-code endpoint returns a 6-character code and `expires_at`.

### Invitee Join

1. Enter valid code on second device.
2. Verify backend inserts/updates `campaign_members`.
3. Verify backend inserts/updates `session_participants` on the host session.
4. Verify Android opens the returned campaign.
5. Start the session from handoff.
6. Verify invitee creates its own `sessions` row.
7. Verify invitee publishes `campaign_presence.session_id = host session id`.

### Realtime Presence

1. Move host or invitee more than 20 meters.
2. Verify teammate marker updates on other device.
3. Pause one device.
4. Verify other device shows paused styling.
5. Wait 60 seconds without updates.
6. Verify marker is faded/stale.
7. Wait 180 seconds without updates.
8. Verify marker disappears.

### Shared Door State

1. Device A marks a home `delivered`, `talked`, `appointment`, `no_answer`, and `do_not_knock`.
2. Device B receives `address_statuses` realtime update.
3. Device B updates map state without a manual refresh.
4. Verify newer updates win over older updates.

### End Session

1. End host session.
2. Verify final metrics and `end_time` are saved.
3. Verify participant `left_at` is set for current user.
4. Verify current user's `campaign_presence` row is deleted.
5. Verify voice disconnects.
6. Verify Beacon share is revoked and check-ins are deleted.

### Error Cases

1. Offline shared live start continues solo.
2. Invalid code returns user-visible invalid code message.
3. Expired code returns user-visible expired message.
4. Ended host session cannot be joined.
5. Non-participant voice join returns `403`.
6. Missing live-session migrations produce unavailable messaging, not a crash.

## 13. Common Gotchas

- Do not use the invitee's local session id for shared presence after joining a code. Use the host/source `session_id` returned by the join endpoint.
- Do not show all campaign presence rows. Filter by active shared live session id.
- Do not write join codes from Android directly to Supabase. Always use backend endpoints.
- Do not store raw Beacon tokens in Supabase. Store only the MD5 hash server-side/table-side and keep the raw token local.
- Do not enable microphone immediately after LiveKit connect. Voice is push-to-talk.
- Do not block normal solo session tracking just because shared-live infrastructure is unavailable.
- Do not skip final `left_at` and presence cleanup on session end, or stale teammates will linger until expiry.
