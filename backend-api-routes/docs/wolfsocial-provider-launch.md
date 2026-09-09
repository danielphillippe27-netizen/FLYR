# WolfSocial provider launch package

## TikTok production review

Use the production app named **WolfGrid Social**.

- App icon: `../WolfGridSales/App/Assets.xcassets/AppIcon.appiconset/WolfGridIcon.png`
- Category: Business
- Description: `Create, schedule and publish original social content, manage engagement, and track results across connected accounts.`
- Terms: `https://social.wolfgrid.app/terms`
- Privacy: `https://social.wolfgrid.app/privacy`
- Platforms: Web and iOS
- Website: `https://social.wolfgrid.app`
- Web redirect URI: `https://social.wolfgrid.app/api/social/oauth/tiktok/callback`
- Verified URL prefix for `PULL_FROM_URL`: `https://social.wolfgrid.app/api/social/media/`
- Products: Login Kit and Content Posting API with Direct Post enabled
- Scopes: `user.info.basic` and `video.publish` only

Review explanation (fits the 1,000-character field):

> WolfGrid Social lets authenticated creators connect their own TikTok account and publish original photos or videos from WolfSocial on web and iOS. Login Kit uses user.info.basic to show the creator nickname/avatar and confirm the selected account. Content Posting API uses video.publish for Direct Post only. On every post screen we query current creator info, show the nickname, require manual privacy selection, default comments/Duet/Stitch off, hide Duet/Stitch for photos, enforce disabled capabilities and maximum video duration, show an editable content preview, collect commercial-content disclosures, display the required Branded Content Policy and Music Usage Confirmation declaration, and require explicit approval. Server-hosted media uses PULL_FROM_URL from our verified social.wolfgrid.app prefix. We poll publish status and show processing, success, and provider errors. We do not copy arbitrary content from other platforms or add watermarks.

Demo recording checklist:

1. Begin with the WolfGrid Sales iOS app launch screen.
2. Open WolfSocial → Connections and connect the sandbox target user.
3. Select that exact TikTok account in Create; show the live nickname/avatar and privacy options.
4. Choose an original photo or video and show the full preview and editable caption.
5. Manually choose privacy, interactions, disclosure settings, and the policy/music confirmation.
6. Approve and publish a `SELF_ONLY` sandbox post.
7. Show processing followed by the final status in Calendar and the private post in TikTok.
8. Repeat the same flow at `https://social.wolfgrid.app/social` for the web surface.
9. Keep the recording under 50 MB in MP4 or MOV format and ensure every selected product/scope is visibly demonstrated.

Do not add `video.upload` or `user.info.stats`; WolfSocial does not request them.

## Meta production launch

WolfSocial uses two distinct Meta login products in the same Meta app:

- Facebook Login for Facebook Pages.
- Instagram API with Instagram Login for Instagram professional accounts. This flow does not require a linked Facebook Page.

### Production URLs and server configuration

Register these OAuth redirect URIs exactly (including `https` and no trailing slash):

- `https://sales.wolfgrid.app/api/social/oauth/facebook/callback`
- `https://sales.wolfgrid.app/api/social/oauth/instagram/callback`

Configure both the **Page** and **Instagram** webhook objects with:

- Callback URL: `https://sales.wolfgrid.app/api/social/webhooks/meta`
- Verify token: the same high-entropy value stored as `META_WEBHOOK_VERIFY_TOKEN` in Vercel Production
- Page fields: `feed`, `messages`, and `messaging_postbacks`. Page comments are delivered through the `feed` field.
- Instagram fields: `comments` and `messages`.

Set these Vercel Production variables, then redeploy before connecting test accounts:

- `META_APP_ID`
- `META_APP_SECRET`
- `INSTAGRAM_CLIENT_ID` and `INSTAGRAM_CLIENT_SECRET` when the Instagram product exposes credentials distinct from the Meta app credentials
- `META_WEBHOOK_VERIFY_TOKEN`
- `META_API_VERSION` (optional; the server defaults to `v25.0`)
- `NEXT_PUBLIC_SOCIAL_APP_URL=https://sales.wolfgrid.app`
- `SOCIAL_TOKEN_ENCRYPTION_KEY`
- `SOCIAL_MEDIA_URL_SECRET`

Do not put the app secret, verify token, provider access tokens, or token-encryption keys in iOS configuration or source control.

### Permissions and access

Request Advanced Access and App Review for the exact Facebook scopes used by the code:

- `pages_show_list`
- `pages_read_engagement`
- `pages_manage_posts`
- `pages_manage_engagement`
- `pages_messaging`
- `pages_manage_metadata` — additionally required to install the app on a Page and subscribe `/subscribed_apps` for webhooks

Request Advanced Access and App Review for the exact Instagram Login scopes used by the code:

- `instagram_business_basic`
- `instagram_business_content_publish`
- `instagram_business_manage_comments`
- `instagram_business_manage_messages`

Complete Meta Business Verification before submitting permissions that require it. Keep the app in Development mode while testing with app-role/test users, then switch to Live only after the required permissions are approved.

The Facebook callback reads `tasks` from `/me/accounts` and saves only Pages with a Page access token and a content-management task (`CREATE_CONTENT`, `MANAGE`, or its `PROFILE_PLUS_*` equivalent). A messaging-only or analytics-only Page is not saved.

### App Review evidence

Use one continuous recording per permission group and visibly show the account name before each action:

1. Sign in to WolfGrid Sales and open Social → Connections.
2. Connect Facebook; show that only Pages where the tester can post are saved.
3. Publish a text-only Page post, a single-photo Page post, and a Page video separately.
4. Add a comment and a Messenger message from a second non-role account; show both arrive in Social → Inbox, then reply from WolfGrid Sales.
5. Connect an Instagram Business or Creator account using Instagram Login.
6. Publish, as four independent tests, a feed image, a 2-item carousel, a Reel, and a Story.
7. Add a comment and DM from a second Instagram account; show receipt and reply in Social → Inbox.
8. Revoke the integration (or invalidate the test token), attempt a publish, show the connection becomes `expired`, and use **Reconnect Facebook/Instagram** to restore it.

In each App Review permission explanation, state the user-visible feature, the Graph call it enables, and the exact point in the recording where the reviewer can see it. Provide reviewer credentials and keep every test Page/profile owned by or assigned to a review test user.

### Release verification matrix

Record the post URL/ID and result for every row; do not treat one format as evidence for another.

| Platform | Test | Expected result |
| --- | --- | --- |
| Facebook Page | Text | `/PAGE_ID/feed` returns a post ID and the post is visible on the selected Page. |
| Facebook Page | Photo | `/PAGE_ID/photos` returns a post ID and the photo is visible. |
| Facebook Page | Video | `/PAGE_ID/videos` returns a video ID, processing completes, and the post becomes visible. |
| Instagram | Feed image | Container reaches `FINISHED`; `/media_publish` returns the media ID. |
| Instagram | Carousel | Every child and the parent container reach `FINISHED` before the parent is published. |
| Instagram | Reel | Video container reaches `FINISHED`; the Reel publishes. |
| Instagram | Story | Story container publishes independently and appears in the professional account's active Story. |
| Meta auth | Expired/revoked token | Publish fails safely, connection status becomes `expired`, and the UI offers Reconnect. |

WolfSocial signs its media proxy URLs for 24 hours. The proxy generates a fresh short-lived storage URL on every Meta fetch, so the public URL remains usable while Instagram container processing is polled. During release testing, request the exact generated media URL before container creation, while processing, and immediately after `FINISHED`; each request must return `200` with the original media content type.

### Dashboard completion record

Fill this in as the Meta-side work is completed:

- [ ] Meta business verified
- [ ] Facebook Login redirect URI saved
- [ ] Instagram Login redirect URI saved
- [ ] Facebook permissions approved for Advanced Access
- [ ] `pages_manage_metadata` approved for webhook installation
- [ ] Instagram permissions approved for Advanced Access
- [ ] Page webhook object verified and fields subscribed
- [ ] Instagram webhook object verified and fields subscribed
- [ ] Facebook Page test matrix passed
- [ ] Instagram professional-account matrix passed
- [ ] Expired-token and reconnect test passed
- [ ] App switched to Live

## Remaining OAuth credentials

- YouTube: create a Web OAuth client, authorize the production redirect URI, configure the consent screen, then set `YOUTUBE_CLIENT_ID` and `YOUTUBE_CLIENT_SECRET` in Vercel Production.
- LinkedIn: create/configure the production OAuth app, authorize the production redirect URI, request the products needed for member posting and Community Management for organization posting, then set `LINKEDIN_CLIENT_ID` and `LINKEDIN_CLIENT_SECRET` in Vercel Production.
- Meta/Instagram: complete and sign off the production launch checklist above.

## LinkedIn launch and approval

1. In the LinkedIn developer app, add **Sign In with LinkedIn using OpenID Connect** and **Share on LinkedIn**. Register `https://social.wolfgrid.app/api/social/oauth/linkedin/callback` (or the exact production origin configured in `NEXT_PUBLIC_SOCIAL_APP_URL`).
2. Set `LINKEDIN_CLIENT_ID` and `LINKEDIN_CLIENT_SECRET`. Keep `LINKEDIN_ORGANIZATION_SCOPES=false`. Authorization then requests only `openid profile email w_member_social`, and only the connecting member's personal profile is offered.
3. Run `npm run test:social`, connect a test member, then publish and verify a text post, one-image post, multi-image post, and one video post. Confirm each target reaches `published`, has an external post id, and appears in the member's LinkedIn activity.
4. Apply for LinkedIn **Community Management API** access from the LinkedIn Developer Portal. Do not enable Company Pages while the application is pending.
5. After approval, set `LINKEDIN_ORGANIZATION_SCOPES=true` and reconnect LinkedIn so consent adds `rw_organization_admin r_organization_social w_organization_social`.
6. During connection, WolfSocial queries approved organization ACLs for `ADMINISTRATOR` and `CONTENT_ADMIN`. Only Pages with one of those roles are saved. The server checks the member's current role again before every Company Page post.
7. Repeat the text, one-image, multi-image, and one-video tests against an approved Company Page. Company Page visibility is always public. Video uploads use LinkedIn's initialize, multipart upload, finalize, processing-status, and Posts API sequence.

Community Management application summary:

> WolfGrid Social lets an authenticated LinkedIn member create, schedule, and publish original text, single-image, multi-image, and video content to Company Pages they administer. We request organization permissions only after Community Management approval. During OAuth we list only Pages where the member has an approved ADMINISTRATOR or CONTENT_ADMIN role, record the verified role, and re-check that role at publish time. Every post requires explicit user action or a user-defined schedule; Wolfey suggestions never auto-publish. Personal posting uses w_member_social independently. LinkedIn inbox features are disabled.
