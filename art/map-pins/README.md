# WolfGrid session pushpin

`WolfGrid-PushPin.blend` is the editable source for the refined iPhone pin. `pin-before.png` records the original model and `pin-refined.png` previews the blank model. `pin-number-preview.png` shows an illustrative house number; that text is excluded from the GLB exports.

The silhouette retains the original pushpin shape, with a broad flat matte number plate, rounded status-coloured rim and graphite shaft/collar. The entire top is reserved for the house number; no W or other branding belongs there. The status-coloured body and fixed details export separately so map status changes recolour only the body.

Rebuild with:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python art/map-pins/refine_pushpin.py
```

The script exports `PushPin.glb`, `PushPinBase.glb` and `PushPinTop.glb` into the main iPhone app's `Resources/MapAssets` directory. The split files share the same ground origin and glTF Y-up orientation. Their assembled model height is 5.15 m. Runtime scales this to 5.2 × 0.7 = 3.64 m; default houses use 5.2 × 0.6 = 3.12 m. This is a shared reference-height ratio, not a percentage of each individual building's measured height.

2D satellite pins and the 3D models use the same campaign address UUID, coordinates and status. Mode changes affect presentation only; manual-pin source geometry stays a Point.

The app positions manual-pin labels at the cap height plus 0.04 m and centres them over the pin. The hidden preview text object in Blender is illustrative only.

The pin is widened 3× in the horizontal plane (cap, body and stem), with its 5.15 m model height and 3.64 m runtime body height unchanged. Satellite mode displays only manually dropped/reverse-geocoded pins; preloaded campaign address points remain data, not map markers.

When a pin or its widened cap overlaps a loaded building footprint, its base lifts enough for its cap to clear the highest overlapping rendered roof by 0.65 m. The number uses the same elevation. Pins on open ground retain their original elevation and proportions.
