# Wolfy character revision

Authoring source: `../scripts/build_character.py` (Blender 5). Each stage has an editable `.blend`, a reference render, and hashed GPU assets. The original prototype/stage studies remain preserved in their original directories.

The pup uses a 32% larger head, a 28% shorter torso, shorter legs, larger paws, amber eyes with two highlights, a short muzzle, rounded ears, and a curved plume tail. Torso, head, cheeks, limbs and tail are a voxel-unioned smooth surface. Two-bone weights preserve continuous transitions; paws keep their volume. Older stages progressively change leg length, body length, chest width, ruff, brow and tail shape. All stages stay quadrupeds without clothing.

The 24-second idle clip moves through sniff, look, scratch, sit, rest and rise. Walk/run add oversized steps, head bob, tail sway and ear movement. This is a procedural character revision for review, not a claim of final hand-animated art quality.

Runtime: 13,314–14,039 vertices per stage. Both map renderers support the new two-bone vertex format and legacy one-bone assets. Campaigns use the pup; the existing Pack stage field selects the five silhouettes. Pack presentation remains in the existing development-only map. Its screen-space grouping keeps at most eight wolves (five when constrained), retains all other reps in counted markers, and never moves stored GPS coordinates. Tapping a pack marker zooms toward its members.

Validation: `scripts/validate-wolfy-v2-assets.py`, `scripts/validate-wolfy-character-motion.py` (NumPy), and the standalone Swift pack motion/layout tests.
