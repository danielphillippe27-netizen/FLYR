-- Gold reference tables: ref_buildings_gold, ref_addresses_gold
-- Exact schemas matching production (safe to re-apply; all IF NOT EXISTS).
-- Also adds Gold link columns to campaign_addresses.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. ref_buildings_gold
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ref_buildings_gold (
    idx                   SERIAL,
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id             TEXT,
    source_file           TEXT,
    source_url            TEXT,
    source_date           DATE,
    external_id           TEXT,
    parcel_id             TEXT,
    geom                  GEOMETRY(MultiPolygon, 4326),
    centroid              GEOMETRY(Point, 4326),
    area_sqm              NUMERIC DEFAULT 0,
    height_m              NUMERIC,
    floors                INTEGER,
    year_built            INTEGER,
    building_type         TEXT,
    subtype               TEXT,
    primary_address       TEXT,
    primary_street_number TEXT,
    primary_street_name   TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ref_buildings_gold_geom
    ON public.ref_buildings_gold USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_ref_buildings_gold_centroid
    ON public.ref_buildings_gold USING GIST(centroid);
CREATE INDEX IF NOT EXISTS idx_ref_buildings_gold_source_id
    ON public.ref_buildings_gold(source_id);

ALTER TABLE public.ref_buildings_gold ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ref_buildings_gold_service_role" ON public.ref_buildings_gold;
CREATE POLICY "ref_buildings_gold_service_role"
    ON public.ref_buildings_gold FOR ALL
    USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "ref_buildings_gold_authenticated_select" ON public.ref_buildings_gold;
CREATE POLICY "ref_buildings_gold_authenticated_select"
    ON public.ref_buildings_gold FOR SELECT TO authenticated
    USING (true);

-- ---------------------------------------------------------------------------
-- 2. ref_addresses_gold
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ref_addresses_gold (
    idx                      SERIAL,
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id                TEXT,
    source_file              TEXT,
    source_url               TEXT,
    source_date              DATE,
    street_number            TEXT,
    street_name              TEXT,
    unit                     TEXT,
    city                     TEXT,
    zip                      TEXT,
    province                 TEXT,
    country                  TEXT,
    geom                     GEOMETRY(Point, 4326),
    address_type             TEXT,
    precision                TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    street_number_normalized INTEGER,
    street_name_normalized   TEXT,
    zip_normalized           TEXT
);

CREATE INDEX IF NOT EXISTS idx_ref_addresses_gold_geom
    ON public.ref_addresses_gold USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_ref_addresses_gold_province
    ON public.ref_addresses_gold(province);
CREATE INDEX IF NOT EXISTS idx_ref_addresses_gold_source_id
    ON public.ref_addresses_gold(source_id);
CREATE INDEX IF NOT EXISTS idx_ref_addresses_gold_street
    ON public.ref_addresses_gold(street_name_normalized, street_number_normalized);

ALTER TABLE public.ref_addresses_gold ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ref_addresses_gold_service_role" ON public.ref_addresses_gold;
CREATE POLICY "ref_addresses_gold_service_role"
    ON public.ref_addresses_gold FOR ALL
    USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "ref_addresses_gold_authenticated_select" ON public.ref_addresses_gold;
CREATE POLICY "ref_addresses_gold_authenticated_select"
    ON public.ref_addresses_gold FOR SELECT TO authenticated
    USING (true);

-- ---------------------------------------------------------------------------
-- 3. Extend campaign_addresses with Gold link columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.campaign_addresses
    ADD COLUMN IF NOT EXISTS building_id   UUID REFERENCES public.ref_buildings_gold(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS match_source  TEXT CHECK (match_source IN ('gold_exact', 'gold_proximity', 'silver')),
    ADD COLUMN IF NOT EXISTS confidence    FLOAT CHECK (confidence >= 0 AND confidence <= 1);

CREATE INDEX IF NOT EXISTS idx_campaign_addresses_building_id
    ON public.campaign_addresses(building_id)
    WHERE building_id IS NOT NULL;

COMMIT;
