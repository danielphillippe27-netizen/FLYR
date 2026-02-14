#!/bin/bash
# Test Buildings API - Debug empty snapshots issue
# Usage: ./test_buildings_api.sh <campaign_id> [base_url]
# Example: ./test_buildings_api.sh 6824DF05-1234-5678-9ABC-DEF012345678

set -e

CAMPAIGN_ID="${1:-}"
BASE_URL="${2:-https://flyrpro.app}"

if [ -z "$CAMPAIGN_ID" ]; then
    echo "❌ Error: Campaign ID is required"
    echo "Usage: $0 <campaign_id> [base_url]"
    echo "Example: $0 6824DF05-1234-5678-9ABC-DEF012345678"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "  🏢 Buildings API Diagnostic Tool"
echo "═══════════════════════════════════════════════════════════════"
echo "Campaign ID: $CAMPAIGN_ID"
echo "Base URL:    $BASE_URL"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "⚠️  Warning: jq is not installed. Installing jq will provide better formatting."
    echo "   macOS: brew install jq"
    echo "   Ubuntu: sudo apt-get install jq"
    echo ""
    HAS_JQ=0
else
    HAS_JQ=1
fi

# Function to make API call and extract status
call_api() {
    local endpoint="$1"
    local description="$2"
    local url="${BASE_URL}${endpoint}"
    
    echo "───────────────────────────────────────────────────────────────"
    echo "  📡 $description"
    echo "  URL: $url"
    echo "───────────────────────────────────────────────────────────────"
    
    # Make the API call and capture response
    local response_file=$(mktemp)
    local http_code=$(curl -s -w "%{http_code}" -o "$response_file" "$url" 2>/dev/null || echo "000")
    
    echo "HTTP Status: $http_code"
    echo ""
    
    if [ "$http_code" = "000" ]; then
        echo "❌ Connection failed - check network or base URL"
        rm -f "$response_file"
        return 1
    fi
    
    if [ "$http_code" = "404" ]; then
        echo "❌ Not Found (404)"
        echo "   Possible causes:"
        echo "   - Campaign does not exist"
        echo "   - No snapshot exists for this campaign (not provisioned)"
        echo "   - Wrong campaign ID"
    elif [ "$http_code" = "200" ]; then
        if [ $HAS_JQ -eq 1 ]; then
            # Parse with jq
            local feature_count=$(jq '.features | length' "$response_file" 2>/dev/null || echo "null")
            local geojson_type=$(jq -r '.type' "$response_file" 2>/dev/null || echo "unknown")
            
            echo "✅ Response received"
            echo "   GeoJSON Type: $geojson_type"
            echo "   Feature Count: $feature_count"
            echo ""
            
            if [ "$feature_count" = "0" ]; then
                echo "⚠️  EMPTY FEATURES ARRAY - This is the issue!"
                echo ""
                echo "   Possible causes:"
                echo "   1. Campaign not fully provisioned (provision_status != 'ready')"
                echo "   2. Snapshot exists but contains no buildings"
                echo "   3. Territory boundary has no intersecting buildings"
                echo "   4. S3 object exists but is empty/corrupted"
                echo ""
                echo "   Raw response:"
                jq . "$response_file"
            elif [ "$feature_count" = "null" ]; then
                echo "⚠️  Invalid GeoJSON - no 'features' array found"
                echo "   Raw response:"
                cat "$response_file"
            else
                echo "✅ SUCCESS - Buildings data available"
                echo ""
                echo "   Sample feature properties:"
                jq '.features[0].properties | {gers_id, height_m, id} | with_entries(select(.value != null))' "$response_file" 2>/dev/null || echo "   (No properties to show)"
                echo ""
                echo "   Geometry types:"
                jq '[.features[].geometry.type] | unique' "$response_file" 2>/dev/null || echo "   (No geometry info)"
            fi
        else
            # No jq - just show raw response
            echo "✅ Response received (install jq for better parsing):"
            cat "$response_file"
        fi
    else
        echo "⚠️  Unexpected status code: $http_code"
        cat "$response_file"
    fi
    
    rm -f "$response_file"
    echo ""
}

# Test 1: Buildings endpoint
call_api "/api/campaigns/$CAMPAIGN_ID/buildings" "GET /api/campaigns/{id}/buildings"

# Test 2: Roads endpoint (if available)
echo "───────────────────────────────────────────────────────────────"
echo "  📡 Testing Roads endpoint (if available)"
echo "───────────────────────────────────────────────────────────────"

roads_url="${BASE_URL}/api/campaigns/$CAMPAIGN_ID/roads"
roads_response=$(mktemp)
roads_code=$(curl -s -w "%{http_code}" -o "$roads_response" "$roads_url" 2>/dev/null || echo "000")

echo "HTTP Status: $roads_code"

if [ "$roads_code" = "200" ] && [ $HAS_JQ -eq 1 ]; then
    roads_features=$(jq '.features | length' "$roads_response" 2>/dev/null || echo "null")
    echo "Roads features: $roads_features"
    if [ "$roads_features" != "null" ] && [ "$roads_features" -gt 0 ]; then
        echo "✅ Roads data exists - snapshot set is present"
    else
        echo "ℹ️  Roads endpoint returned empty (roads may not be provisioned)"
    fi
elif [ "$roads_code" = "404" ]; then
    echo "ℹ️  Roads endpoint not found (optional endpoint)"
else
    echo "Response: $(cat "$roads_response" | head -c 200)"
fi
rm -f "$roads_response"
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════"
echo "  📋 Summary & Next Steps"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "If buildings returned 0 features but roads exist:"
echo "  → The campaign_snapshots row exists (roads work)"
echo "  → But buildings snapshot file may be empty or missing"
echo ""
echo "If both return 404:"
echo "  → Campaign may not be provisioned yet"
echo "  → Check provision_status in Supabase"
echo ""
echo "To check campaign status directly in Supabase:"
echo "  SELECT id, provision_status, territory_boundary IS NOT NULL as has_boundary"
echo "  FROM campaigns WHERE id = '$CAMPAIGN_ID';"
echo ""
echo "To check snapshot metadata:"
echo "  SELECT campaign_id, buildings_key, addresses_key, created_at"
echo "  FROM campaign_snapshots WHERE campaign_id = '$CAMPAIGN_ID';"
echo ""
