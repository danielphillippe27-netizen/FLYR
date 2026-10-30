# Map editing verification

Result: PASS — iOS simulator implementation and production backend verification.

- Debug iOS simulator build passed.
- 68 selected iOS regression tests passed with zero failures.
- 11 backend validation and authenticated request-flow tests passed.
- Backend TypeScript check passed.
- Postgres transaction, retry, conflict, undo, isolation, and permission checks passed.
- The real PMTiles rendering check passed: moved geometry was tappable, original tile features were absent, removed overlays disappeared, and Undo restored the original tile hit.
- Removing the selected building and parcel preserved all 13,328 addresses in the fixture.
- Offline journal reopen and ordered replay passed; temporary previews do not persist.

Production status: migration `20261028180000` is applied and recorded on the FLYR APP database (`kfnsnwqylsdsbgnwgxva`). The tested production build `dpl_DURhwaR36wvhM7uVnPK5s2A7Sos9` is promoted on https://wolfgrid.app. Its source was reconstructed from the previous live deployment (`dpl_EiUg11aMLWjCxjvPzmSJECWs5HV8`) and only the five additive map-edit route/service/test/migration files were added. Other local changes were excluded.

Twelve checks passed on the staged build and again through the public production endpoint: anonymous/outsider denial, owner access, atomic geometry/link/removal persistence, idempotent retry, stale revision rejection, invalid geometry rejection, teammate sync, server Undo, exact source address/history preservation, and direct table/RPC bypass denial. Temporary accounts, workspace, campaign and associated rows were removed afterward. No physical-phone field trial or App Store release was performed.

Evidence: live-staged-tests.log, live-production-tests.log, tests-isolated-final.log, backend-tests.log, backend-typecheck.log, database-tests.log, report.json, map-edit-moved.png, map-edit-undone.png, and render-result.png.

Post-deploy error scan: no error-level runtime log entries for the released deployment in the inspected 20-minute window.
