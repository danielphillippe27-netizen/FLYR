-- Migration: Add route tracking to sessions table
-- Date: 2025-02-05
-- Description: Add campaign_id and route_data columns to support route-based sessions

-- Add campaign_id column with foreign key to campaigns table
ALTER TABLE sessions 
ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES campaigns(id) ON DELETE SET NULL;

-- Add route_data column to store optimized route information as JSONB
ALTER TABLE sessions 
ADD COLUMN IF NOT EXISTS route_data JSONB;

-- Create index on campaign_id for faster queries
CREATE INDEX IF NOT EXISTS idx_sessions_campaign_id ON sessions(campaign_id);

-- Create index on route_data for queries that need to filter by route properties
CREATE INDEX IF NOT EXISTS idx_sessions_route_data ON sessions USING GIN(route_data);

-- Add comment to campaign_id column
COMMENT ON COLUMN sessions.campaign_id IS 'Optional reference to the campaign this session was tracking';

-- Add comment to route_data column
COMMENT ON COLUMN sessions.route_data IS 'JSONB object containing optimized route with waypoints, segments, and metadata';

-- Example route_data structure:
-- {
--   "waypoints": [
--     {
--       "id": "uuid",
--       "address": "123 Main St",
--       "latitude": 43.123,
--       "longitude": -79.123,
--       "orderIndex": 0,
--       "estimatedArrivalTime": "2025-02-05T12:00:00Z"
--     }
--   ],
--   "roadSegments": [
--     {
--       "id": "uuid",
--       "fromWaypointId": "uuid",
--       "toWaypointId": "uuid",
--       "coordinatesList": [[43.123, -79.123], [43.124, -79.124]],
--       "distance": 150.5,
--       "roadClass": "residential"
--     }
--   ],
--   "totalDistance": 2500.0,
--   "estimatedDuration": 3600.0,
--   "createdAt": "2025-02-05T11:00:00Z"
-- }
