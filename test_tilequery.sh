#!/bin/bash
# Test Tilequery API with both tilesets
# Replace YOUR_TOKEN with your actual Mapbox access token

MAPBOX_TOKEN="${MAPBOX_ACCESS_TOKEN:-YOUR_TOKEN}"

echo "=== Testing Orono Point (-78.62245, 43.98785) ==="
echo ""
echo "1. mapbox-streets-v8 (old tileset):"
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-78.62245,43.98785.json?layers=building&radius=50&limit=8&access_token=${MAPBOX_TOKEN}" | jq '.features | length' 2>/dev/null || echo "No jq installed - check raw response"
echo ""

echo "2. mapbox-buildings-v3 (new tileset - what we deployed):"
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=50&limit=8&access_token=${MAPBOX_TOKEN}" | jq '.features | length' 2>/dev/null || echo "No jq installed - check raw response"
echo ""

echo "=== Testing Toronto CBD (-79.3832, 43.6532) ==="
echo ""
echo "3. mapbox-streets-v8 (old tileset):"
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-79.3832,43.6532.json?layers=building&radius=50&limit=8&access_token=${MAPBOX_TOKEN}" | jq '.features | length' 2>/dev/null || echo "No jq installed - check raw response"
echo ""

echo "4. mapbox-buildings-v3 (new tileset):"
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-79.3832,43.6532.json?radius=50&limit=8&access_token=${MAPBOX_TOKEN}" | jq '.features | length' 2>/dev/null || echo "No jq installed - check raw response"
echo ""

echo "=== Detailed Response (Orono with buildings-v3, first feature geometry type) ==="
curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=8&access_token=${MAPBOX_TOKEN}" | jq '{feature_count: (.features | length), first_geometry_type: .features[0].geometry.type, first_properties: .features[0].properties}' 2>/dev/null || echo "Check raw response above"

