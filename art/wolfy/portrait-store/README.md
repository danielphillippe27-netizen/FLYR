# Wolfy XP accessory store

## Delivered design

The Den opens **Store & Locker**, with a live portrait preview, five-stage fitting
preview, category filters, owned/equipped collections, and remote purchase/equip.
Home and the Den display the same persisted outfit. Stage previews do not change XP.
Artwork and accessories breathe and react together; reduced-motion behavior is retained.

The 16 original vector designs are drawn directly in SwiftUI Canvas, registered to
each of the five supplied portrait poses. No original portrait is repainted.
Wear one chain or collar, one pair of glasses, and one glow effect together.

| Collection | Items and price in spendable XP |
| --- | --- |
| Chains | Silver Chain 150; Gold Chain 400; Cuban Link 900; Orange Pendant 600 |
| Glasses | Classic Shades 100; Gold Aviators 300; Round Frames 250; Orange Visor 650 |
| Collars | WolfGrid Collar 75; Midnight Collar 100; Teal Collar 150; Studded Collar 350 |
| Effects | Ember Glow 100; Arctic Glow 250; Golden Glow 500; Prism Glow 900 |

All launch items require level 1. Their prices provide the earning requirement.
The server remains authoritative for price, availability, ownership, and future level gates.
Unrecognized or unavailable catalog items cannot be purchased through the portrait UI.

## Wallet and migration

`20260915210000_wolfy_portrait_store.sql` adds `spendable_xp` to profiles and
`spendable_xp_delta` to the immutable ledger. Existing `xp` remains lifetime XP,
and the current five growth milestones remain unchanged.

Unspent legacy Coins convert 1:1 into spendable XP with a conversion ledger entry.
Legacy coin balances/history remain for audit; the old purchase RPC is disabled so
old clients cannot spend them again. Existing ownership is preserved. New validated
XP rewards credit both lifetime and spendable XP equally, once per source event.

`wolfy_purchase_portrait(workspace, user, item, request)` locks the wallet, checks
ownership and price, debits spendable XP, grants ownership and equips in one transaction.
Retries use the same request ID. Support refunds append one reversal and credit
spendable XP; they do not alter lifetime XP or revoke the retained item.

Authenticated clients cannot write balances or mint rewards. Existing owner/workspace
isolation and queued offline equip remain. Purchases require a connection; missing
store data allows artwork previews without enabling purchases.

## Verification and release boundary

- Field iOS simulator build passed.
- PGlite tests passed: wallet conversion, reward idempotency, purchase/equip atomicity,
  unchanged lifetime XP/rank, retry protection, insufficient balance rollback,
  foreign-user and direct-write rejection, slot replacement, refunds and catalog parity.
- Swift growth-stage and character policy tests passed.
- Simulator images capture five stage fits and the Store using labelled debug data.

The hosted migration has **not** been applied. Real-account purchase/relaunch and
cross-device validation must follow applying the migration to the intended backend.
The existing release feature flag is unchanged. No App Store release or new live-map
integration was performed. The separate 3D assets/renderer remain available.
