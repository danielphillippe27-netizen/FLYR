# iOS Storms verification — October 26, 2026

Status: automated and real-provider checks pass. Physical iPhone hail selection and territory saving are verified. Physical campaign creation, home population, and canvassing remain unverified.

## Verified this run

- Signed Debug iOS build succeeded using `WolfGrid.xcodeproj`, scheme `WolfGrid`, generic iOS destination, and `../DerivedData-device-build`.
- The resulting WolfGrid application was successfully installed on Daniel’s connected iPhone, bundle `com.danielphillippe.FLYR`.
- Shared mobile session and wind integration suites passed: scoped authentication, workspace pinning, refresh recovery, wind rendering, numerical selection, territory save, campaign planning, provisioning requests, retry reuse, duplicate-click protection, and native callback invocation. These integration tests use API fixtures.
- All eight suites in `npm run test:storm-maps` passed.
- Additional hail-zone, manual drawing, campaign partitioning, wind-zone, address-count, and historical geometry suites passed. Coverage includes connected areas, holes, thresholds, missing data, the 1,000-address cap, and exact-once address coverage.
- Phone-sized Chromium test passed using mobile touch input: discover storm → select verified hail geometry → save territory → draw and close a custom boundary → save → choose saved territory → create address campaign → provision homes. Campaign API responses are fixtures.
- The browser test additionally injected a 503 provisioning failure. Continuing creation retried provisioning with the same campaign ID; exactly one campaign creation request was made.
- Real-provider test passed against the local shared workbench: 15 recent hail events retrieved from IEM; the October 21 Arizona hail event selected; provider authentication and four hail imagery requests succeeded without weather errors.
- A touch probe into the observed shaded Arizona hail area produced a reviewed numerical hail selection: clicked estimate 5.3 mm, trace-hail threshold, estimated boundary detail 939 m. Weather responses were real; app authorization/territory APIs were fixtures. No territory or campaign was saved by this probe.

## Test improvements

The browser fixture previously used mouse clicks for drawing. It failed to finish the polygon. Mobile touch emulation and taps completed the polygon successfully. The fixture now tests the interaction used by the iPhone and includes a provisioning failure/retry case.

The real-provider test still expected a visible storm-list close button after selecting a storm. Current mobile behavior automatically closes the list. The test now uses `chrome=map` and verifies that automatic close. It also supports an optional screenshot-observed hail probe through `STORMS_TEST_HAIL_TAP=x,y`.

Both scripts live in the sibling `Wolfgrid-WEB/scripts` folder. No functional app code or production deployment was changed in this verification run. The iPhone installation used the current workspace build.

## Physical device gate

iPhone Mirroring repeatedly reported “iPhone in Use — Lock your iPhone to connect.” The user was asked to lock the phone. Installation succeeded independently of Mirroring, but installation is not evidence of successful live interaction.

Still required on the physical phone:

1. Open Create → Storms with the current signed-in workspace.
2. Select a real shaded hail/wind area and observe the boundary and intensity.
3. Save a clearly named QA territory and create a real address campaign.
4. Confirm actual homes populate and the native handoff opens that campaign.
5. Start canvassing and verify a home can be opened. Do not terminate an existing user session to perform this check without their direction.

Before the physical follow-up below, no real QA campaign, territory, session, or home interaction was created. The user subsequently saved a real territory, as recorded below. Do not report physical end-to-end completion until campaign creation, home population, and canvassing have also been observed.

### Follow-up after the user locked the phone

Mirroring connected successfully. Keyboard Spotlight search and Return launched the installed WolfGrid app. The physical phone displayed WolfGrid’s sign-in screen, so an authenticated Storms interaction could not yet be performed.

The mirroring tool rejected a screenshot-based tap on the WolfGrid icon with `noWindowsAvailable` despite continuing to supply live screenshots and accept keyboard input. Return opened the app as a workaround. The user was asked to sign in, open Create → Storms, and lock the phone again. Physical campaign creation remains pending; do not treat the mirroring connection or app launch as proof of the Storms flow.

The subsequent live display showed the signed-in home screen, then the Session campaign list. The existing “Wind 93+ km/h · 2026-10-18” campaign displayed 1,011 homes. This verifies listing an existing storm campaign, not creating one in this run.

The next live display showed the physical iPhone’s Storms workbench around El Paso, a selected black hail boundary, “Storm territory saved,” a 50.8 mm+ threshold, a clicked estimate of 63.3 mm, 939 m boundary detail, and an estimated 6,446 mapped addresses. Selection and territory saving are now physically verified through the user’s manual taps.

A read-only database check confirmed the matching saved territory at `2026-10-26T16:09:31.099759+00:00`, ID `1b4bfab1-e49f-401e-9479-469719593c67`, with numerical sampling `clickedMM=63.33281621712507`, `cellMeters=939`, and `minimumHailMM=50.8`. At the first campaign check, no campaigns referenced this territory yet. The user was asked to tap Create campaign; remote touch still returned `noWindowsAvailable`. The selected area exceeds 1,000 addresses, so campaign creation should partition it into multiple campaigns.

## Evidence

Screenshots: `../TestArtifacts/storms-2026-10-26/`.

Build/install and browser/provider logs: `/tmp/wolfgrid-storms-*20261026*.log`. Local web server logs may contain short-lived weather capability URLs; do not publish them.
