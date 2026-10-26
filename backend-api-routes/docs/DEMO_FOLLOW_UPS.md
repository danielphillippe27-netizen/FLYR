# Demo follow-ups

WolfGrid Sales web and iOS show **Manual** and **Demo** tabs inside Follow Up.
The shared `sales_tasks` lifecycle handles completion and snoozing. Demo records
use `task_type = demo_follow_up` and metadata identifying the original send,
recipient, latest send, reply signal, and outcome. Manual calendar reminders and
tasks stay in the Manual tab.

## Release order

1. Apply `../supabase/migrations/20261026160000_demo_follow_ups.sql` to the Sales
   database using the normal reviewed migration process.
2. Deploy this `backend-api-routes` project to the Sales web backend.
3. Release the WolfGrid Sales iOS build.

The migration is additive. It does not backfill historical messages or generated
links, because generating a link is not evidence that a message was sent. Until
the migration is applied, existing communications continue working but automatic
demo reminders will not be created. The Supabase migration is applied for the web release. The iOS application
remains a separate release.

## Send and reminder lifecycle

- Older dialler text/call and contact-record send paths bridge accepted demo sends
  into the same communication record, including sends without a Sales CRM contact.
- The existing message classifier recognizes WolfGrid demo URLs, recipient
  tracking links, and Demo Center referral links explicitly targeting a demo.
- A database trigger creates the reminder in the same transaction as an accepted
  outbound demo communication, with a due date seven days after the send.
- Drafts, scheduled/pending messages, failed sends, and inbound messages do not
  create reminders. Telnyx status callbacks share the provider message ID with
  the initial send so they cannot inflate send counts or restart reminders.
- Opening a tracked link records engagement without creating a second manual
  reminder or overwriting the task due date.
- Repeated sends to the same known lead/contact (or matching recipient address)
  share one open reminder; the original or snoozed due date stays intact. An
  advisory transaction lock serializes simultaneous email/text sends by owner.
  Two unlinked recipients cannot be inferred to be the same person across
  different channels without a common CRM identity.
- Completing/stopping a reminder preserves its send history. A later demo can
  start a new reminder cycle. Automatic follow-ups do not send messages.
- Replies flag the active reminder. A verified lead signup closes it; do-not-
  contact, lost/not-interested outcomes, and contact opt-outs stop it. A final
  delivery failure stops a reminder when no other successful send remains.
- Shared static demo links currently do not provide recipient-specific viewing
  evidence. The screen explicitly says viewing is not confirmed.

## API and ownership

`GET /api/demo-follow-ups?workspaceId=...&offset=0` returns paged demo tasks;
`taskId=...` returns their send history. Both queries scope by authenticated user
and workspace. `PATCH /api/tasks` handles completion, stopping, and due-date
changes with existing personal-reference checks. `GET /api/tasks?category=manual`
excludes demo tasks. iOS uses the same demo API and excludes demo tasks from its
manual calendar/task aggregation.

## Verification

Run the focused tests with:

```sh
npx tsx --test lib/dialer/__tests__/demo-follow-ups.test.ts lib/dialer/__tests__/demo-send-route.test.ts lib/dialer/__tests__/personal-communications.test.ts lib/dialer/__tests__/follow-up-route.test.ts lib/salesperson/outreach-metrics.test.ts lib/email/demo.test.ts
npm run build
```

`scripts/test-demo-follow-ups.cjs` executes the actual migration and 15 lifecycle
scenarios against an isolated PostgreSQL-compatible PGlite database. It needs
the optional `@electric-sql/pglite` test dependency available on `NODE_PATH` and
never reads production credentials or sends communications.

The local browser fixture exercises tab separation, due filters, send history,
reply composition, failed updates, snoozing, and desktop/mobile layout with
mocked requests. It is not a signed-in production or physical-device check.
