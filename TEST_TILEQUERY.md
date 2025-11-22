# Tilequery API Test Commands

## Important: We deployed `mapbox-buildings-v3`, not `mapbox-streets-v8`

The Edge Function now uses `mapbox.mapbox-buildings-v3` tileset. Test both to compare coverage.

## Test Commands

Replace `YOUR_TOKEN` with your actual Mapbox access token (starts with `pk.` for public or `sk.` for secret).

### Orono Point (-78.62245, 43.98785)

**Old tileset (mapbox-streets-v8):**
```bash
curl "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-78.62245,43.98785.json?layers=building&radius=50&limit=8&access_token=YOUR_TOKEN"
```

**New tileset (mapbox-buildings-v3) - What we deployed:**
```bash
curl "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=50&limit=8&access_token=YOUR_TOKEN"
```

**With 75m radius (retry):**
```bash
curl "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=8&access_token=YOUR_TOKEN"
```

### Toronto CBD (-79.3832, 43.6532) - Should return features

**Old tileset:**
```bash
curl "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-79.3832,43.6532.json?layers=building&radius=50&limit=8&access_token=YOUR_TOKEN"
```

**New tileset:**
```bash
curl "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-79.3832,43.6532.json?radius=50&limit=8&access_token=YOUR_TOKEN"
```

## Quick Test with jq (if installed)

Count features returned:
```bash
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=8&access_token=YOUR_TOKEN" | jq '.features | length'
```

Check first geometry type:
```bash
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=8&access_token=YOUR_TOKEN" | jq '.features[0].geometry.type'
```

## Expected Results

- **Toronto CBD**: Should return multiple features (urban area)
- **Orono**: May return 0 features if sparse coverage (rural area) - this is expected, proxies will be used

## What to Look For

1. **Feature count**: `{"features": [...]}` array length
2. **Geometry types**: Should be `"Polygon"` or `"MultiPolygon"` only
3. **Response status**: Should be 200 OK
4. **Coverage comparison**: Compare buildings-v3 vs streets-v8 for same coordinates

## Notes

- `mapbox-buildings-v3` doesn't need `layers=building` parameter (it's building-only)
- `mapbox-streets-v8` requires `layers=building` parameter
- Our Edge Function uses 50m initial, 75m retry with `mapbox-buildings-v3`

