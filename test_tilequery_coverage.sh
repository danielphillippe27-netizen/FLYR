#!/bin/bash
# Test Tilequery API coverage for Orono and Toronto
# Replace YOUR_TOKEN with your actual Mapbox secret token (sk.xxx)

MAPBOX_TOKEN="${MAPBOX_ACCESS_TOKEN:-YOUR_TOKEN}"

echo "=== Testing mapbox-buildings-v3 tileset ==="
echo ""

echo "1. Orono Point (-78.62245, 43.98785) - 50m radius:"
ORONO_50=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=50&limit=8&access_token=${MAPBOX_TOKEN}")
ORONO_50_COUNT=$(echo "$ORONO_50" | jq '.features | length' 2>/dev/null || echo "N/A")
echo "   Features: $ORONO_50_COUNT"
if [ "$ORONO_50_COUNT" != "N/A" ] && [ "$ORONO_50_COUNT" -gt 0 ]; then
  echo "   First geometry type: $(echo "$ORONO_50" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "2. Orono Point (-78.62245, 43.98785) - 75m radius (retry):"
ORONO_75=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=8&access_token=${MAPBOX_TOKEN}")
ORONO_75_COUNT=$(echo "$ORONO_75" | jq '.features | length' 2>/dev/null || echo "N/A")
echo "   Features: $ORONO_75_COUNT"
if [ "$ORONO_75_COUNT" != "N/A" ] && [ "$ORONO_75_COUNT" -gt 0 ]; then
  echo "   First geometry type: $(echo "$ORONO_75" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "3. Toronto CBD (-79.3832, 43.6532) - 50m radius (should return features):"
TORONTO_50=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-79.3832,43.6532.json?radius=50&limit=8&access_token=${MAPBOX_TOKEN}")
TORONTO_50_COUNT=$(echo "$TORONTO_50" | jq '.features | length' 2>/dev/null || echo "N/A")
echo "   Features: $TORONTO_50_COUNT"
if [ "$TORONTO_50_COUNT" != "N/A" ] && [ "$TORONTO_50_COUNT" -gt 0 ]; then
  echo "   First geometry type: $(echo "$TORONTO_50" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "=== Summary ==="
echo "Orono (50m): $ORONO_50_COUNT features"
echo "Orono (75m): $ORONO_75_COUNT features"
echo "Toronto (50m): $TORONTO_50_COUNT features"
echo ""
if [ "$TORONTO_50_COUNT" != "N/A" ] && [ "$TORONTO_50_COUNT" -gt 0 ]; then
  echo "✅ Toronto returns features - pipeline is working correctly"
  if [ "$ORONO_50_COUNT" = "0" ] && [ "$ORONO_75_COUNT" = "0" ]; then
    echo "⚠️  Orono has sparse coverage - proxy circles are expected"
  fi
else
  echo "❌ Toronto returns 0 features - check token or tileset"
fi

