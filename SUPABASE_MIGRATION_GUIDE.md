# FLYR Supabase Migration Guide

## Overview

This guide will help you set up your Supabase database to work with the FLYR app's campaign and address management features.

## Step 1: Check Your Current Schema

1. Open your Supabase project dashboard
2. Go to the **SQL Editor**
3. Copy and paste the contents of `check_supabase_schema.sql`
4. Run the query to see your current database structure

This will show you:
- ✅ What's already set up correctly
- ⚠️ What needs to be added or modified
- ❌ What's missing entirely

## Step 2: Run the Migration

1. In the same SQL Editor, copy and paste the contents of `supabase_migration_setup.sql`
2. Run the migration script

This will:
- Create the required tables (`campaigns`, `campaign_addresses`)
- Set up PostGIS geometry support
- Create indexes for performance
- Set up Row Level Security (RLS) policies
- Create helper functions for the app

## Step 3: Verify the Setup

1. Run the `check_supabase_schema.sql` script again
2. All items should now show ✅ status
3. You should see "FLYR database schema setup completed successfully!" message

## What the Migration Creates

### Tables

**`campaigns` table:**
- `id` (UUID, Primary Key)
- `owner_id` (UUID, Foreign Key to auth.users)
- `title` (Text) - Campaign name
- `description` (Text) - Campaign description
- `total_flyers` (Integer) - Total number of addresses
- `scans` (Integer) - Number of completed scans
- `conversions` (Integer) - Number of conversions
- `region` (Text) - Seed query region
- `created_at` (Timestamp)
- `updated_at` (Timestamp)

**`campaign_addresses` table:**
- `id` (UUID, Primary Key)
- `campaign_id` (UUID, Foreign Key to campaigns)
- `formatted` (Text) - Full address string
- `postal_code` (Text) - Postal/ZIP code
- `source` (Text) - How address was found
- `seq` (Integer) - Sequence number
- `visited` (Boolean) - Whether address was visited
- `geom` (PostGIS Point) - Geographic coordinates
- `created_at` (Timestamp)

### Security Features

- **Row Level Security (RLS)** enabled on both tables
- **Policies** ensure users can only access their own campaigns
- **Foreign key constraints** maintain data integrity
- **Cascade deletes** clean up related data

### Performance Features

- **Indexes** on frequently queried columns
- **GIST index** on geometry column for spatial queries
- **Updated_at triggers** for automatic timestamp updates

### Helper Functions

- `add_campaign_addresses()` - Bulk insert addresses with PostGIS geometry
- `get_campaign_with_addresses()` - Fetch campaign with all addresses
- `update_campaign_progress()` - Update scan counts

## Testing the Setup

After running the migration, you can test with sample data:

```sql
-- Test campaign creation (replace with your user ID)
INSERT INTO campaigns (owner_id, title, description, total_flyers, scans, conversions, region)
VALUES (
    auth.uid(), 
    'Test Campaign', 
    'Testing the setup', 
    5, 
    0, 
    0, 
    'Toronto, ON'
);

-- Test address insertion
SELECT add_campaign_addresses(
    (SELECT id FROM campaigns WHERE title = 'Test Campaign' LIMIT 1),
    '[
        {
            "formatted": "123 Main St, Toronto, ON",
            "lon": -79.3832,
            "lat": 43.6532
        },
        {
            "formatted": "456 Queen St, Toronto, ON", 
            "lon": -79.3815,
            "lat": 43.6525
        }
    ]'::jsonb
);
```

## Troubleshooting

### If you get permission errors:
- Make sure you're logged in as the project owner
- Check that RLS policies are correctly applied

### If PostGIS isn't available:
- Contact Supabase support to enable PostGIS on your project
- Or use a different Supabase project with PostGIS enabled

### If tables already exist:
- The migration uses `CREATE TABLE IF NOT EXISTS` so it won't overwrite existing data
- Check the verification script to see what's different

## Next Steps

Once the migration is complete:

1. **Test the app** - Create a campaign in the FLYR app
2. **Check the database** - Verify data appears in Supabase
3. **Test address insertion** - Ensure addresses are stored with correct coordinates
4. **Test progress updates** - Verify scan counts update correctly

## Support

If you encounter issues:
1. Check the Supabase logs in your dashboard
2. Verify your app's Supabase configuration
3. Ensure your user is properly authenticated
4. Check that all required environment variables are set







