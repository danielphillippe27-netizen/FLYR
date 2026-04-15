# Visit stack — files to review

Short index of the main Swift files behind **GPS-driven session completion**, **visit inference**, **CRM/address status writes**, and the **session-events RPC** layer. Full behavior (tables, RPCs, event types, offline queue) is in [`VISIT_LOGGING_TECHNICAL.md`](VISIT_LOGGING_TECHNICAL.md).

---

## Core files (start here)

| Focus | File |
|------|------|
| **GPS + session completion orchestration** — location acceptance, scored vs legacy auto-complete, manual complete/undo, pending event flush, session lifecycle hooks | [`FLYR/Features/Map/SessionManager.swift`](../FLYR/Features/Map/SessionManager.swift) |
| **Visit inference algorithm** — scored engine over corridor context, proximity tiers, thresholds, wrong-side handling | [`FLYR/Features/Map/GPSNormalization/ScoredVisitEngine.swift`](../FLYR/Features/Map/GPSNormalization/ScoredVisitEngine.swift) |
| **CRM / map status writes** — `address_statuses` upsert, touches, `markAddressVisited`, etc. | [`FLYR/Features/Campaigns/API/VisitsAPI.swift`](../FLYR/Features/Campaigns/API/VisitsAPI.swift) |
| **Session events RPC** — `rpc_complete_building_in_session`, lifecycle events, parameter wiring | [`FLYR/Features/Map/API/SessionEventsAPI.swift`](../FLYR/Features/Map/API/SessionEventsAPI.swift) |

---

## Small companion worth opening with SessionEvents

- **Event type strings:** [`FLYR/Features/Map/API/SessionEventType.swift`](../FLYR/Features/Map/API/SessionEventType.swift) — referenced throughout `SessionManager` + `SessionEventsAPI`.

---

## If you’re tracing the full GPS normalization path

From [`VISIT_LOGGING_TECHNICAL.md`](VISIT_LOGGING_TECHNICAL.md) § GPS pipeline: `LocationAcceptanceFilter`, `SessionTrailNormalizer`, `GPSNormalizationConfig`, and campaign roads input — see also [`CAMPAIGN_ROADS_TECHNICAL.md`](CAMPAIGN_ROADS_TECHNICAL.md).
