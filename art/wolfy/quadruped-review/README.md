# Wolfy quadruped design review

This is a new, unrigged Blender character concept created from an empty scene.
The generator does not read the former humanoid master, meshes, skeleton,
animations, or bundled iOS assets.

## Deliverables

- `Wolfy-Quadruped-Review.blend`: editable geometry, materials, studio lights and camera.
- `front.png`, `side.png`, `three-quarter.png`: 2048 × 2048 design review renders.
- `iphone-size.png`: separate 390 × 390 render for checking small-screen readability.
- `build_preview.py`: reproducible, preview-only Blender generator.

Run from this repository with Blender 5.0:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/wolfy/quadruped-review/build_preview.py
```

The silhouette uses a horizontal ribcage and pelvis, descending forelegs,
forward stifles and backward hocks, four paws, a sloping neck and a long muzzle.
All views use the same standing pose. The neutral ground is a studio floor,
not a pedestal. The coat shader blends grey, charcoal and light markings.

## Approval boundary

These are design-review assets, not a production-ready character. No armature,
animation, clothing, runtime exports, or app integration are included. Rigging,
retopology for deformation, animation and mobile performance work must wait for
character approval. Existing app assets and business features are unchanged.
