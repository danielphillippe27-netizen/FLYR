#!/usr/bin/env python3
"""
Create a new test campaign with a polygon territory and provision it.
Uses the tiledecode_roads function for road data.
"""

import json
import sys
import urllib.request
import urllib.error
from datetime import datetime

# Supabase configuration
SUPABASE_URL = "https://kbvpjuaqzfdbmtaajcci.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtidnBqdWFxemZkYm10YWFqY2NpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE4NDYxMzAsImV4cCI6MjA0NzQyMjEzMH0.m-E7ZHD7r9yvZqgyhzln8GLtD0jXJpz4I16MXOl3MxE"

def make_request(url, method="GET", headers=None, data=None):
    """Make HTTP request and return response."""
    try:
        req = urllib.request.Request(url, method=method)
        if headers:
            for key, value in headers.items():
                req.add_header(key, value)
        
        if data:
            req.add_header('Content-Type', 'application/json')
            req.data = json.dumps(data).encode('utf-8')
        
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read().decode('utf-8')
            return response.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8') if e.fp else ""
        return e.code, body
    except Exception as e:
        return 0, str(e)

def sign_in(email, password):
    """Sign in with email and password to get access token."""
    url = f"{SUPABASE_URL}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json"
    }
    data = {
        "email": email,
        "password": password
    }
    
    status, body = make_request(url, "POST", headers, data)
    
    if status == 200:
        response = json.loads(body)
        return response.get("access_token"), response.get("user")
    else:
        print(f"❌ Sign in failed: {status}")
        print(f"Response: {body}")
        return None, None

def create_campaign(access_token, user_id, name, polygon_geojson, region=None):
    """Create a new campaign with territory boundary."""
    url = f"{SUPABASE_URL}/rest/v1/campaigns"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    
    data = {
        "name": name,
        "title": name,
        "owner_id": user_id,
        "territory_boundary": polygon_geojson,
        "region": region,
        "description": f"Test campaign created on {datetime.now().isoformat()}",
        "provision_status": None  # Will be set by provision
    }
    
    status, body = make_request(url, "POST", headers, data)
    
    if status in [200, 201]:
        return json.loads(body)[0]
    else:
        print(f"❌ Failed to create campaign: {status}")
        print(f"Response: {body}")
        return None

def provision_campaign(access_token, campaign_id):
    """Provision the campaign using the API."""
    url = "https://flyrpro.app/api/campaigns/provision"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    data = {
        "campaign_id": campaign_id
    }
    
    status, body = make_request(url, "POST", headers, data)
    
    if status in [200, 201]:
        return json.loads(body)
    else:
        print(f"❌ Failed to provision campaign: {status}")
        print(f"Response: {body[:500]}")
        return None

def call_tiledecode_roads(access_token, bbox):
    """Test the tiledecode_roads function."""
    url = f"{SUPABASE_URL}/functions/v1/tiledecode_roads"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    
    status, body = make_request(url, "POST", headers, bbox)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ tiledecode_roads returned: {status}")
        print(f"Response: {body[:500]}")
        return None

def main():
    # Test area: Small area in Toronto (you can change this)
    # This is a small polygon in a residential area
    test_polygon = {
        "type": "Polygon",
        "coordinates": [[
            [-79.4000, 43.6500],  # Southwest
            [-79.3950, 43.6500],  # Southeast
            [-79.3950, 43.6550],  # Northeast
            [-79.4000, 43.6550],  # Northwest
            [-79.4000, 43.6500]   # Close
        ]]
    }
    
    # Bounding box for the polygon (for tiledecode_roads)
    bbox = {
        "minLat": 43.6500,
        "minLon": -79.4000,
        "maxLat": 43.6550,
        "maxLon": -79.3950,
        "zoom": 14
    }
    
    email = "danielmember@gmail.com"
    password = "megs1989"
    campaign_name = f"Test Road Campaign {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    
    print("=" * 70)
    print("🚀 FLYR Test Campaign Creator")
    print("=" * 70)
    print(f"Email: {email}")
    print(f"Campaign: {campaign_name}")
    print()
    
    # Step 1: Sign in
    print("🔐 Signing in...")
    access_token, user = sign_in(email, password)
    
    if not access_token:
        print("❌ Authentication failed")
        sys.exit(1)
    
    user_id = user.get("id", "unknown")
    print(f"✅ Signed in as: {user.get('email', 'unknown')}")
    print()
    
    # Step 2: Test tiledecode_roads function
    print("🛣️ Testing tiledecode_roads function...")
    roads = call_tiledecode_roads(access_token, bbox)
    if roads:
        road_count = len(roads.get("features", []))
        print(f"✅ tiledecode_roads returned {road_count} road features")
    else:
        print("⚠️ tiledecode_roads test failed - continuing anyway")
    print()
    
    # Step 3: Create campaign
    print("📋 Creating campaign...")
    campaign = create_campaign(
        access_token, 
        user_id, 
        campaign_name, 
        test_polygon,
        region="ON"  # Ontario
    )
    
    if not campaign:
        print("❌ Campaign creation failed")
        sys.exit(1)
    
    campaign_id = campaign.get("id")
    print(f"✅ Campaign created!")
    print(f"   ID: {campaign_id}")
    print(f"   Name: {campaign.get('name')}")
    print()
    
    # Step 4: Provision campaign
    print("⚙️ Provisioning campaign (this may take a minute)...")
    provision_result = provision_campaign(access_token, campaign_id)
    
    if not provision_result:
        print("❌ Provisioning failed")
        print("\nYou may need to provision manually via the app")
        sys.exit(1)
    
    print(f"✅ Provisioning complete!")
    print(f"   Addresses saved: {provision_result.get('addresses_saved', 0)}")
    print(f"   Buildings saved: {provision_result.get('buildings_saved', 0)}")
    print()
    
    # Step 5: Summary
    print("=" * 70)
    print("📊 CAMPAIGN CREATED SUCCESSFULLY")
    print("=" * 70)
    print(f"Campaign ID: {campaign_id}")
    print(f"Name: {campaign_name}")
    print()
    print("🔗 Links:")
    print(f"   Dashboard: https://supabase.com/dashboard/project/kbvpjuaqzfdbmtaajcci/editor")
    print(f"   API URL: https://flyrpro.app/api/campaigns/{campaign_id}/buildings")
    print()
    print("📱 Open the FLYR iOS app to see your new campaign!")
    print()
    print("🛣️ With the new tiledecode_roads function:")
    print("   - Roads/trails will ONLY appear inside your drawn polygon")
    print("   - Full road geometry (LineStrings) from Mapbox Vector Tiles")
    print("   - Better GPS normalization along actual road paths")
    
    return campaign_id

if __name__ == "__main__":
    main()
