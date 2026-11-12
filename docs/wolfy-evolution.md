# Wolfy evolution and gradient coats

Home and Customize Wolf use five updated skinned Blender characters. Pup has a shorter muzzle and rounder eyes; later stages have narrower eyes and stronger brows. Each stage has a seamless 12-second idle with blinking, breathing, eased looking/sniffing, and stage-dependent tail/ear motion. Stage-matched celebration clips drive rewards and customization reactions.

Customize Wolf lists all five door milestones (0, 100, 500, 2,500, 10,000), with current/unlocked/locked status and accessible labels. Existing door accounting is unchanged.

Every fur palette uses the authored dark-to-light UV coat markings. The linear-RGB endpoints live in `WolfyColor.coatPalette`; ears and brows use matching endpoints, and colour-picker swatches show the same gradient. Eyes and nose retain independent colour selection.

## Asset workflow

Run Blender with `art/wolfy-v2/scripts/build_character.py`, then `art/wolfy-v2/scripts/export_ios_stages.py -- --home-only --skip-thumbnails`. Editable sources and draft motion data live in `art/wolfy-v2/character`. Copy each generated stage PNG to its corresponding WolfyStage imageset. The exporter updates bundled USDZ hashes. The map renderer's WolfyV2 bundle is unchanged.

## Validation

Simulator Debug build passed. All five exported idle/reaction meshes passed finite/bounded/ground-contact checks; idle endpoints match and bundled SHA-256 hashes validate. Customize Wolf's Alpha fixture and Arctic gradient rendered in the iPhone 17 Pro simulator. Physical-device and live-account acceptance remain untested.
