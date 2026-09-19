# Wolfy 3D — implementation and release status

## Implemented

- Original Blender character, shared armature, lightweight facial bone controls,
  12 named sockets, 28 animation exports, 25 catalog entries and 21 accessory exports.
- RealityView on iOS 18+, non-AR RealityKit ARView on iOS 17. There is no SceneKit or
  game-engine dependency. Files load asynchronously after SHA-256 verification.
- A four-entity asset cache, memory-warning eviction, Low Power/Reduce Motion handling,
  offscreen animation cancellation, animation priority, duplicate celebration suppression,
  crossfades, three ambient variations, rotation, and static poster fallback.
- Home character viewport, native Den/Locker/Store, preview-before-purchase, training,
  free treat/play cooldowns, personal working hours/DND, sound/haptic controls and
  debug-only laboratory. Release builds default character/gamification flags off.
- Server-owned XP and Coins, append-only ledger, atomic purchases, inventory, one item
  per slot, rank/level gates, server-only refunds, scoped cached inventory and offline
  outfit queue. New progression is workspace-scoped; legacy all-time user_stats XP
  is preserved separately and is not silently converted into Coins.

## Art and exact paths

- Editable master: `art/wolfy/blender/Wolfy.blend`
- iOS base: `WolfGrid/Resources/Wolfy/wolfy_base.usdz`
- Web base/library: `art/wolfy/exports/wolfy.glb`
- iOS clips: `WolfGrid/Resources/Wolfy/wolfy_<clip>.usdz`
- Accessories: `WolfGrid/Resources/Wolfy/<item>.usdz` and `art/wolfy/exports/<item>.glb`
- Manifest: `art/wolfy/manifests/wolfy_manifest.json`, also bundled with the app
- Front/side/rear/poster: `art/wolfy/renders/`
- Turntable: `art/wolfy/renders/wolfy-turntable.mp4`
- Simulator recording/screenshots: `art/wolfy/renders/wolfy-simulator.mp4` and
  `simulator-*.png`. Debug fixture screenshots are explicitly labelled and do not
  prove hosted purchases or real-account data.
- Multi-angle pose renders: `art/wolfy/renders/validation/`

The base has **24,836 triangles**, flat efficient materials with no fur simulation,
no texture atlas dependency, and construction meshes batched by material. The
first model is original procedural geometry. It needs professional sculpting,
cloth-fit and expressive-animation polish before being called premium final art.
No third-party models, textures or character IP were included.

## Reproduce (from WolfGrid-IOS)

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/wolfy/scripts/build_wolfy.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python art/wolfy/scripts/validate_wolfy.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python art/wolfy/scripts/visual_check.py
swift art/wolfy/scripts/turntable_video.swift art/wolfy/renders
```

Blender used: 5.0.0. `-- --assets-only` skips renders. The build script exports
original geometry; PNG files are only thumbnails/posters. The USDZ library uses
one file per logical named clip, mapped by manifest to a skinned AnimationResource.
The GLB contains named NLA clips for web use.

## Rig, materials and extension contracts

The manifest lists every joint and socket. Preserve `WolfyRig`, `wolfy_root`,
all rest transforms and the `wolfy-v1` compatibility tag. The hierarchy runs from
pelvis/spine/chest through head/face, mirrored arms/legs, and three tail bones.
Facial expression is implemented with eye/brow/jaw/ear controls rather than a
heavy facial rig. Full visemes and polished lip sync are not shipped.

Accessories use the **same master skeleton and bind pose**, including rigid items,
so animation resources can drive the base and accessory exports together. Socket
metadata identifies placement; this version does not reparent hats to runtime
bone-attachment components. Keep accessory geometry under 5,000 triangles.

To add an accessory: add a stable catalog entry and original fitted geometry in
`build_wolfy.py`, bind it to the existing joints, export, validate, inspect all poses,
regenerate hashes/thumbnails, and seed the matching server catalog row. Never trust
client price or requirements. All launch assets are bundled; optional HTTPS URLs
in the trusted manifest can use the hash-checked 64 MB disk cache (10 MB/file).
Downloads are asynchronous foreground-session transfers, not OS-resumable background
jobs. New remote manifest distribution is not deployed.

To add an animation: create an action with a stable name, matching rest pose and
loop endpoints, add its manifest entry, then add an approved semantic state if
needed. Arbitrary model output must never select raw entities.

To add a rank: update `WolfyProgression`, SQL `wolfy_level`/catalog requirements,
rank labels and tests together. Rank accents change the platform material and
nameplate; the body proportions never change.

## Economy and authorization

Apply the intended migrations to the correct field backend:

1. `supabase/migrations/20260915150000_wolfy_home.sql`
2. `supabase/migrations/20260915170000_wolfy_character.sql`
3. `supabase/migrations/20260915200000_wolfy_field_sales_rewards.sql` — requires the separately developed `20260915190000_field_sales_v1.sql` first.

None has been applied to a hosted project in this task. Do not push unrelated
pending migrations from this dirty checkout.

Level = min(100, 1 + floor(sqrt(XP / 100))). Ranks are Rookie (1), Street Wolf (10),
Territory Wolf (25), Alpha (50), Grid Legend (100). Purchases debit **Coins only**.
XP ledger deltas cannot be negative. Support refunds append an idempotent Coin
reversal and preserve XP; they do not automatically revoke the cosmetic item.

Reward rules (XP / Coins): door 2/1, conversation 5/2, qualified lead 30/15,
appointment 60/30, verified sale 250/125, goal 50/25, training 10/5,
follow-up 15/8, campaign 100/50, streak 25/12.

Automatic hooks currently exist for accepted door/conversation events, qualified
field leads, meeting activities and goal reconciliation. Door rewards deduplicate
by target/UTC day; lead rewards deduplicate by both entity and hashed normalized
identity; meetings reward once per contact. This conservative rule avoids repeated
appointment creation farming. Training is one fixed useful objection drill and
rewards once per UTC day. Feed is free every four hours; play every thirty minutes.

A verified field-sales module appeared in the shared working tree during this run.
The separate `wolfy_field_sales_rewards` migration hooks its verified transition,
requires verifier/time fields, and awards only once per workspace/lead. Pending,
cancelled or recreated sales cannot earn duplicate rewards. The integration test
covers pending -> verified -> cancelled -> replacement. Existing XP is permanent.

**Completed follow-ups, campaign completion and streak reward rules have a
service-role-only award interface, but their source hooks remain outstanding.** No reward is issued merely from
an iOS celebration or a sales-status claim. Actual accepted activity validity still
relies on WolfGrid's existing server validation; this does not add location attestation.

All balances/inventory/equipment are workspace+user scoped. Clients have read-only
RLS and authenticated owner RPCs. Wallet row locks serialize rewards and purchases;
request IDs and unique ownership prevent double charging. Another account cannot
reuse cached state because every cache/outbox key includes workspace and user IDs.

## Mood and accessibility

Mood uses real active-session state, daily target progress and overdue follow-ups.
Pipeline Health is explicitly labelled an estimate of sales-process health, not
physical health. Unknown follow-up data has no numeric Health value. Happiness is
persisted; Energy is a readiness metaphor. There is no overnight decay job, death,
sickness, guilt notification or loss of purchased items. DND/outside work hours
select a resting state. Significant messages remain native Home text and actions.

## Verification and remaining release gates

- Swift state/progression/manifest tests and isolated PostgreSQL economy tests pass.
- USDZ hashes, skeletons and animation samples validated for 50 exports.
- Field app simulator builds and true RealityKit rendering verified.
- Simulator cold load observed about 0.67s and idle asset about 0.21s before mesh
  batching. After mesh batching, a warm simulator run measured about 0.14s for the base and 0.10s for idle. These are load observations, **not 60 FPS or device memory benchmarks**.
- The duplicate base-load race found during simulator capture was fixed with a
  shared in-flight load task. Final isolated-simulator recording verifies a single character, sale celebration
  and cap equip. Return to idle was observed in the running app.
- Hosted migration, signed-in Home/Den/Store flows, real cross-device purchases,
  iOS 17 device rendering, FPS/memory profiling, exhaustive artist clipping approval,
  full face/viseme polish and the source hooks listed above remain unverified or
  unfinished. This is a substantial working first implementation, **not full
  production acceptance of every item in the brief**.

```sh
swiftc WolfGrid/Features/Wolfy/WolfyDomain.swift scripts/test-wolfy-character.swift -o /tmp/test-wolfy-character
/tmp/test-wolfy-character WolfGrid/Resources/Wolfy/wolfy_manifest.json
PGLITE_MODULE=/path/to/@electric-sql/pglite/dist/index.js node supabase/tests/wolfy_character.mjs
```

The lab requires a Debug binary plus `--wolfy-lab`; `--wolfy-demo` runs idle,
sale celebration and cap equip without awarding anything. `--wolfy-den` and
`--wolfy-store` use labelled local visual fixtures, never real account data.

## Animation library

idle_neutral, idle_happy, idle_focused, idle_tired, blink, look_around, tail_wag, thinking, talking, listening, concerned, encouraging, celebrate_lead, celebrate_appointment, celebrate_sale, goal_completed, streak_saved, level_up, rank_up, equip_item, wave, walk, run, eat_treat, play, train, sleep, wake_up.

## Launch catalog

- Black W Hoodie — 0 Coins, level 1
- Dark Cargo Pants — 0 Coins, level 1
- Black and White Sneakers — 0 Coins, level 1
- Basic Collar — 0 Coins, level 1
- Default Den — 0 Coins, level 1
- WolfGrid Cap — 150 Coins, level 1
- Black Beanie — 100 Coins, level 1
- Silver Chain — 200 Coins, level 1
- Clear Glasses — 150 Coins, level 1
- Dark Sunglasses — 200 Coins, level 1
- Black Bandana — 100 Coins, level 1
- White Sneakers — 300 Coins, level 1
- Work Gloves — 200 Coins, level 1
- Roofing Hard Hat — 500 Coins, level 10
- High Visibility Vest — 500 Coins, level 10
- Tool Belt — 600 Coins, level 10
- Clipboard — 400 Coins, level 10
- WolfGrid Backpack — 700 Coins, level 10
- Storm Jacket — 900 Coins, level 10
- Premium Work Boots — 650 Coins, level 10
- Headset — 450 Coins, level 10
- Alpha Bomber — 1800 Coins, level 50
- Heavy Gold Chain — 1500 Coins, level 25
- Sales Tablet — 1200 Coins, level 25
- Electric Blue Aura — 2500 Coins, level 25

## SDK references

Apple's [RealityView documentation](https://developer.apple.com/documentation/realitykit/realityview)
and [AnimationResource documentation](https://developer.apple.com/documentation/realitykit/animationresource).
Availability was also checked against the installed Xcode SDK and the iOS 17 build target.
