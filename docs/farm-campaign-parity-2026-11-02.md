# Farm and campaign changes — November 2, 2026

This is an inventory of the iOS work identified from today's Farm-related chats and the current checkout. Shared code indicates an implementation path, not proof of an end-to-end campaign test.

## Address and map workflow

- Temporary Mapbox suggestions for unlinked properties, house-number labels, taps, lookup fallback, local saves, duplicate checks, and neighbouring townhouse processing: previously Farm-only; enabled in the campaign Mapbox property map in this change. It requires loaded property geometry, network service for lookups, and close zoom. The Google 2D/Standard renderer does not use these suggestions.
- Saved house-number labels: shared map rendering, including the new building-identifier fallback. Requires visual campaign verification.
- Faster location card and local save, map update after the card appears, and reduced repeated session/geometry preparation: shared map implementation; actual campaign timing remains to be measured.
- Townhouse status colours, parcel boundaries, and immediate parcel status indexing: shared map renderer; the specific reported properties and campaign behavior still need physical-device verification.
- Do Not Knock control and map colours: shared property card and map layers; appearance still needs campaign device verification.
- GPS and wolf marker controls and proximity visit detection: shared session/map code. Simulated tests are not a real campaign walk or proof of sync.
- Lead autosave and business-card text flow: shared property card. An actual message and complete campaign flow have not been verified here.
- Session share-card fixes: shared session views. Campaign sharing has not been re-tested here.

## Details and lists

- Farm and campaign details share the session conversation-count calculation; Farm retains direct, legacy and session-linked leads. Independent detail loads and Farm session-lead lookups run concurrently with a four-request limit. Farm session membership and campaign analytics still use different queries and need end-to-end verification.
- Farm and campaign details use the same online active-home count query. Campaign detail now uses address statuses for progress and reports it unavailable when counts or activity are unavailable, or session doors exist without matching statuses. Do Not Knock is excluded, as in Farm. Farm still counts its visit records separately, so the underlying progress data sources are not identical.
- Farm lead association and Contacts Farm filter: specific to Farm identity; campaigns already have a separate campaign association/filter path. Historic missing associations are not repaired by this work.
- Farm list loading, swipe delete, cached Farm cleanup, and planned touches: Farm-specific list and data lifecycle, not a map feature that can be copied directly to a campaign.
- Home door-count correction: shared Home metrics service; campaign totals need separate validation against campaign session records.

## Known limits

- The earlier Farm investigation reported a server rejection for some municipal building IDs during address sync. This change does not establish that the server issue is resolved.
- No physical campaign end-to-end validation, real GPS walk, production release, or phone installation is implied by this inventory.
