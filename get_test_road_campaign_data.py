#!/usr/bin/env python3
"""
Get ALL data for "test road" campaign for danielmember@gmail.com
Includes: campaign details, addresses (houses), buildings, roads, sessions, metadata
"""

import json
import sys
import urllib.request
import urllib.error
from urllib.parse import urljoin

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
        
        with urllib.request.urlopen(req, timeout=30) as response:
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

def get_user_campaigns(access_token):
    """Get all campaigns for the user."""
    url = f"{SUPABASE_URL}/rest/v1/campaigns?select=*&order=created_at.desc"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"❌ Failed to get campaigns: {status}")
        print(f"Response: {body[:500]}")
        return []

def find_campaign_by_name(campaigns, name):
    """Find campaign by name (case-insensitive partial match)."""
    name_lower = name.lower()
    matches = []
    for campaign in campaigns:
        campaign_name = campaign.get("name", "") or campaign.get("title", "")
        if name_lower in campaign_name.lower():
            matches.append(campaign)
    return matches

def get_campaign_addresses(access_token, campaign_id):
    """Get all addresses (houses) for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/campaign_addresses?campaign_id=eq.{campaign_id}&select=*&order=seq.asc"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get addresses: {status}")
        return []

def get_campaign_roads(access_token, campaign_id):
    """Get all roads for a campaign using RPC."""
    url = f"{SUPABASE_URL}/rest/v1/rpc/rpc_get_campaign_roads_v2"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    data = {"p_campaign_id": campaign_id}
    
    status, body = make_request(url, "POST", headers, data)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get roads: {status}")
        return None

def get_campaign_road_metadata(access_token, campaign_id):
    """Get road metadata for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/rpc/rpc_get_campaign_road_metadata"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    data = {"p_campaign_id": campaign_id}
    
    status, body = make_request(url, "POST", headers, data)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get road metadata: {status}")
        return None

def get_campaign_sessions(access_token, campaign_id):
    """Get all sessions for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/sessions?campaign_id=eq.{campaign_id}&select=*&order=start_time.desc"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get sessions: {status}")
        return []

def get_campaign_buildings(access_token, campaign_id):
    """Get all buildings for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/buildings?campaign_id=eq.{campaign_id}&select=*"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get buildings: {status}")
        return []

def get_campaign_snapshots(access_token, campaign_id):
    """Get snapshot metadata for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/campaign_snapshots?campaign_id=eq.{campaign_id}&select=*"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get snapshots: {status}")
        return []

def get_address_statuses(access_token, campaign_id):
    """Get address statuses for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/address_statuses?campaign_id=eq.{campaign_id}&select=*"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get address statuses: {status}")
        return []

def get_field_leads(access_token, campaign_id):
    """Get field leads for a campaign."""
    url = f"{SUPABASE_URL}/rest/v1/field_leads?campaign_id=eq.{campaign_id}&select=*"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}"
    }
    
    status, body = make_request(url, "GET", headers)
    
    if status == 200:
        return json.loads(body)
    else:
        print(f"⚠️ Failed to get field leads: {status}")
        return []

def download_buildings_from_api(campaign_id):
    """Download buildings from the buildings API endpoint."""
    url = f"https://flyrpro.app/api/campaigns/{campaign_id}/buildings"
    
    status, body = make_request(url, "GET")
    
    if status == 200:
        try:
            return json.loads(body)
        except:
            return {"raw": body[:1000]}
    else:
        print(f"⚠️ Failed to get buildings from API: {status}")
        return None

def save_to_json(data, filename):
    """Save data to JSON file."""
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2, default=str)
    print(f"✅ Saved to {filename}")

def main():
    email = "danielmember@gmail.com"
    password = "megs1989"
    
    print("=" * 70)
    print("🏠 FLYR Campaign Data Extractor")
    print("=" * 70)
    print(f"Email: {email}")
    print(f"Looking for: 'test road' campaign")
    print()
    
    # Step 1: Sign in
    print("🔐 Signing in...")
    access_token, user = sign_in(email, password)
    
    if not access_token:
        print("❌ Authentication failed")
        sys.exit(1)
    
    user_id = user.get("id", "unknown")
    print(f"✅ Signed in as: {user.get('email', 'unknown')}")
    print(f"   User ID: {user_id}")
    print()
    
    # Step 2: Get all campaigns
    print("📋 Fetching campaigns...")
    campaigns = get_user_campaigns(access_token)
    print(f"✅ Found {len(campaigns)} campaign(s)")
    print()
    
    # Step 3: Find test road campaign
    print("🔍 Looking for 'test road' campaign...")
    matches = find_campaign_by_name(campaigns, "test road")
    
    if not matches:
        print("❌ No 'test road' campaign found!")
        print("\nAvailable campaigns:")
        for c in campaigns:
            name = c.get("name") or c.get("title", "Unnamed")
            print(f"  - {name} (ID: {c.get('id', 'unknown')[:8]}...)")
        sys.exit(1)
    
    print(f"✅ Found {len(matches)} match(es):")
    for i, match in enumerate(matches):
        name = match.get("name") or match.get("title", "Unnamed")
        print(f"  {i+1}. {name}")
        print(f"     ID: {match.get('id')}")
    print()
    
    # Use the first match
    campaign = matches[0]
    campaign_id = campaign.get("id")
    campaign_name = campaign.get("name") or campaign.get("title", "Unnamed")
    
    print(f"📊 Extracting ALL data for: {campaign_name}")
    print(f"   Campaign ID: {campaign_id}")
    print()
    
    # Step 4: Fetch all data
    all_data = {
        "campaign": campaign,
        "campaign_id": campaign_id,
        "extracted_at": json.dumps({}),
    }
    
    # 4.1: Campaign Addresses (HOUSES)
    print("🏠 Fetching campaign addresses (houses)...")
    addresses = get_campaign_addresses(access_token, campaign_id)
    all_data["addresses"] = addresses
    all_data["address_count"] = len(addresses)
    print(f"✅ Found {len(addresses)} address(es)")
    if addresses:
        print("   Sample addresses:")
        for addr in addresses[:3]:
            formatted = addr.get("formatted", "N/A")
            print(f"     - {formatted}")
    print()
    
    # 4.2: Campaign Roads
    print("🛣️ Fetching campaign roads...")
    roads = get_campaign_roads(access_token, campaign_id)
    road_metadata = get_campaign_road_metadata(access_token, campaign_id)
    all_data["roads"] = roads
    all_data["road_metadata"] = road_metadata
    if roads:
        features = roads.get("features", [])
        print(f"✅ Found {len(features)} road(s)")
    else:
        print("ℹ️ No roads found or RPC not available")
    print()
    
    # 4.3: Sessions
    print("📱 Fetching sessions...")
    sessions = get_campaign_sessions(access_token, campaign_id)
    all_data["sessions"] = sessions
    all_data["session_count"] = len(sessions)
    print(f"✅ Found {len(sessions)} session(s)")
    print()
    
    # 4.4: Buildings
    print("🏢 Fetching buildings...")
    buildings = get_campaign_buildings(access_token, campaign_id)
    all_data["buildings"] = buildings
    all_data["building_count"] = len(buildings)
    print(f"✅ Found {len(buildings)} building(s) in Supabase")
    
    # Also try the API endpoint
    print("🏢 Fetching buildings from API endpoint...")
    api_buildings = download_buildings_from_api(campaign_id)
    all_data["api_buildings"] = api_buildings
    if api_buildings and isinstance(api_buildings, dict):
        features = api_buildings.get("features", [])
        print(f"✅ Found {len(features)} building(s) from API")
    print()
    
    # 4.5: Campaign Snapshots
    print("📸 Fetching campaign snapshots...")
    snapshots = get_campaign_snapshots(access_token, campaign_id)
    all_data["snapshots"] = snapshots
    print(f"✅ Found {len(snapshots)} snapshot record(s)")
    print()
    
    # 4.6: Address Statuses
    print("📍 Fetching address statuses...")
    statuses = get_address_statuses(access_token, campaign_id)
    all_data["address_statuses"] = statuses
    print(f"✅ Found {len(statuses)} status record(s)")
    print()
    
    # 4.7: Field Leads
    print("👥 Fetching field leads...")
    leads = get_field_leads(access_token, campaign_id)
    all_data["field_leads"] = leads
    print(f"✅ Found {len(leads)} lead(s)")
    print()
    
    # Step 5: Save to file
    output_file = f"test_road_campaign_{campaign_id[:8]}_full_data.json"
    save_to_json(all_data, output_file)
    
    # Step 6: Summary
    print("=" * 70)
    print("📊 DATA EXTRACTION SUMMARY")
    print("=" * 70)
    print(f"Campaign: {campaign_name}")
    print(f"Campaign ID: {campaign_id}")
    print()
    print(f"🏠 Addresses (Houses): {len(addresses)}")
    print(f"🛣️ Roads: {len(roads.get('features', [])) if roads else 0}")
    print(f"📱 Sessions: {len(sessions)}")
    print(f"🏢 Buildings (Supabase): {len(buildings)}")
    if api_buildings and isinstance(api_buildings, dict):
        print(f"🏢 Buildings (API): {len(api_buildings.get('features', []))}")
    print(f"📸 Snapshots: {len(snapshots)}")
    print(f"📍 Address Statuses: {len(statuses)}")
    print(f"👥 Field Leads: {len(leads)}")
    print()
    print(f"✅ All data saved to: {output_file}")
    print()
    
    # Print first few addresses as preview
    if addresses:
        print("=" * 70)
        print("🏠 FIRST 10 HOUSES:")
        print("=" * 70)
        for i, addr in enumerate(addresses[:10]):
            print(f"\n{i+1}. {addr.get('formatted', 'N/A')}")
            print(f"   ID: {addr.get('id')}")
            print(f"   Postal Code: {addr.get('postal_code', 'N/A')}")
            print(f"   Visited: {addr.get('visited', False)}")
            print(f"   Sequence: {addr.get('seq', 'N/A')}")
            if addr.get('gers_id'):
                print(f"   GERS ID: {addr.get('gers_id')}")
            if addr.get('contact_name'):
                print(f"   Contact: {addr.get('contact_name')}")
            if addr.get('lead_status'):
                print(f"   Lead Status: {addr.get('lead_status')}")
    
    return all_data

if __name__ == "__main__":
    main()
