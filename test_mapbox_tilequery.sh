#!/bin/zsh
# Test Mapbox Tilequery API coverage
# Usage: export MAPBOX_SK='sk.your_token' && ./test_mapbox_tilequery.sh

if [ -z "$MAPBOX_SK" ]; then
  echo "❌ Error: MAPBOX_SK not set"
  echo ""
  echo "Set your token first:"
  echo "  export MAPBOX_SK='sk.your_mapbox_secret_token'"
  echo ""
  echo "Verify token:"
  echo "  echo \${#MAPBOX_SK}  # Should be > 30"
  echo "  echo \$MAPBOX_SK | sed -E 's/(sk\\.[^.]+\\.).*/\\1**** (masked)/'"
  exit 1
fi

echo "✅ Token is set (length: ${#MAPBOX_SK})"
echo ""

# Verify token format
if [[ ! "$MAPBOX_SK" =~ ^sk\. ]]; then
  echo "⚠️  Warning: Token should start with 'sk.' (not 'pk.' or 'sk-')"
fi

echo "=== Testing Orono Point (-78.62245, 43.98785) ==="
echo ""

echo "1. Buildings v3 (75m radius):"
ORONO_B3=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=10&access_token=$MAPBOX_SK")
ORONO_B3_COUNT=$(echo "$ORONO_B3" | jq '.features | length' 2>/dev/null || echo "N/A")
ORONO_B3_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=10&access_token=$MAPBOX_SK")
echo "   Features: $ORONO_B3_COUNT (HTTP: $ORONO_B3_STATUS)"
if [ "$ORONO_B3_COUNT" != "N/A" ] && [ "$ORONO_B3_COUNT" -gt 0 ]; then
  echo "   First geometry: $(echo "$ORONO_B3" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "2. Streets v8 (75m radius):"
ORONO_S8=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-78.62245,43.98785.json?layers=building&radius=75&limit=10&access_token=$MAPBOX_SK")
ORONO_S8_COUNT=$(echo "$ORONO_S8" | jq '.features | length' 2>/dev/null || echo "N/A")
ORONO_S8_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-78.62245,43.98785.json?layers=building&radius=75&limit=10&access_token=$MAPBOX_SK")
echo "   Features: $ORONO_S8_COUNT (HTTP: $ORONO_S8_STATUS)"
if [ "$ORONO_S8_COUNT" != "N/A" ] && [ "$ORONO_S8_COUNT" -gt 0 ]; then
  echo "   First geometry: $(echo "$ORONO_S8" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "=== Testing Toronto CBD (-79.3832, 43.6532) - Should return features ==="
echo ""

echo "3. Buildings v3 (75m radius):"
TORONTO_B3=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-79.3832,43.6532.json?radius=75&limit=10&access_token=$MAPBOX_SK")
TORONTO_B3_COUNT=$(echo "$TORONTO_B3" | jq '.features | length' 2>/dev/null || echo "N/A")
TORONTO_B3_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-79.3832,43.6532.json?radius=75&limit=10&access_token=$MAPBOX_SK")
echo "   Features: $TORONTO_B3_COUNT (HTTP: $TORONTO_B3_STATUS)"
if [ "$TORONTO_B3_COUNT" != "N/A" ] && [ "$TORONTO_B3_COUNT" -gt 0 ]; then
  echo "   First geometry: $(echo "$TORONTO_B3" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "4. Streets v8 (75m radius):"
TORONTO_S8=$(curl -s "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-79.3832,43.6532.json?layers=building&radius=75&limit=10&access_token=$MAPBOX_SK")
TORONTO_S8_COUNT=$(echo "$TORONTO_S8" | jq '.features | length' 2>/dev/null || echo "N/A")
TORONTO_S8_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/-79.3832,43.6532.json?layers=building&radius=75&limit=10&access_token=$MAPBOX_SK")
echo "   Features: $TORONTO_S8_COUNT (HTTP: $TORONTO_S8_STATUS)"
if [ "$TORONTO_S8_COUNT" != "N/A" ] && [ "$TORONTO_S8_COUNT" -gt 0 ]; then
  echo "   First geometry: $(echo "$TORONTO_S8" | jq -r '.features[0].geometry.type // "none"')"
fi
echo ""

echo "=== Summary ==="
echo "Orono - Buildings v3: $ORONO_B3_COUNT features (HTTP $ORONO_B3_STATUS)"
echo "Orono - Streets v8:   $ORONO_S8_COUNT features (HTTP $ORONO_S8_STATUS)"
echo "Toronto - Buildings v3: $TORONTO_B3_COUNT features (HTTP $TORONTO_B3_STATUS)"
echo "Toronto - Streets v8:   $TORONTO_S8_COUNT features (HTTP $TORONTO_S8_STATUS)"
echo ""

# Analysis
if [ "$TORONTO_B3_STATUS" = "200" ] || [ "$TORONTO_S8_STATUS" = "200" ]; then
  if [ "$TORONTO_B3_COUNT" != "N/A" ] && [ "$TORONTO_B3_COUNT" -gt 0 ]; then
    echo "✅ Toronto returns features - pipeline is working correctly"
    if [ "$ORONTO_B3_COUNT" = "0" ] && [ "$ORONTO_S8_COUNT" = "0" ]; then
      echo "⚠️  Orono has sparse coverage - proxy circles are expected"
    fi
  elif [ "$TORONTO_S8_COUNT" != "N/A" ] && [ "$TORONTO_S8_COUNT" -gt 0 ]; then
    echo "✅ Toronto returns features (streets-v8) - pipeline is working"
    echo "💡 Consider using streets-v8 if buildings-v3 has sparse coverage"
  else
    echo "⚠️  Toronto returns 0 features - check token scope or tileset coverage"
  fi
elif [ "$TORONTO_B3_STATUS" = "401" ] || [ "$TORONTO_B3_STATUS" = "403" ]; then
  echo "❌ Token authentication failed (HTTP $TORONTO_B3_STATUS)"
  echo "   Check: token starts with 'sk.', has 'tilesets:read' scope"
elif [ "$TORONTO_B3_STATUS" != "200" ]; then
  echo "⚠️  Unexpected HTTP status: $TORONTO_B3_STATUS"
fi

