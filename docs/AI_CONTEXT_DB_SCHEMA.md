# FLYR Database Schema

Reference for Supabase Postgres + PostGIS database schema. All tables use UUID primary keys and have Row Level Security (RLS) enabled.

## Core Tables

### Campaigns

**`campaigns`** - Campaign definitions
- `id` UUID PRIMARY KEY
- `owner_id` UUID REFERENCES auth.users (FK, NOT NULL)
- `name` TEXT
- `type` TEXT (flyer, doorKnock, event, survey, gift, popBy, openHouse)
- `address_source` TEXT (closestHome, importList, map, sameStreet)
- `total_flyers` INT
- `scans` INT
- `conversions` INT
- `created_at` TIMESTAMPTZ DEFAULT now()
- `updated_at` TIMESTAMPTZ DEFAULT now()

**ON DELETE**: CASCADE to campaign_addresses, buildings, roads, contacts, sessions

---

### Addresses

**`campaign_addresses`** - Addresses within campaigns
- `id` UUID PRIMARY KEY
- `campaign_id` UUID REFERENCES campaigns(id) ON DELETE CASCADE
- `geom` GEOMETRY(Point, 4326) (lat/lon)
- `formatted` TEXT (formatted address string)
- `postal_code` TEXT
- `city` TEXT
- `province` TEXT
- `country` TEXT
- `gers_id` TEXT (unique identifier for matching)
- `created_at` TIMESTAMPTZ DEFAULT now()

**Indexes**: GIST on geom, btree on campaign_id, btree on gers_id

**`addresses_master`** - Unified master address list (all sources)
- `id` UUID PRIMARY KEY
- `source` TEXT (durham_open, osm, user, fallback)
- `geom` GEOMETRY(Point, 4326)
- `formatted` TEXT
- `postal_code` TEXT
- `city` TEXT
- `province` TEXT
- `confidence` FLOAT (0.0-1.0, higher = better quality)
- `created_at` TIMESTAMPTZ

**Source Priority**: durham_open (0.95) > osm (0.85) > user (0.80) > fallback (0.70)

**`addresses_unified`** - View over addresses_master for RPC compatibility

---

### Buildings

**`buildings`** - Building geometries
- `id` UUID PRIMARY KEY
- `campaign_id` UUID REFERENCES campaigns(id) ON DELETE CASCADE
- `geom` GEOMETRY(MultiPolygon, 4326)
- `height_m` FLOAT (height in meters)
- `is_townhome_row` BOOLEAN
- `units_count` INT
- `gers_id` TEXT
- `created_at` TIMESTAMPTZ

**Indexes**: GIST on geom, btree on campaign_id

**`building_polygons`** - Cached building polygons (address → building mapping)
- `id` UUID PRIMARY KEY
- `address_id` UUID REFERENCES campaign_addresses(id) UNIQUE
- `geom` JSONB (GeoJSON geometry object)
- `geom_geom` GEOMETRY(MultiPolygon, 4326) (PostGIS geometry)
- `area_m2` FLOAT
- `centroid` GEOMETRY(Point, 4326)
- `bbox` FLOAT[] (bounding box: [minLon, minLat, maxLon, maxLat])
- `method` TEXT (contains, nearby, largest)
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

**Relationship**: 1:1 with campaign_addresses (one building per address)

**`building_address_links`** - Many-to-many links (legacy)
- `building_id` UUID REFERENCES buildings(id)
- `address_id` UUID REFERENCES campaign_addresses(id)
- `campaign_id` UUID REFERENCES campaigns(id)
- `method` TEXT

**`building_stats`** - Building statistics (updated by triggers)
- `id` UUID PRIMARY KEY
- `building_id` UUID REFERENCES buildings(id)
- `scans_today` INT DEFAULT 0
- `scans_total` INT DEFAULT 0
- `last_scan_at` TIMESTAMPTZ
- `status` TEXT (none, no_answer, delivered, talked, appointment, etc.)

---

### Roads

**`roads`** - Road geometries
- `id` UUID PRIMARY KEY
- `campaign_id` UUID REFERENCES campaigns(id) ON DELETE CASCADE
- `geom` GEOMETRY(LineString, 4326)
- `name` TEXT
- `road_class` TEXT (primary, secondary, tertiary, residential, service)
- `gers_id` TEXT
- `created_at` TIMESTAMPTZ

**Indexes**: GIST on geom, btree on campaign_id

---

### Address Statuses

**`address_statuses`** - Visit status tracking
- `id` UUID PRIMARY KEY
- `address_id` UUID REFERENCES campaign_addresses(id) ON DELETE CASCADE
- `campaign_id` UUID REFERENCES campaigns(id) ON DELETE CASCADE
- `user_id` UUID REFERENCES auth.users
- `status` TEXT (enum: none, no_answer, delivered, talked, appointment, do_not_knock, future_seller, hot_lead)
- `visited_at` TIMESTAMPTZ
- `notes` TEXT
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

**Status Enum Values**:
- `none` - Not visited
- `no_answer` - Knocked, no answer
- `delivered` - Flyer delivered
- `talked` - Had conversation
- `appointment` - Appointment booked
- `do_not_knock` - Do not contact
- `future_seller` - Future seller lead
- `hot_lead` - Hot lead

**Indexes**: btree on (address_id, campaign_id), btree on user_id

---

### QR Codes

**`qr_codes`** - QR code definitions
- `id` UUID PRIMARY KEY
- `slug` TEXT UNIQUE (short URL identifier, e.g., "abc123")
- `address_id` UUID REFERENCES campaign_addresses(id)
- `campaign_id` UUID REFERENCES campaigns(id)
- `farm_id` UUID REFERENCES farms(id)
- `batch_id` UUID REFERENCES batches(id)
- `landing_page_id` UUID REFERENCES landing_pages(id)
- `qr_type` TEXT (address, batch, custom)
- `custom_url` TEXT
- `created_at` TIMESTAMPTZ

**`batches`** - QR batch configurations
- `id` UUID PRIMARY KEY
- `owner_id` UUID REFERENCES auth.users
- `name` TEXT
- `qr_type` TEXT
- `landing_page_id` UUID REFERENCES landing_pages(id)
- `custom_url` TEXT
- `export_format` TEXT (png, svg, pdf, thermal)
- `created_at` TIMESTAMPTZ

**`qr_code_scans`** - Scan tracking
- `id` UUID PRIMARY KEY
- `qr_code_id` UUID REFERENCES qr_codes(id)
- `address_id` UUID REFERENCES campaign_addresses(id)
- `scanned_at` TIMESTAMPTZ DEFAULT now()
- `device_info` TEXT
- `user_agent` TEXT
- `ip_address` INET

---

### Contacts & CRM

**`contacts`** - CRM contacts
- `id` UUID PRIMARY KEY
- `user_id` UUID REFERENCES auth.users
- `campaign_id` UUID REFERENCES campaigns(id)
- `farm_id` UUID REFERENCES farms(id)
- `full_name` TEXT
- `phone` TEXT
- `email` TEXT
- `address` TEXT
- `status` TEXT (hot, warm, cold, new)
- `last_contacted` TIMESTAMPTZ
- `notes` TEXT
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

**`contact_activities`** - Contact activity log
- `id` UUID PRIMARY KEY
- `contact_id` UUID REFERENCES contacts(id) ON DELETE CASCADE
- `user_id` UUID REFERENCES auth.users
- `type` TEXT (knock, call, flyer, note, text, email, meeting)
- `notes` TEXT
- `created_at` TIMESTAMPTZ

---

### Farms

**`farms`** - Farm areas
- `id` UUID PRIMARY KEY
- `owner_id` UUID REFERENCES auth.users
- `name` TEXT
- `polygon` GEOMETRY(Polygon, 4326)
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

**`farm_touches`** - Planned farm touches
- `id` UUID PRIMARY KEY
- `farm_id` UUID REFERENCES farms(id) ON DELETE CASCADE
- `date` DATE
- `type` TEXT (flyer, door_knock, event, newsletter, ad, custom)
- `completed` BOOLEAN DEFAULT false
- `campaign_id` UUID REFERENCES campaigns(id)
- `batch_id` UUID REFERENCES batches(id)
- `created_at` TIMESTAMPTZ

---

### Sessions

**`sessions`** - Session/workout tracking
- `id` UUID PRIMARY KEY
- `user_id` UUID REFERENCES auth.users
- `campaign_id` UUID REFERENCES campaigns(id)
- `start_time` TIMESTAMPTZ
- `end_time` TIMESTAMPTZ
- `distance_meters` FLOAT
- `goal_type` TEXT (time, distance, doors)
- `goal_amount` FLOAT
- `path_geojson` JSONB (LineString GeoJSON)
- `route_data` JSONB (optimized route data)
- `created_at` TIMESTAMPTZ

---

### User Stats

**`user_stats`** - User performance metrics
- `id` UUID PRIMARY KEY
- `user_id` UUID REFERENCES auth.users UNIQUE
- `flyers` INT DEFAULT 0
- `conversations` INT DEFAULT 0
- `leads` INT DEFAULT 0
- `distance_meters` FLOAT DEFAULT 0
- `current_streak` INT DEFAULT 0
- `longest_streak` INT DEFAULT 0
- `last_activity` DATE
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

**Updated by triggers** on: qr_code_scans, address_statuses, sessions

**`user_settings`** - User preferences
- `id` UUID PRIMARY KEY
- `user_id` UUID REFERENCES auth.users UNIQUE
- `dark_mode` BOOLEAN DEFAULT false
- `exclude_weekends` BOOLEAN DEFAULT false
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

**`user_integrations`** - OAuth integrations
- `id` UUID PRIMARY KEY
- `user_id` UUID REFERENCES auth.users
- `provider` TEXT (hubspot, monday, fub, kvcore, zapier)
- `access_token` TEXT
- `refresh_token` TEXT
- `expires_at` TIMESTAMPTZ
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

---

## Geometry Types

- **Point**: Addresses, address centroids (lat/lon)
- **Polygon/MultiPolygon**: Buildings, farms
- **LineString**: Roads, session paths

## PostGIS Conventions

- **SRID**: 4326 (WGS84 lat/lon)
- **Geography Type**: Used for distance calculations in meters
- **Spatial Indexes**: GIST indexes on all geometry columns
- **JSON Serialization**: `ST_AsGeoJSON(geom, 6)::jsonb` for GeoJSON output

## Foreign Key Cascade Rules

- **campaigns → campaign_addresses**: ON DELETE CASCADE
- **campaigns → buildings**: ON DELETE CASCADE
- **campaigns → roads**: ON DELETE CASCADE
- **campaigns → contacts**: ON DELETE CASCADE
- **campaigns → sessions**: ON DELETE CASCADE
- **campaign_addresses → address_statuses**: ON DELETE CASCADE
- **contacts → contact_activities**: ON DELETE CASCADE
- **farms → farm_touches**: ON DELETE CASCADE

## Indexes Strategy

- **Spatial**: GIST on all geometry columns
- **Foreign Keys**: btree on all FK columns
- **Lookups**: btree on frequently queried columns (slug, gers_id, user_id)
- **Composite**: Multi-column indexes for common query patterns
- **Partial**: WHERE clauses for filtered indexes

## Timestamp Conventions

- **created_at**: Record creation timestamp (DEFAULT now())
- **updated_at**: Last update timestamp (trigger-based auto-update)
- **visited_at**: Specific event timestamp
- **last_contacted**: Last contact timestamp (trigger-based)
