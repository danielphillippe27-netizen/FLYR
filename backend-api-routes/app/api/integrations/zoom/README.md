# Zoom meeting integration

WolfGrid uses a Zoom **user-managed OAuth app**. Meeting creation happens on the server; iOS and web never receive OAuth credentials or Zoom's host-only `start_url`.

## Zoom Marketplace setup

1. Create a user-managed OAuth app.
2. Add meeting read/write access and user profile read access.
3. Add this exact production redirect URL:
   `https://sales.wolfgrid.app/api/integrations/zoom/oauth/callback`
4. Add the local callback too when developing, or set `ZOOM_OAUTH_REDIRECT_URI` to the callback registered in Zoom.

## Server environment

- `ZOOM_OAUTH_CLIENT_ID`
- `ZOOM_OAUTH_CLIENT_SECRET`
- `ZOOM_OAUTH_REDIRECT_URI` (optional when the request origin is the registered origin)
- `OAUTH_STATE_SECRET` (the existing OAuth state signing secret)
- `RESEND_API_KEY` and `RESEND_FROM_EMAIL` (required to email attendee invitations)
- `TELNYX_API_KEY` and `TELNYX_DEFAULT_SMS_FROM_NUMBER` (required to text attendee invitations)

Apply `supabase/migrations/20260806100000_zoom_meetings.sql` before deploying the routes.

## Client flow

- Web: **Meetings** in the sales navigation.
- iOS: **Follow Up → Meetings**.
- The first use asks the user to connect Zoom. Later meeting creation is one step and automatically refreshes expired Zoom access tokens.
- Email and SMS recipients entered on the meeting form receive the participant-safe Zoom join URL after the calendar event is saved. Upcoming meetings also have a **Send link** action for later sharing or resending. A delivery failure never deletes an otherwise valid meeting.
