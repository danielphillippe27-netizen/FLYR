# Android Calendar Tab Technical Guide

This is the Android handoff for copying the new iOS Calendar tab into the Android app.

The important idea: the Calendar tab is not only a `calendar_events` table UI. The product surface is a normalized calendar feed that merges:

1. Standalone calendar events from `public.calendar_events`.
2. Legacy/contact follow-up reminders from `contacts.reminder_date`.
3. Appointment/meeting activities from `contact_activities`.
4. Door-knocking/flyer session history from `sessions`.

Android should preserve that normalized feed behavior so users see the same calendar on both platforms.

## 1. Primary Files

### Calendar Feature Files

- `FLYR/Features/Calendar/Views/CalendarTabView.swift`
  - Main SwiftUI screen.
  - Owns year/month/day/list/search UI.
  - Owns event editor sheet.
  - Owns item tap routing into edit sheets/session detail.
  - Owns timeline gesture handling through a UIKit bridge.

- `FLYR/Features/Calendar/Models/FlyrCalendarEvent.swift`
  - Canonical calendar event model mapped to Supabase `calendar_events`.
  - Normalized display model `CalendarItem`.
  - Event type enum.
  - Recurrence enum.
  - Calendar item kind enum.
  - Calendar color enum.
  - Stable linked event ID helper.

- `FLYR/Features/Calendar/Services/CalendarService.swift`
  - Main calendar data orchestrator.
  - Fetches and merges standalone events, contacts, activities, and sessions.
  - Expands recurrence.
  - Creates, updates, and deletes standalone events.
  - Writes calendar mutations into the offline outbox.
  - Performs remote Supabase upserts/deletes when the outbox syncs.

- `FLYR/Features/Calendar/Services/CalendarEventRepository.swift`
  - Local GRDB repository for cached calendar events.
  - Reads/writes `cached_calendar_events`.
  - Preserves `payload_json` for full-fidelity offline round-trip.
  - Tracks `dirty` and `synced_at`.

- `FLYR/Features/Calendar/Services/CalendarDateHelpers.swift`
  - Calendar level/mode enums.
  - Month grid generation.
  - Visible fetch range calculation.
  - Day range and event intersection helpers.

- `FLYR/Features/Calendar/Services/CalendarEventLayout.swift`
  - Timeline event overlap layout engine.
  - Assigns overlapping timed events into columns.
  - Caches layouts by day and item timestamps.

- `FLYR/Features/Calendar/Services/CalendarNowDisplayLink.swift`
  - Emits the current time for the day timeline's red "now" line.
  - iOS uses `CADisplayLink` at about 1 FPS.
  - Android can use a coroutine ticker, `Handler`, or Compose `LaunchedEffect`.

### Integration Files

- `FLYR/MainTabView.swift`
  - Adds Calendar as tab index `3`.
  - Presents `NavigationStack { CalendarTabView() }`.

- `FLYR/Shared/UI/UberStyleTabBar.swift`
  - Adds bottom tab item labelled `Calendar`.
  - Uses SF Symbol `calendar` on iOS.

- `FLYR/Shared/AppUIState.swift`
  - Stores `selectedTabIndex`.
  - Tracks `calendarTabPresentationDepth`.
  - Exposes `isCalendarTabPresented`.

- `FLYR/Offline/OfflineMigrations.swift`
  - Creates and evolves local table `cached_calendar_events`.

- `FLYR/Offline/Repositories/OutboxRepository.swift`
  - Adds outbox operations:
    - `upsert_calendar_event`
    - `delete_calendar_event`

- `FLYR/Offline/Services/OfflineSyncCoordinator.swift`
  - Processes calendar outbox entries.
  - Calls `FlyrCalendarService.performRemoteUpsertEvent`.
  - Calls `FlyrCalendarService.performRemoteDeleteEvent`.

- `FLYRTests/CalendarFeatureTests.swift`
  - Tests month grid, search haystack, overlap layout, timeline slot snapping, model fields, stable IDs, and offline migration columns.

### Existing Shared Dependencies Used By Calendar

- `FLYR/Features/Contacts/Models/Contact.swift`
  - Provides contact/reminder data.

- `FLYR/Features/Contacts/Models/ContactActivity.swift`
  - Provides meeting/appointment activity data.

- `FLYR/Features/Contacts/Services/ContactsService.swift`
  - Fetches contacts and meeting activities.

- `FLYR/Feautures/Home/Services/ActivityFeedService.swift`
  - Calendar reuses activity edit and session detail flows.
  - Important methods:
    - `saveEditedItem(...)`
    - `fetchSessionRecord(sessionId:)`

- `FLYR/Feautures/Home/Views/ActivityView.swift`
  - Provides:
    - `ActivityFeedEditSheet`
    - `ActivitySessionDetailView`

- `FLYR/Features/Map/Services/SessionsAPI.swift`
  - Fetches user session rows for calendar display.

- `FLYR/Offline/Repositories/SessionRepository.swift`
  - Fetches cached/recent sessions for offline display.

- `FLYR/Feautures/Campaigns/CampaignsAPI.swift`
  - Loads campaign metadata for the event editor.

- `FLYR/Feautures/Campaigns/Hooks/UseAddressAutocomplete.swift`
  - Address autocomplete view model used by event editor location field.

- `FLYR/Shared/UI/Components/AddressSearchField.swift`
  - Shared address search UI used by the event editor.

### Supabase Migrations

- `supabase/migrations/20260602090000_create_calendar_events.sql`
  - Creates `public.calendar_events`.
  - Adds RLS policies for owner/workspace members.

- `supabase/migrations/20260602100000_calendar_events_type_contact.sql`
  - Ensures event type/contact columns exist.

- `supabase/migrations/20260602110000_calendar_events_source_link.sql`
  - Adds `source_kind` and `source_id`.
  - Adds unique source index.
  - Backfills contact follow-ups and appointments into calendar events.
  - Adds contact scheduling columns if needed.

- `supabase/migrations/20260602110000_calendar_events_campaign_recurrence.sql`
  - Adds campaign fields and recurrence fields.

## 2. Product Behavior Summary

The Calendar tab has these main states:

- Year view: 12 mini-month cards.
- Month view: month grid plus selected-day agenda details.
- Month list mode: agenda list across loaded events.
- Day view: timeline with week strip, all-day strip, timed blocks, current-time line.
- Day list mode: agenda list for selected date.
- Search mode: agenda list filtered by title, notes, location, contact, campaign, and address.
- Add event sheet: creates standalone `calendar_events` rows.
- Tap event:
  - Session item opens session detail.
  - Standalone appointment/follow-up opens editable activity-style sheet.
  - Legacy reminder/meeting opens editable activity-style sheet.

Current iOS behavior intentionally hides some partially built display modes:

- `MonthDisplayMode.compact` exists but is forced back to `.details` on appear and hidden from the menu.
- `MonthDisplayMode.stacked` exists but is forced back to `.details` on appear and hidden from the menu.
- `DayDisplayMode.multiDay` exists in code but is forced back to `.singleDay` on appear and hidden from the menu.

Android can implement only the visible modes first:

- Month details.
- Month list.
- Day single-day timeline.
- Day list.
- Search list.
- Add event sheet.

## 3. Data Model Contract

### `FlyrCalendarEvent`

This maps directly to `public.calendar_events`.

Fields:

```kotlin
data class FlyrCalendarEvent(
    val id: UUID,
    val userId: UUID?,
    val workspaceId: UUID?,
    val title: String,
    val startAt: Instant,
    val endAt: Instant,
    val isAllDay: Boolean,
    val eventType: String,
    val contactId: UUID?,
    val contactName: String?,
    val contactAddress: String?,
    val campaignId: UUID?,
    val campaignName: String?,
    val recurrenceRule: String,
    val recurrenceUntil: Instant?,
    val sourceKind: String?,
    val sourceId: UUID?,
    val notes: String?,
    val location: String?,
    val colorKey: String,
    val createdAt: Instant,
    val updatedAt: Instant,
    val deletedAt: Instant?
)
```

Defaults:

- `id`: generated client-side UUID.
- `isAllDay`: `false`.
- `eventType`: `appointment`.
- `recurrenceRule`: `none`.
- `colorKey`: `red`.
- `createdAt`: now.
- `updatedAt`: now.
- `deletedAt`: null.

JSON/database names:

```text
id
user_id
workspace_id
title
start_at
end_at
is_all_day
event_type
contact_id
contact_name
contact_address
campaign_id
campaign_name
recurrence_rule
recurrence_until
source_kind
source_id
notes
location
color_key
created_at
updated_at
deleted_at
```

### `FlyrCalendarEventType`

Raw values:

```text
appointment
door_knock
follow_up
showing
call
task
personal
```

Display titles:

```text
appointment -> Appointment
door_knock -> Door Knock
follow_up -> Follow-Up
showing -> Showing
call -> Call
task -> Task
personal -> Personal
```

Default color keys:

```text
appointment -> yellow
door_knock -> green
follow_up -> yellow
showing -> green
call -> purple
task -> yellow
personal -> gray
```

iOS selectable event types in the add sheet exclude `showing`.

Default title rule:

1. If a campaign name exists: `"{Event Type Title}: {Campaign Name}"`.
2. Else if a contact name exists: `"{Event Type Title}: {Contact Name}"`.
3. Else: `"{Event Type Title}"`.

### `CalendarRecurrenceRule`

Raw values:

```text
none
daily
weekly
monthly
```

Behavior:

- `none`: one occurrence only.
- `daily`: add 1 day per occurrence.
- `weekly`: add 1 week per occurrence.
- `monthly`: add 1 month per occurrence.

The current implementation expands recurrence client-side inside the loaded visible range.

### `CalendarEventSourceKind`

Raw values:

```text
contact_appointment
contact_follow_up
session
```

Used to link calendar events back to legacy/source records.

### Stable Linked Event ID

iOS has a deterministic linked ID helper:

```swift
FlyrCalendarEvent.linkedId(sourceKind:sourceId:eventType:)
```

Algorithm:

1. Seed string:

```text
flyr-calendar-event|{sourceKind}|{lowercase source UUID}|{eventType}
```

2. SHA-256 hash the UTF-8 seed.
3. Take the first 16 bytes.
4. Force UUID version bits to version 5:
   - `bytes[6] = (bytes[6] & 0x0f) | 0x50`
5. Force RFC variant bits:
   - `bytes[8] = (bytes[8] & 0x3f) | 0x80`
6. Build a UUID from those 16 bytes.

Android should port this exactly if it creates linked events from source records. This prevents duplicates across devices.

### `CalendarItem`

`CalendarItem` is the normalized UI model. Android should have an equivalent model, because the UI should not render four different source types directly.

```kotlin
data class CalendarItem(
    val id: String,
    val sourceId: UUID,
    val kind: CalendarItemKind,
    val eventType: String,
    val title: String,
    val startAt: Instant,
    val endAt: Instant,
    val isAllDay: Boolean,
    val notes: String?,
    val location: String?,
    val colorKey: String,
    val contactName: String?,
    val contactId: UUID?,
    val campaignName: String?,
    val campaignId: UUID?,
    val address: String?
)
```

Kinds:

```text
standalone
reminder
meeting
session
```

Search haystack:

```text
title + notes + location + contactName + campaignName + address
```

Lowercase the combined string. Search uses substring matching.

### Calendar Colors

Keys:

```text
red
blue
green
yellow
purple
pink
gray
```

iOS colors:

```text
red    -> rgb(255, 59, 48)
blue   -> rgb(10, 132, 255)
green  -> rgb(51, 199, 89)
yellow -> rgb(255, 204, 31)
purple -> rgb(176, 82, 222)
pink   -> rgb(255, 56, 115)
gray   -> system gray
```

Android should map these to Material/Compose colors, but keep the raw string keys identical for sync.

## 4. Supabase Table Contract

Table: `public.calendar_events`

Columns:

```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
workspace_id UUID REFERENCES public.workspaces(id) ON DELETE SET NULL,
title TEXT NOT NULL,
start_at TIMESTAMPTZ NOT NULL,
end_at TIMESTAMPTZ NOT NULL,
is_all_day BOOLEAN NOT NULL DEFAULT FALSE,
event_type TEXT NOT NULL DEFAULT 'appointment',
contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
contact_name TEXT,
contact_address TEXT,
campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
campaign_name TEXT,
recurrence_rule TEXT NOT NULL DEFAULT 'none',
recurrence_until TIMESTAMPTZ,
source_kind TEXT,
source_id UUID,
notes TEXT,
location TEXT,
color_key TEXT NOT NULL DEFAULT 'red',
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
deleted_at TIMESTAMPTZ
```

Important indexes:

```sql
idx_calendar_events_user_range(user_id, start_at, end_at) WHERE deleted_at IS NULL
idx_calendar_events_workspace_range(workspace_id, start_at, end_at) WHERE deleted_at IS NULL
idx_calendar_events_contact_id(contact_id) WHERE contact_id IS NOT NULL AND deleted_at IS NULL
idx_calendar_events_campaign_id(campaign_id) WHERE campaign_id IS NOT NULL AND deleted_at IS NULL
idx_calendar_events_recurrence(recurrence_rule, recurrence_until) WHERE recurrence_rule <> 'none' AND deleted_at IS NULL
idx_calendar_events_source_unique(source_kind, source_id, event_type) WHERE source_kind IS NOT NULL AND source_id IS NOT NULL
```

RLS behavior:

- Read if `auth.uid() = user_id`.
- Read if `workspace_id` is set and current user is a workspace member.
- Insert/update/delete use the same owner/workspace-member rule.

Android should pass both `user_id` and `workspace_id` when available. Workspace events are shared with workspace members; personal events can have `workspace_id = null`.

## 5. Local Offline Table Contract

iOS local table: `cached_calendar_events`.

Android Room entity should mirror this closely.

Columns:

```text
id TEXT PRIMARY KEY
user_id TEXT?
workspace_id TEXT?
title TEXT NOT NULL
start_at TEXT NOT NULL
end_at TEXT NOT NULL
is_all_day INTEGER NOT NULL DEFAULT 0
event_type TEXT NOT NULL DEFAULT 'appointment'
contact_id TEXT?
contact_name TEXT?
contact_address TEXT?
campaign_id TEXT?
campaign_name TEXT?
recurrence_rule TEXT NOT NULL DEFAULT 'none'
recurrence_until TEXT?
source_kind TEXT?
source_id TEXT?
notes TEXT?
location TEXT?
color_key TEXT NOT NULL DEFAULT 'red'
payload_json TEXT?
created_at TEXT NOT NULL
updated_at TEXT NOT NULL
deleted_at TEXT?
dirty INTEGER NOT NULL DEFAULT 0
synced_at TEXT?
```

Recommended Room indexes:

```kotlin
Index(value = ["user_id", "start_at", "end_at"])
Index(value = ["workspace_id", "start_at", "end_at"])
Index(value = ["dirty", "updated_at"])
Index(value = ["contact_id"])
Index(value = ["source_kind", "source_id", "event_type"])
Index(value = ["campaign_id"])
Index(value = ["recurrence_rule", "recurrence_until"])
```

Important local behavior:

- Store the full event JSON in `payload_json`.
- Prefer decoding `payload_json` when reading, because it protects against schema drift.
- Fall back to reconstructing from columns if `payload_json` is missing.
- Local writes set `dirty = 1` and `synced_at = null`.
- Remote refresh writes set `dirty = 0` and `synced_at = now`.

## 6. Fetch Pipeline

iOS entry point:

```swift
FlyrCalendarService.fetchCalendarItems(start:end:)
```

Android equivalent:

```kotlin
suspend fun fetchCalendarItems(start: Instant, end: Instant): List<CalendarItem>
```

Required context:

- Current auth user ID.
- Current workspace ID, nullable.
- Network online/offline state.

### Step 1: Fetch Standalone Calendar Events

If offline:

- Query local `cached_calendar_events`.

If online:

- Query Supabase `calendar_events`.
- Filter:
  - `start_at < end`
  - `deleted_at IS NULL`
- If `workspaceId != null`, include:
  - `workspace_id = workspaceId`
  - OR `workspace_id IS NULL AND user_id = currentUserId`
- If `workspaceId == null`, include:
  - `user_id = currentUserId`
- Order by `start_at ASC`.
- Cache the returned events locally with `dirty = 0`.
- On failure, fall back to local cache.

Why iOS only filters `start_at < end` remotely:

- Recurring events may start before the visible range and still produce occurrences inside it.
- The later recurrence expansion/intersection step decides actual visibility.

### Step 2: Fetch Contacts

Fetch contacts through `ContactsService.fetchContacts(userID:workspaceId:)`.

Fallback:

- If remote fetch fails, use local `ContactRepository.fetchContacts`.

Calendar uses contacts for legacy follow-up reminders:

- `contacts.reminder_date`
- duration: 30 minutes
- kind: `reminder`
- eventType: `follow_up`
- title: `Follow up: {contact.fullName}`
- colorKey: `yellow`
- contact fields preserved.

### Step 3: Fetch Contact Meeting Activities

Fetch activities:

- table: `contact_activities`
- filter: `contact_id IN (...)`
- type: `meeting`
- order: `timestamp DESC`
- limit: `500`

Fallback:

- Use local cached contact activities.

Calendar meeting item mapping:

- kind: `meeting`
- eventType: `appointment`
- start: `activity.timestamp`
- end: `activity.timestamp + 1 hour`
- title: parsed from activity note, fallback to `Meeting: {contact.fullName}` or `Meeting`
- notes: `activity.note`
- location/address: contact address
- colorKey: `yellow`

Meeting title parser:

1. Remove `Appointment | `.
2. Split by `|`.
3. Trim pieces.
4. Use first piece that does not start with:
   - `Start:`
   - `End:`
   - `Address:`
5. Fallback to contact name.

### Step 4: Fetch Sessions

Local:

- Fetch recent sessions with limit `1000`.
- Keep sessions for current user only.
- Keep sessions intersecting requested range.

Remote:

- If online, call the session API equivalent:
  - current user ID
  - workspace ID
  - start
  - end
  - limit `1000`
- If offline, skip remote.

Merge:

- Combine remote and local.
- De-dupe by `session.id` when present.
- If `session.id` missing, de-dupe by `{userId}-{start_time_epoch}`.
- Sort by `start_time ASC`.

Session calendar item mapping:

- kind: `session`
- eventType: `door_knock`
- start: `session.start_time`
- end:
  - `session.end_time`
  - else `session.start_time + max(60, durationSeconds)`
- title:
  - if active/no end time: `"{Session Mode Display Name} Active"`
  - else `"{Session Mode Display Name}"`
- color:
  - `blue` for flyer mode
  - `green` for other session modes
- address/details text:
  - homes count if `doorsCount > 0`
  - conversations if > 0
  - leads if > 0
  - appointments if > 0
  - distance in km if > 0
  - fallback duration in minutes

### Step 5: Expand Recurrence

For each standalone event:

- If `recurrence_rule = none`, include only if event intersects range.
- If recurring:
  - duration = max(60 seconds, `endAt - startAt`)
  - recurrence end = min(`recurrenceUntil ?: rangeEnd`, `rangeEnd`)
  - skip if event starts after range end.
  - skip if recurrence end is before range start.
  - loop from original start:
    - create occurrence if occurrence intersects range
    - add one recurrence component
    - stop if next occurrence is not greater than current
    - stop if occurrence start is after recurrence end
    - safety stop at 1000 occurrences

Occurrence item ID:

```text
event-{event.id}-{yyyy-MM-dd-HHmm}
```

Non-recurring item ID:

```text
event-{event.id}
```

### Step 6: Remove Legacy Duplicates

Contacts/reminders/meetings are fallback/compatibility items. If a real `calendar_events` row duplicates one, hide the legacy item.

Duplicate detection:

- Only applies to legacy kinds:
  - `reminder`
  - `meeting`
- Must have a contact ID.
- Calendar event must:
  - not be deleted
  - have same `eventType`
  - have `event.contactId ?? event.sourceId == item.contactId`

Reminder duplicate:

- `abs(event.startAt - item.startAt) <= 30 minutes`

Meeting duplicate:

- duplicate if `abs(event.startAt - item.startAt) <= 60 minutes`
- or if item notes contain any case-insensitive marker:
  - `Appointment`
  - `Starts:`
  - `Start:`

### Step 7: Sort

Final item list:

1. Sort by `startAt ASC`.
2. If same start time, sort by title case-insensitively.

## 7. Create, Update, Delete

### Create Event

iOS entry point:

```swift
FlyrCalendarService.createEvent(_:)
```

Behavior:

1. Resolve current `userId` and `workspaceId`.
2. Upsert locally into `cached_calendar_events`.
3. Fill missing `userId`/`workspaceId`.
4. Set `updatedAt = now`.
5. Mark local row `dirty = true`.
6. Encode full event JSON.
7. Enqueue outbox entry:
   - `entityType = "calendar_event"`
   - `entityId = event.id`
   - `operation = upsert_calendar_event`
   - payload: `{ "eventJSON": "{...}" }`
   - dependencyKey: `calendar_event:{lowercase event id}`
8. If online, schedule outbox processing.

Android should use the same optimistic local write pattern.

### Update Event

iOS update path is used when editing a standalone calendar item through the activity-style sheet.

Inputs:

- source `CalendarItem`
- new title
- new location
- new start date
- new notes

Rules:

- Look up existing cached event by `item.sourceId`.
- Keep existing duration, minimum 15 minutes.
- `endAt = newStartAt + duration`.
- Trim title/location/notes.
- Empty location becomes null.
- Empty notes become null.
- Resolve event type from existing event, else item type, else appointment.
- If title is empty, use existing title or event type default title.
- Preserve existing contact/campaign/source/color/recurrence metadata.
- Save through create/upsert path.

### Delete Event

iOS entry point:

```swift
FlyrCalendarService.deleteEvent(id:)
```

Behavior:

1. Soft delete local row:
   - set `deletedAt = now`
   - set `updatedAt = now`
   - set `dirty = true`
2. Enqueue outbox entry:
   - `entityType = "calendar_event"`
   - `entityId = event id`
   - `operation = delete_calendar_event`
   - payload: `{ "eventId": "{uuid}" }`
   - dependencyKey: `calendar_event:{lowercase event id}`
3. If online, schedule outbox processing.

Remote delete is also soft delete:

```sql
UPDATE calendar_events
SET deleted_at = now(), updated_at = now()
WHERE id = :id
```

## 8. Remote Upsert Contract

iOS performs remote upsert directly on Supabase:

Table:

```text
calendar_events
```

Conflict target:

```text
id
```

Payload:

```json
{
  "id": "uuid",
  "user_id": "uuid or null",
  "workspace_id": "uuid or null",
  "title": "string",
  "start_at": "timestamp",
  "end_at": "timestamp",
  "is_all_day": false,
  "event_type": "appointment",
  "contact_id": "uuid or null",
  "contact_name": "string or null",
  "contact_address": "string or null",
  "campaign_id": "uuid or null",
  "campaign_name": "string or null",
  "recurrence_rule": "none",
  "recurrence_until": "timestamp or null",
  "source_kind": "string or null",
  "source_id": "uuid or null",
  "notes": "string or null",
  "location": "string or null",
  "color_key": "red",
  "updated_at": "timestamp",
  "deleted_at": "timestamp or null"
}
```

Include `created_at` only if the event has a real created timestamp.

After remote upsert:

- Use the returned row if Supabase returns one.
- Cache it locally with `dirty = false`.
- Mark synced.

## 9. Outbox Contract

Operations:

```text
upsert_calendar_event
delete_calendar_event
```

Upsert payload:

```json
{
  "eventJSON": "{serialized FlyrCalendarEvent JSON}"
}
```

Delete payload:

```json
{
  "eventId": "uuid"
}
```

Android should process outbox entries in dependency order if the Android app already has an outbox dependency system. Calendar uses:

```text
calendar_event:{eventId lowercase}
```

Processing:

- Upsert:
  - Decode event JSON.
  - Remote upsert.
  - Cache returned row.
  - Mark local row synced.
- Delete:
  - Decode event ID.
  - Remote soft delete.
  - Mark local row synced.

## 10. UI State

iOS `CalendarTabView` state:

```text
level: year | month | day
selectedDate: Date
visibleDate: Date
monthMode: compact | stacked | details | list
dayMode: singleDay | multiDay | list
items: [CalendarItem]
isLoading: Bool
searchText: String
isSearching: Bool
showingAddSheet: Bool
draftStartDate: Date
hourHeight: CGFloat
dayLayouts: [yyyy-MM-dd: [CalendarTimedEventLayout]]
selectedEditableItem
selectedCalendarEditableItem
selectedSessionDetail
showItemOpenError
```

Android Compose equivalent:

```kotlin
data class CalendarUiState(
    val level: CalendarLevel = CalendarLevel.Month,
    val selectedDate: LocalDate = LocalDate.now(),
    val visibleDate: YearMonth = YearMonth.now(),
    val monthMode: MonthDisplayMode = MonthDisplayMode.Details,
    val dayMode: DayDisplayMode = DayDisplayMode.SingleDay,
    val items: List<CalendarItem> = emptyList(),
    val isLoading: Boolean = false,
    val searchText: String = "",
    val isSearching: Boolean = false,
    val showingAddSheet: Boolean = false,
    val draftStartDateTime: ZonedDateTime = ZonedDateTime.now().plusHours(1),
    val hourHeightDp: Dp = 56.dp,
    val dayLayouts: Map<LocalDate, List<CalendarTimedEventLayout>> = emptyMap(),
    val selectedItem: CalendarItem? = null,
    val openError: Boolean = false
)
```

Reload trigger:

- On screen appear.
- When `visibleDate` changes.
- After create/update/delete.

Layout recompute trigger:

- When `items` changes.
- When selected day changes in day mode.
- When day mode changes.

## 11. Calendar Navigation

### Header

Month/year header:

- Back pill shown when not in year.
- Back from month -> year.
- Back from day -> month.
- Right pill contains:
  - view mode menu
  - search toggle
  - add event

Day header:

- Back pill title is selected month name.
- Back from day -> month.
- Same right-side controls.

### Month Swipe

Horizontal drag:

- minimum distance `24`
- must be mostly horizontal
- horizontal distance must exceed `44`
- left swipe -> next month
- right swipe -> previous month
- selected date becomes new visible month date

### Month Tap

Month day cell tap:

- If tapping already-selected day, enter day view.
- If `monthMode == compact`, enter day view.
- Else only update selected date.

### Day Swipe

Only in single-day mode:

- minimum distance `28`
- horizontal movement must be greater than vertical by `1.35x`
- horizontal distance must exceed `52`
- left swipe -> next day
- right swipe -> previous day

### Default Add Start Time

When the plus button is tapped:

- If currently in day view, use selected day.
- Else use today.
- Start hour is current hour + 1, capped at 23.
- Minute/second = 0.

## 12. Date Helpers

Android should preserve these rules.

### Configured Calendar

iOS uses `Calendar.current` with current time zone.

Android should use:

- `ZoneId.systemDefault()`
- localized first day of week if possible
- or app-level first day rule matching iOS/user locale

### Month Grid

Generate exactly 42 cells.

Algorithm:

1. Get first day of displayed month.
2. Determine leading days based on first weekday.
3. Grid start = month start minus leading days.
4. Return 42 consecutive dates.
5. Mark whether each date belongs to displayed month.

This matters for visual parity and tests.

### Visible Fetch Range

iOS calendar tab loads a wide range:

```text
visibleRange(around visibleDate, monthsBefore: 6, monthsAfter: 6)
```

So Android should fetch:

- Start: start of month, six months before visible month.
- End: start of month, seven months after visible month.

This range keeps swiping/search smooth.

### Day Range

```text
start = local start of day
end = start + 1 day
```

Intersection rule:

```text
item.endAt > rangeStart && item.startAt < rangeEnd
```

Use the same strict inequality so edge-aligned items do not double count.

## 13. Year View

The year view is a scrollable 3-column grid of 12 mini-month cards.

Each card:

- Month name, abbreviated (`Jan`, `Feb`, etc.).
- Mini 7-column grid.
- Uses only first 35 cells from the 42-cell month grid.
- Today is highlighted red.
- Out-of-month days have reduced opacity.
- Tapping a card:
  - sets `selectedDate = month`
  - sets `visibleDate = month`
  - animates to month level

Android can implement this in Compose using:

- `LazyVerticalGrid(columns = GridCells.Fixed(3))`
- custom mini day cells

## 14. Month View

Visible month details mode:

1. Weekday header.
2. 7-column month grid.
3. Divider.
4. Compact agenda list for selected day.

Weekday header:

- One-letter weekday symbols.
- Ordered by calendar first weekday.

Month grid:

- 42 cells.
- Row height:
  - iOS details mode: `48`
  - compact mode: `56` but compact is currently hidden
- Day number is circular when selected/today.
- Today background: calendar red.
- Selected non-today background: system gray.
- Out-of-month opacity: `0.38`.

Markers:

- Session status marker is shown for dates up to today.
- If day has a session:
  - green check circle.
- If day does not have a session:
  - red circle with `x`.
- Session items themselves are not shown as normal month event markers.
- Non-session visible items can show:
  - `F` for follow-up.
  - `A` for appointment.
  - otherwise title pill.
- Up to 2 visible event markers are rendered in month details mode.

This session-status marker is important: the month grid doubles as a door-knocking activity compliance/status view.

## 15. Agenda List

Used by:

- Search results.
- Month list mode.
- Day list mode.
- Selected-day compact list under month grid.

Behavior:

- If empty:
  - show calendar icon
  - show `No Events`
- Non-compact:
  - group by local start day.
  - section header format: `EEE d MMM`
  - sort section dates ascending.
- Compact:
  - single section for selected day.
  - sort by start time, then title if needed.

Row:

- Leading color dot from `colorKey`.
- Title, one line.
- Subtitle:
  - `All-day` for all-day events.
  - else `{h:mm a} - {h:mm a}`
  - append ` · {location}` if location exists.
- Search mode highlights the matching text in the title with calendar red.

## 16. Day Timeline

The day timeline is the most complex UI in the feature.

Sections:

1. Week strip.
2. Selected day title bar.
3. Optional all-day strip.
4. Vertical hour grid and timed event blocks.

### Week Strip

- Shows 7 days for the selected week.
- Uses one-letter weekday format.
- Selected day has red filled circle.
- Today uses red text when not selected.
- Dates outside selected month use secondary text.

### Selected Day Title

Format:

```text
EEEE - MMM d, yyyy
```

iOS source uses an en dash in the formatter string. Android can use a hyphen for ASCII-safe parity:

```text
Tuesday - Jun 2, 2026
```

### All-Day Strip

Render if any all-day item intersects any displayed timeline day.

- Horizontal scroll.
- Pills use event color.
- Tapping pill opens item.

### Hour Grid

- 24 rows.
- `hourHeight` default: `56`.
- Gutter width iOS: `56`.
- Hour 0 label is empty.
- Hour 12 label is `Noon`.
- Other labels use `h AM/PM`.
- Scrolls vertically.
- On appear:
  - if selected date includes today, scroll to current hour minus 5.
  - else scroll to 8 AM.

### Pinch Zoom

iOS supports pinch on the timeline:

- Baseline is hour height when pinch begins.
- New hour height = baseline * scale.
- Clamp: `28...88`.

Android Compose can use `detectTransformGestures` or a nested pointer input.

### Long Press To Add

Long press on empty timeline:

- Resolve pressed point to date/time.
- Snap to nearest 15 minutes.
- Open add event sheet with that start time.

Slot resolver:

```text
if no days or invalid width/hourHeight -> null
x is clamped to gutter...timelineWidth
dayWidth = (timelineWidth - gutterWidth) / dayCount
dayIndex = floor((x - gutterWidth) / dayWidth), clamped
rawMinutes = point.y / hourHeight * 60
snapped = round(rawMinutes / 15) * 15
snapped is clamped to 23:45
date = startOfDay(days[dayIndex]) + snapped minutes
```

### Tap Item

iOS uses a transparent UIKit overlay so gestures can coexist with ScrollView.

Tap handling:

1. Ignore taps in gutter.
2. Determine day column from `x`.
3. Determine local X inside day.
4. Check each layout block bounds.
5. Return first item whose block contains the point.

Android can instead make event blocks clickable directly, but long press/pinch/scroll conflict should be tested carefully.

### Current Time Line

Shown only if one of the timeline days is today.

- Label: current time formatted `h:mm`.
- Red capsule in gutter.
- Small red dot.
- Red horizontal line across timeline.
- Y offset:

```text
(currentHour * 60 + currentMinute) / 60 * hourHeight - 10
```

iOS updates roughly once per second.

## 17. Timed Event Layout

iOS file: `CalendarEventLayout.swift`.

Model:

```kotlin
data class CalendarTimedEventLayout(
    val id: String,
    val item: CalendarItem,
    val column: Int,
    val columnCount: Int,
    val startMinute: Int,
    val durationMinutes: Int
)
```

Algorithm:

1. Get day start and day end.
2. Keep timed items only:
   - `!isAllDay`
   - item intersects day range.
3. Sort:
   - by `startAt ASC`
   - if same start, by `endAt ASC`
4. Maintain `active` list of overlapping items with assigned columns.
5. For each item:
   - remove active entries whose `endAt <= item.startAt`.
   - if active is empty and results are not empty, increment group index.
   - find the lowest non-used column among active entries.
   - append item to active and results.
   - update max column for current group.
6. Convert results to layout:
   - clip start to day start.
   - clip end to day end.
   - `startMinute = minutesBetween(dayStart, clippedStart)`.
   - `durationMinutes = max(15, minutesBetween(clippedStart, clippedEnd))`.
   - `columnCount = groupMaxColumn + 1`.

Rendering:

```text
dayWidth = (timelineWidth - gutterWidth) / dayCount
columnWidth = (dayWidth - 8) / columnCount
height = max(22, durationMinutes / 60 * hourHeight - 2)
x = 4 + column * columnWidth
y = startMinute / 60 * hourHeight
block width = columnWidth - 3
```

Important behavior:

- Items ending exactly when another starts do not overlap.
- Overlap groups are independent.
- Minimum visible event duration is 15 minutes.
- Minimum block height is 22 px/points.

## 18. Add Event Sheet

iOS component is embedded in `CalendarTabView.swift` as `CalendarEventEditorSheet`.

Fields:

- Title.
- Location/address autocomplete.
- All-day toggle.
- Start date/time.
- End date/time.
- Type selector.
- Repeat picker.
- Optional repeat end date.
- Lead search/select.
- Campaign search/select.
- Color selector.
- Notes.

### Initial Values

- Start: passed in from plus button or long press.
- End: start + 1 hour.
- Recurrence until: start + 3 months.
- Event type: `appointment`.
- Color: `red`.
- All-day: false.

### Save Button

Button label: `Add`.

Disabled state:

- iOS currently always allows save (`canSave == true`).
- Android may keep that behavior for parity, but it is reasonable to prevent empty invalid date edge cases if product approves it.

On save:

1. `normalizedEnd = max(endDate, startDate + 15 minutes)`.
2. Trim title.
3. If title empty, use event type default title with selected contact/campaign.
4. Resolve location:
   - address autocomplete query, trimmed, if non-empty
   - else local location string, trimmed, if non-empty
   - else selected contact address
5. Create `FlyrCalendarEvent`.
6. Save through `FlyrCalendarService.createEvent`.
7. Close sheet.

### Event Type Selector

Visible types:

- appointment
- door_knock
- follow_up
- call
- task
- personal

Hidden:

- showing

Selecting type:

- Sets `eventType`.
- Sets color to type default color.
- If current title is empty or exactly `Appointment`, replace with default title.

### Lead Search

Loads contacts on sheet task/start.

Search fields:

- full name
- address
- phone
- email
- notes

Sort:

- by full name, case-insensitive.

Limit visible results:

- first 5.

Selecting contact:

- sets selected contact.
- clears contact search.
- if location is empty, fill contact address.
- if title is empty, fill event type default title with contact name.
- clears focus.

### Campaign Search

Load campaign options:

1. Prefer `CampaignV2Store.shared.campaigns` cache.
2. Else fetch campaign metadata via `CampaignsAPI.fetchCampaignsMetadata(workspaceId:)`.

Search fields:

- display name
- region
- details
- status

Sort:

- by display name, case-insensitive.

Limit visible results:

- first 5.

Selecting campaign:

- sets selected campaign.
- clears campaign search.
- if current event type is appointment:
  - switch to `door_knock`
  - update color to door-knock default.
- if title is empty or exactly `Appointment`, fill event type default title with selected contact/campaign.
- clears focus.

### Color Selector

Renders all `CalendarColorKey` values.

Selected color displays a checkmark.

## 19. Tapping Existing Items

iOS function:

```swift
openCalendarItem(_:)
```

Routing:

- `session`:
  - fetch session record through `ActivityFeedService.fetchSessionRecord`.
  - show `ActivitySessionDetailView`.
  - show error alert if missing/failing.

- `standalone`:
  - Convert to an `ActivityFeedItem` if event type maps to activity feed kind.
  - Supported mappings:
    - `follow_up` -> followUp
    - `appointment` -> appointment
  - Opens activity edit sheet using `FlyrCalendarService.updateEvent`.
  - Other standalone types show error because there is no editor for them yet.

- `reminder` or `meeting`:
  - Convert to `ActivityFeedItem`.
  - Requires `contactId`.
  - Opens activity edit sheet using `ActivityFeedService.saveEditedItem`.
  - Show error if conversion/contact missing.

Activity feed item conversion:

- ID: `calendar-{calendarItem.id}`
- title:
  - normalized contact name if present
  - else cleaned calendar title
- subtitle:
  - address or location
- timestamp/dueDate:
  - item start
- contactId:
  - item contactId
- activityId:
  - sourceId for meeting items
- notes:
  - item notes

Title cleanup:

- Follow-up prefixes stripped:
  - `Follow up: `
  - `Follow-Up: `
  - `Follow Up: `
- Appointment prefix stripped:
  - `Appointment: `

Android can either reuse an existing activity editor or build a calendar-specific edit sheet. For parity, preserve:

- follow-up edits update contact summary/reminder date
- appointment edits update/create `contact_activities`
- standalone event edits update `calendar_events`

## 20. Search

Search is a global filter over currently loaded `items`.

Search UI:

- Header search button toggles `isSearching`.
- Closing search clears `searchText`.
- Search strip has:
  - search icon
  - text field placeholder `Search`
  - cancel button

Filtering:

- trim whitespace
- lowercase
- if empty, show all loaded items
- else include item if `searchHaystack.contains(query)`

Search haystack includes:

- title
- notes
- location
- contact name
- campaign name
- address

## 21. Formatting

Use locale-aware Android date formatters where possible, but keep these display formats close:

```text
Month title: LLLL yyyy
Month name: LLLL
Year: yyyy
Day title: EEEE, MMMM d
Month key: yyyy-MM
Day key: yyyy-MM-dd
Selected day title: EEEE - MMM d, yyyy
Agenda section: EEE d MMM
Agenda time: h:mm a
Timeline block time: h:mm-h:mm
Week strip weekday: one-letter weekday
```

Key strings must be stable:

- month layout keys: `yyyy-MM`
- day layout keys: `yyyy-MM-dd`
- recurring occurrence IDs: `yyyy-MM-dd-HHmm`

## 22. Android Architecture Recommendation

Recommended package shape:

```text
calendar/
  data/
    CalendarEventDto.kt
    CalendarEventEntity.kt
    CalendarEventDao.kt
    CalendarEventRepository.kt
    CalendarRemoteDataSource.kt
  domain/
    FlyrCalendarEvent.kt
    CalendarItem.kt
    CalendarEnums.kt
    CalendarDateHelpers.kt
    CalendarEventLayout.kt
    CalendarService.kt
  ui/
    CalendarTabScreen.kt
    CalendarViewModel.kt
    YearCalendarView.kt
    MonthCalendarView.kt
    DayTimelineView.kt
    AgendaList.kt
    CalendarEventEditorSheet.kt
```

Suggested responsibilities:

- `CalendarViewModel`
  - Owns UI state.
  - Calls `CalendarService`.
  - Handles create/update/delete intents.
  - Recomputes day layouts.

- `CalendarService`
  - Pure orchestration/data normalization.
  - Should be testable without Compose.

- `CalendarEventRepository`
  - Room DAO wrapper.
  - Converts entity <-> domain model.

- `CalendarRemoteDataSource`
  - Supabase calls only.

- `CalendarDateHelpers`
  - Pure date math.

- `CalendarEventLayout`
  - Pure layout math.

## 23. Android Implementation Checklist

### Phase 1: Data and Sync

- Add `calendar_events` DTO/model.
- Add Room table `cached_calendar_events`.
- Add migrations for all calendar columns.
- Add DAO queries:
  - fetch events for user/workspace before range end
  - fetch event by ID
  - upsert events
  - soft delete
  - mark synced
- Add outbox operations:
  - `upsert_calendar_event`
  - `delete_calendar_event`
- Add outbox payloads.
- Add remote upsert to Supabase with conflict target `id`.
- Add remote soft delete.
- Add fetch standalone events with remote/local fallback.

### Phase 2: Normalized Feed

- Add `CalendarItem`.
- Add event -> item mapping.
- Add contact reminder -> item mapping.
- Add meeting activity -> item mapping.
- Add session -> item mapping.
- Add recurrence expansion.
- Add legacy duplicate suppression.
- Add final sort.
- Add unit tests for all mappings.

### Phase 3: UI Shell

- Add Calendar bottom tab at index `3`.
- Add screen-level state.
- Add header controls.
- Add search strip.
- Add month details view.
- Add agenda list.
- Add day timeline.
- Add add event sheet.

### Phase 4: Interactions

- Month swipe.
- Day swipe.
- Tap month day.
- Tap agenda/timeline item.
- Long press timeline to add.
- Pinch timeline zoom.
- Search highlighting.
- Edit standalone appointment/follow-up events.
- Open session details.

### Phase 5: Polish and Parity

- Current-time line ticker.
- Session status marker in month cells.
- All-day strip.
- Empty states.
- Offline behavior.
- Error alert for unsupported item open.
- Tests.

## 24. Test Plan

Port these iOS tests from `FLYRTests/CalendarFeatureTests.swift`.

### Month Grid

For June 2026 in America/Toronto with Monday first weekday:

- grid count is 42
- first cell is June 1
- June 30 is in displayed month
- next cell is July 1 and not in displayed month

### Search Haystack

Calendar item search should include:

- title
- notes
- contact name
- address

### Overlap Layout

Events:

- A: 9:00-10:00
- B: 9:30-11:00
- C: 10:00-11:00

Expected:

- A column 0
- B column 1
- C column 0
- A and B columnCount 2

### Timeline Slot Resolver

Given:

- timeline width 374
- gutter width 74
- hour height 56
- days: June 2 and June 3, 2026
- point x 250, y 514

Expected:

- day: June 3
- hour: 9
- minute: 15

### Model Persistence

Ensure event preserves:

- event type
- contact ID
- contact name
- contact address
- source kind
- source ID
- color key

### Stable Linked ID

Same source kind/source ID/event type returns same UUID.

Different source kind/type returns a different UUID.

### Offline Migration

Local calendar table contains:

- `event_type`
- `contact_id`
- `contact_name`
- `contact_address`
- `source_kind`
- `source_id`

Add Android-specific tests:

- recurrence expansion stops at recurrenceUntil
- recurring event before visible start appears inside visible range
- deleted events are hidden
- workspace events and personal events both load when workspace exists
- outbox upsert marks event synced after remote success
- outbox delete soft-deletes remotely
- legacy contact reminder hidden when matching calendar event exists

## 25. Edge Cases and Gotchas

- Do not render only `calendar_events`; users will miss reminders, meetings, and sessions.
- Do not hard-delete calendar events; use `deleted_at`.
- Keep raw enum strings identical across platforms.
- Use device-local timezone for UI grouping/day ranges.
- Use Supabase timestamps/UTC instants for storage.
- Fetch a wide range around the visible month, not just the selected day.
- Recurring events that start before the visible range still need to be fetched.
- Month grid must always be 42 cells.
- Events ending exactly at day start do not belong to that day.
- Events starting exactly at day end do not belong to that day.
- Timeline overlap uses `endAt <= next.startAt` as non-overlap.
- Meeting activity limit is 500 on iOS; Android should match unless product changes it.
- Session fetch limit is 1000 on iOS.
- Event editor currently supports creating all event types except showing, but editing only maps appointment/follow-up cleanly.
- `source_kind/source_id/event_type` uniqueness is for linked/source events, not normal standalone events.
- `payload_json` matters for local compatibility; do not drop it casually.

## 26. Minimum Viable Android Parity

If Android needs a staged copy, this is the minimum useful cut:

1. Calendar tab in bottom navigation.
2. Month details grid.
3. Selected-day agenda list.
4. Day timeline.
5. Search.
6. Add standalone event.
7. Fetch normalized item stream:
   - `calendar_events`
   - contact reminders
   - meeting activities
   - sessions
8. Offline cache/outbox for standalone calendar events.
9. Unit tests for date helpers and overlap layout.

After that, add:

- event editing
- session detail opening
- all-day strip polish
- recurrence edge tests
- campaign/contact selection polish in editor

## 27. Direct iOS-to-Android Mapping Table

| iOS | Android Equivalent |
| --- | --- |
| `CalendarTabView` | `CalendarTabScreen` + `CalendarViewModel` |
| `FlyrCalendarEvent` | domain `FlyrCalendarEvent` + DTO |
| `CalendarItem` | domain UI item model |
| `FlyrCalendarService` | use case/service orchestrator |
| `CalendarEventRepository` | Room repository/DAO |
| `CalendarDateHelpers` | pure Kotlin date helpers |
| `CalendarEventLayoutCache` | pure Kotlin layout calculator plus optional cache |
| `CalendarNowDisplayLink` | coroutine/flow ticker |
| `CalendarEventEditorSheet` | Compose modal bottom sheet/dialog |
| `TimelineGestureOverlay` | Compose pointer input/gesture layer |
| `ActivityFeedEditSheet` | existing Android contact activity editor or new parity sheet |
| `ActivitySessionDetailView` | existing Android session detail screen |

## 28. Final Porting Advice

Port the domain/service layer before the UI. The hardest part is not drawing a calendar grid; it is making Android's calendar feed match iOS exactly when events come from four sources, when the user is offline, and when legacy contact reminders overlap with new first-class calendar events.

Once `CalendarService.fetchCalendarItems(start, end)` returns the same normalized `CalendarItem` list as iOS, the UI becomes straightforward Compose work.
