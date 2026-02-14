#!/usr/bin/env python3
"""
Test Buildings API - Debug empty snapshots issue
Usage: python3 test_buildings_api.py <campaign_id> [--base-url URL] [--verbose]

Examples:
    python3 test_buildings_api.py 6824DF05-1234-5678-9ABC-DEF012345678
    python3 test_buildings_api.py 6824DF05-1234-5678-9ABC-DEF012345678 --verbose
    python3 test_buildings_api.py 6824DF05-1234-5678-9ABC-DEF012345678 --base-url http://localhost:3000
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from urllib.parse import urljoin
from datetime import datetime


def color(text, color_code):
    """Add ANSI color codes to text."""
    return f"\033[{color_code}m{text}\033[0m"


def red(text): return color(text, 91)
def green(text): return color(text, 92)
def yellow(text): return color(text, 93)
def blue(text): return color(text, 94)
def magenta(text): return color(text, 95)
def cyan(text): return color(text, 96)


def print_header(title):
    print(cyan("═" * 65))
    print(cyan(f"  {title}"))
    print(cyan("═" * 65))


def print_section(title):
    print(blue("─" * 65))
    print(blue(f"  📡 {title}"))
    print(blue("─" * 65))


def make_request(url, timeout=30):
    """Make HTTP request and return (status_code, body, error)."""
    try:
        req = urllib.request.Request(url, method='GET')
        req.add_header('Accept', 'application/json')
        
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read().decode('utf-8')
            return response.status, body, None
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8') if e.fp else ""
        return e.code, body, None
    except urllib.error.URLError as e:
        return 0, "", str(e.reason)
    except Exception as e:
        return 0, "", str(e)


def analyze_geojson(data, verbose=False):
    """Analyze GeoJSON FeatureCollection and return summary."""
    if not isinstance(data, dict):
        return {"error": "Response is not a JSON object"}
    
    geojson_type = data.get('type', 'unknown')
    features = data.get('features', None)
    
    if features is None:
        return {"error": "Missing 'features' array", "type": geojson_type}
    
    if not isinstance(features, list):
        return {"error": "'features' is not an array", "type": geojson_type}
    
    feature_count = len(features)
    
    result = {
        "type": geojson_type,
        "feature_count": feature_count,
        "empty": feature_count == 0
    }
    
    if feature_count > 0:
        # Analyze first feature
        first = features[0]
        geom_type = first.get('geometry', {}).get('type', 'unknown') if isinstance(first.get('geometry'), dict) else 'none'
        props = first.get('properties', {}) if isinstance(first.get('properties'), dict) else {}
        
        result['first_feature'] = {
            "geometry_type": geom_type,
            "has_id": 'id' in first,
            "has_gers_id": 'gers_id' in props,
            "sample_properties": {k: v for k, v in list(props.items())[:5]}
        }
        
        # Count geometry types
        geom_types = {}
        for f in features:
            gt = f.get('geometry', {}).get('type', 'unknown') if isinstance(f.get('geometry'), dict) else 'none'
            geom_types[gt] = geom_types.get(gt, 0) + 1
        result['geometry_types'] = geom_types
        
        # Check for gers_id in all features
        gers_count = sum(1 for f in features if isinstance(f.get('properties'), dict) and f['properties'].get('gers_id'))
        result['features_with_gers_id'] = gers_count
    
    if verbose and feature_count > 0:
        result['sample_feature'] = features[0] if feature_count > 0 else None
    
    return result


def test_buildings_endpoint(base_url, campaign_id, verbose=False):
    """Test the buildings API endpoint."""
    endpoint = f"/api/campaigns/{campaign_id}/buildings"
    url = urljoin(base_url, endpoint)
    
    print_section(f"GET {endpoint}")
    print(f"Full URL: {url}\n")
    
    status, body, error = make_request(url)
    
    print(f"HTTP Status: {status if status else 'Connection Failed'}")
    
    if error:
        print(red(f"❌ Connection Error: {error}"))
        return {"status": "error", "error": error}
    
    if status == 404:
        print(red("❌ Not Found (404)"))
        print("\nPossible causes:")
        print("  • Campaign does not exist")
        print("  • No snapshot exists for this campaign (not provisioned)")
        print("  • Wrong campaign ID format")
        return {"status": "not_found", "feature_count": 0}
    
    if status != 200:
        print(yellow(f"⚠️  Unexpected status: {status}"))
        print(f"Response: {body[:500]}")
        return {"status": "error", "http_status": status}
    
    # Parse JSON
    try:
        data = json.loads(body)
    except json.JSONDecodeError as e:
        print(red(f"❌ Invalid JSON response: {e}"))
        print(f"Raw response (first 500 chars): {body[:500]}")
        return {"status": "parse_error"}
    
    # Analyze GeoJSON
    analysis = analyze_geojson(data, verbose)
    
    if "error" in analysis:
        print(red(f"❌ Invalid GeoJSON: {analysis['error']}"))
        print(f"Type: {analysis.get('type', 'unknown')}")
        if verbose:
            print(f"\nRaw response:\n{json.dumps(data, indent=2)[:2000]}")
        return {"status": "invalid_geojson", "error": analysis['error']}
    
    print(green(f"✅ Valid GeoJSON FeatureCollection"))
    print(f"   Feature Count: {analysis['feature_count']}")
    
    if analysis['empty']:
        print(red("\n⚠️  EMPTY FEATURES ARRAY - This is the issue!"))
        print("\nPossible causes:")
        print("  1. Campaign not fully provisioned (provision_status != 'ready')")
        print("  2. Snapshot exists but contains no buildings")
        print("  3. Territory boundary has no intersecting buildings")
        print("  4. S3 object exists but is empty/corrupted")
        print("  5. Lambda query returned no results for the polygon")
        
        if verbose:
            print(f"\nRaw response:\n{json.dumps(data, indent=2)}")
        
        return {"status": "empty", "feature_count": 0}
    
    # Success - has features
    print(green(f"\n✅ SUCCESS - {analysis['feature_count']} building(s) found"))
    
    first = analysis.get('first_feature', {})
    print(f"\nFirst feature:")
    print(f"  Geometry type: {first.get('geometry_type', 'unknown')}")
    print(f"  Has id: {first.get('has_id', False)}")
    print(f"  Has gers_id: {first.get('has_gers_id', False)}")
    
    if 'geometry_types' in analysis:
        print(f"\nGeometry type distribution:")
        for gt, count in analysis['geometry_types'].items():
            print(f"  {gt}: {count}")
    
    if 'features_with_gers_id' in analysis:
        print(f"\nFeatures with gers_id: {analysis['features_with_gers_id']}/{analysis['feature_count']}")
    
    if verbose and 'sample_feature' in analysis:
        print(f"\nSample feature:\n{json.dumps(analysis['sample_feature'], indent=2)}")
    
    return {"status": "success", "feature_count": analysis['feature_count']}


def test_roads_endpoint(base_url, campaign_id):
    """Test the roads API endpoint (optional)."""
    endpoint = f"/api/campaigns/{campaign_id}/roads"
    url = urljoin(base_url, endpoint)
    
    print_section(f"GET {endpoint} (optional)")
    
    status, body, error = make_request(url)
    
    print(f"HTTP Status: {status if status else 'Connection Failed'}")
    
    if error:
        print(yellow(f"⚠️  Connection error: {error}"))
        return {"status": "error"}
    
    if status == 404:
        print("ℹ️  Roads endpoint not found (optional, may not be implemented)")
        return {"status": "not_found"}
    
    if status == 200:
        try:
            data = json.loads(body)
            features = data.get('features', [])
            print(f"Roads features: {len(features)}")
            if len(features) > 0:
                print(green("✅ Roads data exists - snapshot set is present"))
                return {"status": "success", "feature_count": len(features)}
            else:
                print("ℹ️  Roads endpoint returned empty")
                return {"status": "empty", "feature_count": 0}
        except json.JSONDecodeError:
            print("⚠️  Invalid JSON from roads endpoint")
            return {"status": "parse_error"}
    
    print(f"Response: {body[:200]}")
    return {"status": "error", "http_status": status}


def print_summary(buildings_result, roads_result, campaign_id):
    """Print summary and next steps."""
    print_header("Summary & Next Steps")
    
    print("\nBuildings API Result:")
    status = buildings_result.get('status')
    
    if status == 'success':
        print(green(f"  ✅ {buildings_result['feature_count']} building(s) available"))
    elif status == 'empty':
        print(red("  ❌ Buildings snapshot is EMPTY"))
    elif status == 'not_found':
        print(yellow("  ⚠️  Buildings snapshot not found (404)"))
    else:
        print(red(f"  ❌ Error: {buildings_result.get('error', status)}"))
    
    print("\nRoads API Result:")
    rstatus = roads_result.get('status')
    if rstatus == 'success':
        print(green(f"  ✅ {roads_result['feature_count']} road(s) available - snapshot set exists"))
    elif rstatus == 'empty':
        print("  ℹ️  Roads empty but endpoint exists")
    elif rstatus == 'not_found':
        print("  ℹ️  Roads endpoint not available (optional)")
    else:
        print("  ⚠️  Could not verify roads")
    
    print("\n" + cyan("─" * 65))
    
    # Diagnostic guidance
    if status == 'empty' and rstatus == 'success':
        print(yellow("\n🔍 DIAGNOSIS: Buildings empty but roads exist"))
        print("""
This means:
  • The campaign_snapshots row EXISTS (roads work)
  • But the buildings snapshot file is empty or corrupted

Check in Supabase:
  SELECT * FROM campaign_snapshots 
  WHERE campaign_id = '<campaign_id>';

Check S3 directly:
  aws s3 ls s3://flyr-snapshots/campaigns/<campaign_id>/
  aws s3 cp s3://flyr-snapshots/campaigns/<campaign_id>/buildings.geojson.gz - | gunzip | jq '.features | length'
""")
    elif status == 'empty' and rstatus == 'not_found':
        print(yellow("\n🔍 DIAGNOSIS: Buildings empty, roads endpoint unavailable"))
        print("""
This means:
  • Campaign may exist but not be fully provisioned
  • Or snapshot exists but both buildings and roads are empty

Check in Supabase:
  SELECT id, provision_status, territory_boundary IS NOT NULL as has_boundary
  FROM campaigns WHERE id = '<campaign_id>';
  
If provision_status != 'ready':
  → Campaign needs to be provisioned first
  
If provision_status = 'ready':
  → Check campaign_snapshots table for metadata
""")
    elif status == 'not_found':
        print(yellow("\n🔍 DIAGNOSIS: Buildings endpoint returned 404"))
        print("""
This means:
  • Campaign does not exist, OR
  • Campaign exists but has no snapshot metadata, OR
  • Wrong campaign ID format

Check in Supabase:
  SELECT id, provision_status 
  FROM campaigns WHERE id = '<campaign_id>';

If no rows found:
  → Verify the campaign ID is correct
  
If found but provision_status is null/pending:
  → Campaign needs provisioning (POST /api/campaigns/provision)
""")
    
    print(cyan("─" * 65))
    print("\nUseful Supabase queries:")
    print("  -- Check campaign status")
    print(f"  SELECT id, provision_status, territory_boundary IS NOT NULL as has_boundary")
    print(f"  FROM campaigns WHERE id = '{campaign_id}';\n")
    
    print("  -- Check snapshot metadata")
    print(f"  SELECT campaign_id, buildings_key, addresses_key, created_at")
    print(f"  FROM campaign_snapshots WHERE campaign_id = '{campaign_id}';\n")
    
    print("  -- Check provision logs (if available)")
    print(f"  SELECT * FROM provision_logs WHERE campaign_id = '{campaign_id}' ORDER BY created_at DESC LIMIT 5;")


def main():
    parser = argparse.ArgumentParser(
        description='Test Buildings API - Debug empty snapshots issue',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 6824DF05-1234-5678-9ABC-DEF012345678
  %(prog)s 6824DF05-1234-5678-9ABC-DEF012345678 --verbose
  %(prog)s 6824DF05-1234-5678-9ABC-DEF012345678 --base-url http://localhost:3000
        """
    )
    parser.add_argument('campaign_id', help='Campaign UUID to test')
    parser.add_argument('--base-url', default='https://flyrpro.app',
                       help='Base URL for API (default: https://flyrpro.app)')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Show verbose output including full responses')
    
    args = parser.parse_args()
    
    print_header("🏢 Buildings API Diagnostic Tool")
    print(f"Campaign ID: {args.campaign_id}")
    print(f"Base URL:    {args.base_url}")
    print(f"Time:        {datetime.now().isoformat()}\n")
    
    # Test buildings
    buildings_result = test_buildings_endpoint(
        args.base_url, 
        args.campaign_id, 
        args.verbose
    )
    
    print()
    
    # Test roads
    roads_result = test_roads_endpoint(args.base_url, args.campaign_id)
    
    print()
    
    # Print summary
    print_summary(buildings_result, roads_result, args.campaign_id)


if __name__ == '__main__':
    main()
