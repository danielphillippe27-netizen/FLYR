# Campaign creation speed — November 3, 2026

Three live tests of the iOS network request sequence against https://wolfgrid.app, using the same Oshawa polygon with 172 addresses. Separate disposable QA workspaces; no existing campaign modified. This measures server/network behavior from this Mac, not iPhone screen-rendering time. Region lookup, plan gate, and workspace lookup before campaign insertion are excluded.

| Run | Create + boundary | Provision acceptance | Start through readiness detection | Map bundle fetch | Separate building fetch |
|---|---:|---:|---:|---:|---:|
| 1 | 0.47s | 0.66s | 14.16s | 0.66s | 4.19s |
| 2 | 1.64s | 0.52s | 13.79s | 0.75s | 5.40s |
| 3 | 0.20s | 0.32s | 8.95s | 6.61s | 3.19s |

Median through readiness detection: 13.79s. Polling every two seconds adds detection delay. Map bundle and building fetches above occur after readiness and are separate measurements, not a measured phone critical path.

All three successful creations returned 172 address records; endpoint checks completed. Original attempts 2 and 3 in the first workspace hit the free-plan one-campaign limit before creation, so fresh workspaces were used for the remaining two measurements.

Quality caveats: bundle buildings (173) differ from snapshot/building endpoint (185); bundle parcels (220) differ from parcel endpoint (225). Existing fixture expected counts have drifted. Initial bundle reported pending_provision links while backend optimization continued. Passing timing checks is not confirmation of complete geometry/link parity.

Performance findings:
- Most elapsed creation time is backend preparation, rather than campaign insertion.
- Separate first building requests took 3.19–5.40s. Map bundle fetches took 0.66–6.61s. Both paths have variable loading costs. Verify the phone critical path before changing map loading.
- Current uncommitted iOS creation changes already request background provisioning without waiting for full linking. Those changes were preserved and were not deployed or device-tested here.
- The backend stores empty provision_timings for these runs, and later processing rewrites map_ready_at. Use observed readiness timing for comparison; final database timestamps do not reliably preserve the first ready event.
- Instrument source resolution, geometry loading, target enrichment and bundle publishing to locate the main backend cost before selecting an optimization.

Local checks passed: ten provisioning helper checks; session-map preparation regressions (14,000 corrected-home lookups 104ms; 667-home index plus lookups 109ms); standard-map regression suite (10,000-pin first layout 3.56ms). These are Mac test measurements, not device benchmarks.

No application source changes or deployments were made by this test session. Raw reports are included alongside this report.

Cleanup attempt encountered a database statement timeout. QA records may remain in the isolated workspaces; see cleanup.json. Existing user campaigns were not changed.
