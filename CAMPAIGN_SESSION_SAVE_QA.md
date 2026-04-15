# Campaign Session Save QA

Use this checklist against the real Supabase project after deploying the canonical RPC.

## Before You Start

- Use a campaign with at least:
  - one single-address house
  - one multi-address building
  - one active session-capable user account
- Confirm the deployed RPC exists:
  - `record_campaign_address_outcome`
- Start from a clean app launch.

## Flow 1: Next Targets Manual Complete

1. Start a door-knocking session.
2. Open `Next Targets`.
3. Tap `Complete` on one target.
4. Confirm immediately:
   - house turns green on the map
   - session progress increments once
5. Leave the campaign and reopen it.
6. Confirm after reload:
   - same house is still green
   - campaign progress reflects the hit

## Flow 2: Lead Save

1. Tap a house and open lead capture.
2. Save a lead with a status such as `Interested` or `No Answer`.
3. Confirm immediately:
   - house color updates
   - session progress increments once
   - conversation/contact counts move if expected
4. Leave and reopen the campaign.
5. Confirm after reload:
   - house color persists
   - campaign detail analytics reflect the action

## Flow 3: Just Mark

1. Open the lead sheet for a target.
2. Tap `Just Mark`.
3. Confirm immediately:
   - house turns green
   - session progress increments once
4. Reopen the campaign.
5. Confirm:
   - house stays green
   - analytics still include the visit

## Flow 4: Location Card Status Save

1. Open a house from the location card.
2. Save each of these statuses on at least one test address:
   - `Delivered`
   - `Talked`
   - `Do Not Knock`
3. Confirm immediately:
   - address color updates
   - building color updates correctly
4. Reopen the campaign.
5. Confirm:
   - the same status persists
   - the map color matches persisted state

## Flow 5: Flyer Auto-Complete

1. Start a flyer session.
2. Walk to one flyer target until it auto-completes.
3. Confirm immediately:
   - address is marked delivered
   - session progress increments once
4. Leave and reopen the campaign.
5. Confirm:
   - the address remains completed
   - campaign progress reflects the hit

## End Session

1. End the session normally.
2. Confirm:
   - the session does not remain running in the app
   - reopening the campaign still shows all saved houses
   - campaign detail analytics still show the session impact

## Multi-Address Building Check

1. Mark a multi-address building through a manual complete path.
2. Confirm:
   - all expected child addresses persist the delivered status
   - session progress increments only once for that building

## Database Spot Check

For the same address/session you tested, verify in Supabase:

- `address_statuses`
  - row exists
  - correct `status`
  - `visit_count` incremented
- `campaign_addresses`
  - `visited = true`
- `session_events`
  - completion event exists for the session
- `sessions`
  - `completed_count` moved as expected

## Known Remaining Limitation

- Multi-address building completion is still multiple RPC calls, with only the first call carrying session credit.
- That means house outcome plus session event is atomic per address write, but not yet all-or-nothing for the whole building.
