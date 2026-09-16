# Home and Den Wolfy

Home and the Den use the five user-supplied portraits, bundled unchanged as
`WolfyStage1` through `WolfyStage5`. `WolfyPortraitView` supplies subtle breathing
scale, a brief tap/reward bounce, and a crossfade when the growth stage changes.
These are whole-image effects, not skeletal animation or separate eye/tail motion.

Growth follows existing permanent XP levels: 1, 10, 25, 50 and 100. Previewing a
stage in the Den never changes XP, Coins, or unlocked progress. Missing progression
shows the puppy artwork with an unavailable-progress label in the Den.

Motion pauses for Reduce Motion, Low Power Mode, inactive scenes, rest, disappearance,
and on Home while the Den sheet is open. The image tap is also an accessibility action.

The separate RealityKit renderer and 3D assets are preserved. This change does not
add 3D Wolfy to the live map. The original clothing store was replaced by the
portrait accessory Store & Locker; see `../portrait-store/README.md` for XP wallet
and accessory details.

Verification: field simulator build succeeded; permanent-XP growth boundaries passed;
all five bundled PNGs match their source hashes. `den-simulator.png` shows the Den
running with explicitly labelled debug account data. Production reward persistence
and signed-in account flows were not revalidated as part of this visual change.
