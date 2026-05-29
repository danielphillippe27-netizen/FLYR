BEGIN;

-- Client-generated link expiry so backend provision can re-evaluate stale device links.
ALTER TABLE public.campaign_addresses
  ADD COLUMN IF NOT EXISTS client_linked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS client_link_expires_at TIMESTAMPTZ;

UPDATE public.campaign_addresses
SET
  client_linked_at = COALESCE(client_linked_at, NOW()),
  client_link_expires_at = NOW() + INTERVAL '24 hours'
WHERE match_source = 'client_auto'
  AND client_link_expires_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_addresses_client_link_expires_at
  ON public.campaign_addresses (client_link_expires_at)
  WHERE match_source = 'client_auto';

-- Canonical link freshness metadata.
ALTER TABLE public.building_address_links
  ADD COLUMN IF NOT EXISTS source_version TEXT,
  ADD COLUMN IF NOT EXISTS matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS modified_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.building_address_links
  DROP CONSTRAINT IF EXISTS building_address_links_link_source_check;

ALTER TABLE public.building_address_links
  ADD CONSTRAINT building_address_links_link_source_check
  CHECK (link_source IN ('auto', 'auto_parcel', 'manual', 'client_auto', 'client_auto_expired'));

ALTER TABLE public.building_address_links
  DROP CONSTRAINT IF EXISTS building_address_links_match_type_check;

ALTER TABLE public.building_address_links
  ADD CONSTRAINT building_address_links_match_type_check
  CHECK (
    match_type IS NULL
    OR match_type IN (
      'containment',
      'containment_verified',
      'containment_suspect',
      'point_on_surface',
      'parcel_verified',
      'parcel_bridge',
      'proximity_verified',
      'proximity_fallback',
      'nearest_building_15m',
      'client_auto',
      'manual',
      'manual_fallback',
      'orphan'
    )
  );

CREATE OR REPLACE FUNCTION public.set_building_address_link_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.matched_at := COALESCE(NEW.matched_at, NOW());
  END IF;

  NEW.modified_at := NOW();

  IF LOWER(COALESCE(NEW.match_type, '')) IN ('manual', 'manual_fallback') THEN
    NEW.link_source := 'manual';
  ELSIF NEW.link_source IS NULL THEN
    NEW.link_source := 'auto';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_building_address_link_source
ON public.building_address_links;

CREATE TRIGGER set_building_address_link_source
BEFORE INSERT OR UPDATE OF match_type, link_source, building_id, confidence, distance_meters, source_version
ON public.building_address_links
FOR EACH ROW
EXECUTE FUNCTION public.set_building_address_link_source();

-- Canonical orphan storage used by bundle hydration and manual repair workflows.
CREATE TABLE IF NOT EXISTS public.address_orphans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
  reason TEXT,
  nearest_building_id TEXT,
  nearest_distance DOUBLE PRECISION,
  nearest_building_street TEXT,
  address_street TEXT,
  street_match_score DOUBLE PRECISION,
  suggested_buildings JSONB NOT NULL DEFAULT '[]'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending_review',
  suggested_street TEXT,
  coordinate GEOMETRY(Point, 4326),
  assigned_building_id TEXT,
  assigned_by UUID,
  assigned_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.address_orphans
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS nearest_building_id TEXT,
  ADD COLUMN IF NOT EXISTS nearest_distance DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS nearest_building_street TEXT,
  ADD COLUMN IF NOT EXISTS address_street TEXT,
  ADD COLUMN IF NOT EXISTS street_match_score DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS suggested_buildings JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending_review',
  ADD COLUMN IF NOT EXISTS suggested_street TEXT,
  ADD COLUMN IF NOT EXISTS coordinate GEOMETRY(Point, 4326),
  ADD COLUMN IF NOT EXISTS assigned_building_id TEXT,
  ADD COLUMN IF NOT EXISTS assigned_by UUID,
  ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.address_orphans
  DROP CONSTRAINT IF EXISTS address_orphans_reason_check;

ALTER TABLE public.address_orphans
  ADD CONSTRAINT address_orphans_reason_check
  CHECK (
    reason IS NULL OR reason IN (
      'no_containment',
      'no_parcel',
      'proximity_too_far',
      'proximity_ambiguous'
    )
  );

ALTER TABLE public.address_orphans
  DROP CONSTRAINT IF EXISTS address_orphans_status_check;

ALTER TABLE public.address_orphans
  ADD CONSTRAINT address_orphans_status_check
  CHECK (status IN ('pending', 'pending_review', 'ambiguous_match', 'assigned', 'ignored'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_address_orphans_campaign_address_unique
  ON public.address_orphans (campaign_id, address_id);
CREATE INDEX IF NOT EXISTS idx_address_orphans_campaign
  ON public.address_orphans (campaign_id);
CREATE INDEX IF NOT EXISTS idx_address_orphans_campaign_building
  ON public.address_orphans (campaign_id, nearest_building_id);

CREATE OR REPLACE FUNCTION public.touch_address_orphans_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS touch_address_orphans_updated_at
ON public.address_orphans;

CREATE TRIGGER touch_address_orphans_updated_at
BEFORE UPDATE ON public.address_orphans
FOR EACH ROW
EXECUTE FUNCTION public.touch_address_orphans_updated_at();

DROP FUNCTION IF EXISTS public.insert_address_orphans_batch(UUID, JSONB);

CREATE OR REPLACE FUNCTION public.insert_address_orphans_batch(
  p_campaign_id UUID,
  p_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upserted INTEGER := 0;
BEGIN
  WITH raw_rows AS (
    SELECT *
    FROM jsonb_to_recordset(
      CASE
        WHEN jsonb_typeof(p_rows) = 'array' THEN p_rows
        ELSE '[]'::jsonb
      END
    ) AS orphan_row(
      address_id UUID,
      reason TEXT,
      nearest_building_id TEXT,
      nearest_building_distance_m DOUBLE PRECISION,
      nearest_distance DOUBLE PRECISION,
      nearest_building_street TEXT,
      address_street TEXT,
      street_match_score DOUBLE PRECISION,
      suggested_buildings JSONB,
      status TEXT,
      suggested_street TEXT,
      lon DOUBLE PRECISION,
      lat DOUBLE PRECISION
    )
  ),
  clean_rows AS (
    SELECT
      p_campaign_id AS campaign_id,
      address_id,
      CASE
        WHEN reason IN ('no_containment', 'no_parcel', 'proximity_too_far', 'proximity_ambiguous') THEN reason
        ELSE NULL
      END AS reason,
      NULLIF(nearest_building_id, '') AS nearest_building_id,
      COALESCE(nearest_building_distance_m, nearest_distance) AS nearest_distance,
      NULLIF(nearest_building_street, '') AS nearest_building_street,
      NULLIF(address_street, '') AS address_street,
      street_match_score,
      COALESCE(suggested_buildings, '[]'::jsonb) AS suggested_buildings,
      CASE
        WHEN status IN ('pending', 'pending_review', 'ambiguous_match', 'assigned', 'ignored') THEN status
        ELSE 'pending_review'
      END AS status,
      NULLIF(suggested_street, '') AS suggested_street,
      CASE
        WHEN lon IS NOT NULL AND lat IS NOT NULL
        THEN ST_SetSRID(ST_MakePoint(lon, lat), 4326)
        ELSE NULL
      END AS coordinate
    FROM raw_rows
    WHERE address_id IS NOT NULL
  ),
  upserted AS (
    INSERT INTO public.address_orphans (
      campaign_id,
      address_id,
      reason,
      nearest_building_id,
      nearest_distance,
      nearest_building_street,
      address_street,
      street_match_score,
      suggested_buildings,
      status,
      suggested_street,
      coordinate
    )
    SELECT
      campaign_id,
      address_id,
      reason,
      nearest_building_id,
      nearest_distance,
      nearest_building_street,
      address_street,
      street_match_score,
      suggested_buildings,
      status,
      suggested_street,
      coordinate
    FROM clean_rows
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET
      reason = EXCLUDED.reason,
      nearest_building_id = EXCLUDED.nearest_building_id,
      nearest_distance = EXCLUDED.nearest_distance,
      nearest_building_street = EXCLUDED.nearest_building_street,
      address_street = EXCLUDED.address_street,
      street_match_score = EXCLUDED.street_match_score,
      suggested_buildings = EXCLUDED.suggested_buildings,
      status = EXCLUDED.status,
      suggested_street = EXCLUDED.suggested_street,
      coordinate = COALESCE(EXCLUDED.coordinate, address_orphans.coordinate),
      assigned_building_id = NULL,
      assigned_by = NULL,
      assigned_at = NULL
    RETURNING address_id
  )
  SELECT COUNT(*) INTO v_upserted FROM upserted;

  RETURN jsonb_build_object('upserted', v_upserted);
END;
$$;

-- Map bundle orphan columns and canonical statuses.
ALTER TABLE public.campaign_map_bundles
  ADD COLUMN IF NOT EXISTS address_orphans JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS building_orphans JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.campaign_map_bundles
  DROP CONSTRAINT IF EXISTS campaign_map_bundles_links_status_check;

UPDATE public.campaign_map_bundles
SET links_status = 'ok'
WHERE links_status = 'fresh';

ALTER TABLE public.campaign_map_bundles
  ADD CONSTRAINT campaign_map_bundles_links_status_check
  CHECK (links_status IN ('ok', 'stale_reused', 'pending_provision', 'client_fallback_required'));

CREATE OR REPLACE FUNCTION public.invalidate_campaign_map_bundle(p_campaign_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.campaign_map_bundles
  SET
    is_current = FALSE,
    expires_at = NOW(),
    updated_at = NOW()
  WHERE campaign_id = p_campaign_id
    AND is_current = TRUE;
END;
$$;

-- Source version now exposes a linker input version for auto-link freshness while
-- keeping bundle source_version sensitive to canonical link/manual changes.
CREATE OR REPLACE FUNCTION public.rpc_get_campaign_map_source_version(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign RECORD;
  v_address_count INTEGER := 0;
  v_building_count INTEGER := 0;
  v_snapshot_building_count INTEGER := 0;
  v_polished_building_count INTEGER := 0;
  v_parcel_count INTEGER := 0;
  v_link_count INTEGER := 0;
  v_manual_link_count INTEGER := 0;
  v_address_updated_at TIMESTAMPTZ;
  v_building_updated_at TIMESTAMPTZ;
  v_snapshot_updated_at TIMESTAMPTZ;
  v_polished_updated_at TIMESTAMPTZ;
  v_parcel_updated_at TIMESTAMPTZ;
  v_link_updated_at TIMESTAMPTZ;
  v_manual_link_updated_at TIMESTAMPTZ;
  v_effective_building_count INTEGER := 0;
  v_effective_building_updated_at TIMESTAMPTZ;
  v_linker_payload JSONB;
  v_bundle_payload JSONB;
BEGIN
  SELECT
    c.id,
    c.updated_at,
    c.addresses_ready_at,
    c.map_ready_at,
    c.optimized_at,
    c.territory_boundary,
    c.provision_source,
    c.provision_phase,
    c.map_mode,
    c.has_parcels,
    c.building_link_confidence
  INTO v_campaign
  FROM public.campaigns c
  WHERE c.id = p_campaign_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'source_version', md5(('missing:' || p_campaign_id::TEXT)::TEXT),
      'link_source_version', md5(('missing-linker:' || p_campaign_id::TEXT)::TEXT),
      'counts', jsonb_build_object('addresses', 0, 'buildings', 0, 'parcels', 0, 'links', 0, 'manual_links', 0),
      'updated_at', NOW()
    );
  END IF;

  SELECT COUNT(*), MAX(ca.created_at)
  INTO v_address_count, v_address_updated_at
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id;

  SELECT COUNT(*), MAX(COALESCE(b.updated_at, b.created_at))
  INTO v_building_count, v_building_updated_at
  FROM public.buildings b
  WHERE b.campaign_id = p_campaign_id;

  IF to_regclass('public.campaign_snapshots') IS NOT NULL THEN
    SELECT
      COALESCE(MAX(
        GREATEST(
          COALESCE(cs.buildings_count, 0),
          CASE
            WHEN COALESCE(cs.tile_metrics->>'campaign_buildings_count', '') ~ '^[0-9]+$'
              THEN (cs.tile_metrics->>'campaign_buildings_count')::INTEGER
            ELSE 0
          END
        )
      ), 0),
      MAX(cs.created_at)
    INTO v_snapshot_building_count, v_snapshot_updated_at
    FROM public.campaign_snapshots cs
    WHERE cs.campaign_id = p_campaign_id;
  END IF;

  IF to_regclass('public.campaign_polished_building_features') IS NOT NULL THEN
    SELECT
      COALESCE(MAX(cpbf.feature_count), 0),
      MAX(COALESCE(cpbf.updated_at, cpbf.created_at))
    INTO v_polished_building_count, v_polished_updated_at
    FROM public.campaign_polished_building_features cpbf
    WHERE cpbf.campaign_id = p_campaign_id;
  END IF;

  IF to_regclass('public.campaign_parcels') IS NOT NULL THEN
    SELECT COUNT(*), MAX(cp.created_at)
    INTO v_parcel_count, v_parcel_updated_at
    FROM public.campaign_parcels cp
    WHERE cp.campaign_id = p_campaign_id;
  END IF;

  SELECT
    COUNT(*),
    MAX(COALESCE(bal.modified_at, bal.matched_at)),
    COUNT(*) FILTER (WHERE COALESCE(bal.link_source, bal.match_type, '') = 'manual'),
    MAX(COALESCE(bal.modified_at, bal.matched_at)) FILTER (
      WHERE COALESCE(bal.link_source, bal.match_type, '') = 'manual'
    )
  INTO v_link_count, v_link_updated_at, v_manual_link_count, v_manual_link_updated_at
  FROM public.building_address_links bal
  WHERE bal.campaign_id = p_campaign_id;

  v_effective_building_count := GREATEST(
    COALESCE(v_building_count, 0),
    COALESCE(v_snapshot_building_count, 0),
    COALESCE(v_polished_building_count, 0)
  );
  v_effective_building_updated_at := GREATEST(
    COALESCE(v_building_updated_at, '-infinity'::timestamptz),
    COALESCE(v_snapshot_updated_at, '-infinity'::timestamptz),
    COALESCE(v_polished_updated_at, '-infinity'::timestamptz)
  );

  v_linker_payload := jsonb_build_object(
    'campaign_id', p_campaign_id,
    'campaign_updated_at', v_campaign.updated_at,
    'addresses_ready_at', v_campaign.addresses_ready_at,
    'map_ready_at', v_campaign.map_ready_at,
    'optimized_at', v_campaign.optimized_at,
    'territory_boundary', v_campaign.territory_boundary,
    'provision_source', v_campaign.provision_source,
    'provision_phase', v_campaign.provision_phase,
    'bundle_cache_version', 'canonical-map-bundle-v5',
    'map_mode', v_campaign.map_mode,
    'has_parcels', v_campaign.has_parcels,
    'building_link_confidence', v_campaign.building_link_confidence,
    'address_count', COALESCE(v_address_count, 0),
    'building_count', v_effective_building_count,
    'parcel_count', COALESCE(v_parcel_count, 0),
    'address_updated_at', v_address_updated_at,
    'building_updated_at', v_effective_building_updated_at,
    'snapshot_building_count', COALESCE(v_snapshot_building_count, 0),
    'snapshot_updated_at', v_snapshot_updated_at,
    'polished_building_count', COALESCE(v_polished_building_count, 0),
    'polished_updated_at', v_polished_updated_at,
    'parcel_updated_at', v_parcel_updated_at
  );

  v_bundle_payload := v_linker_payload || jsonb_build_object(
    'link_count', COALESCE(v_link_count, 0),
    'manual_link_count', COALESCE(v_manual_link_count, 0),
    'link_updated_at', v_link_updated_at,
    'manual_link_updated_at', v_manual_link_updated_at
  );

  RETURN jsonb_build_object(
    'source_version', md5(v_bundle_payload::TEXT),
    'link_source_version', md5(v_linker_payload::TEXT),
    'source', v_bundle_payload,
    'counts', jsonb_build_object(
      'addresses', COALESCE(v_address_count, 0),
      'buildings', v_effective_building_count,
      'parcels', COALESCE(v_parcel_count, 0),
      'links', COALESCE(v_link_count, 0),
      'manual_links', COALESCE(v_manual_link_count, 0),
      'bundle_cache_version', 'canonical-map-bundle-v5',
      'polished_buildings', COALESCE(v_polished_building_count, 0)
    ),
    'updated_at', GREATEST(
      COALESCE(v_campaign.updated_at, '-infinity'::timestamptz),
      COALESCE(v_campaign.addresses_ready_at, '-infinity'::timestamptz),
      COALESCE(v_campaign.map_ready_at, '-infinity'::timestamptz),
      COALESCE(v_campaign.optimized_at, '-infinity'::timestamptz),
      COALESCE(v_address_updated_at, '-infinity'::timestamptz),
      v_effective_building_updated_at,
      COALESCE(v_parcel_updated_at, '-infinity'::timestamptz),
      COALESCE(v_link_updated_at, '-infinity'::timestamptz)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_upsert_auto_building_links(
  p_campaign_id UUID,
  p_links JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER := 0;
BEGIN
  WITH raw_links AS (
    SELECT *
    FROM jsonb_to_recordset(
      CASE
        WHEN jsonb_typeof(p_links) = 'array' THEN p_links
        ELSE '[]'::jsonb
      END
    ) AS link_row(
      campaign_id UUID,
      address_id UUID,
      building_id UUID,
      match_type TEXT,
      link_source TEXT,
      confidence DOUBLE PRECISION,
      distance_meters DOUBLE PRECISION,
      building_height DOUBLE PRECISION,
      source_version TEXT
    )
  ),
  clean_links AS (
    SELECT
      p_campaign_id AS campaign_id,
      address_id,
      building_id,
      COALESCE(NULLIF(match_type, ''), 'nearest_building_15m') AS match_type,
      CASE
        WHEN link_source IN ('auto', 'auto_parcel', 'client_auto_expired') THEN link_source
        ELSE 'auto'
      END AS link_source,
      GREATEST(0.0, LEAST(1.0, COALESCE(confidence, 0.0))) AS confidence,
      distance_meters,
      building_height,
      NULLIF(source_version, '') AS source_version
    FROM raw_links
    WHERE campaign_id = p_campaign_id
      AND address_id IS NOT NULL
      AND building_id IS NOT NULL
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id,
      address_id,
      building_id,
      match_type,
      link_source,
      confidence,
      distance_meters,
      building_height,
      source_version
    )
    SELECT
      campaign_id,
      address_id,
      building_id,
      match_type,
      link_source,
      confidence,
      distance_meters,
      building_height,
      source_version
    FROM clean_links
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET
      building_id = EXCLUDED.building_id,
      match_type = EXCLUDED.match_type,
      link_source = EXCLUDED.link_source,
      confidence = EXCLUDED.confidence,
      distance_meters = EXCLUDED.distance_meters,
      building_height = EXCLUDED.building_height,
      source_version = EXCLUDED.source_version
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
    RETURNING address_id
  )
  SELECT COUNT(*)
  INTO v_inserted
  FROM upserted;

  RETURN jsonb_build_object('upserted', v_inserted);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_refresh_campaign_map_links(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_containment INTEGER := 0;
  v_parcel INTEGER := 0;
  v_nearest INTEGER := 0;
  v_total INTEGER := 0;
  v_source_version TEXT;
BEGIN
  SELECT COALESCE(
    public.rpc_get_campaign_map_source_version(p_campaign_id)->>'link_source_version',
    public.rpc_get_campaign_map_source_version(p_campaign_id)->>'source_version'
  )
  INTO v_source_version;

  SELECT COUNT(*)
  INTO v_total
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL;

  WITH expired AS (
    UPDATE public.campaign_addresses ca
    SET match_source = 'client_auto_expired'
    WHERE ca.campaign_id = p_campaign_id
      AND ca.match_source = 'client_auto'
      AND ca.client_link_expires_at < NOW()
    RETURNING ca.id
  )
  UPDATE public.building_address_links bal
  SET link_source = 'client_auto_expired'
  WHERE bal.campaign_id = p_campaign_id
    AND bal.link_source = 'client_auto'
    AND bal.address_id IN (SELECT id FROM expired);

  DELETE FROM public.building_address_links bal
  WHERE bal.campaign_id = p_campaign_id
    AND bal.link_source IN ('auto', 'auto_parcel', 'client_auto_expired');

  WITH candidates AS (
    SELECT DISTINCT ON (ca.id)
      ca.id AS address_id,
      b.id AS building_uuid,
      b.gers_id::TEXT AS building_public_id,
      'containment_verified'::TEXT AS match_type,
      'auto'::TEXT AS link_source,
      1.0::DOUBLE PRECISION AS confidence,
      0.0::DOUBLE PRECISION AS distance_meters
    FROM public.campaign_addresses ca
    JOIN public.buildings b
      ON b.campaign_id = p_campaign_id
     AND b.geom IS NOT NULL
     AND ST_Area(b.geom::geography) >= 45.0
     AND ST_Covers(b.geom, ca.geom)
    WHERE ca.campaign_id = p_campaign_id
      AND ca.geom IS NOT NULL
      AND NULLIF(BTRIM(COALESCE(b.gers_id::TEXT, '')), '') IS NOT NULL
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
    ORDER BY ca.id, ST_Area(b.geom::geography) ASC, b.id
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id, address_id, building_id, match_type, link_source,
      confidence, distance_meters, source_version
    )
    SELECT p_campaign_id, address_id, building_uuid, match_type, link_source,
      confidence, distance_meters, v_source_version
    FROM candidates
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET building_id = EXCLUDED.building_id,
        match_type = EXCLUDED.match_type,
        link_source = EXCLUDED.link_source,
        confidence = EXCLUDED.confidence,
        distance_meters = EXCLUDED.distance_meters,
        source_version = EXCLUDED.source_version
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
    RETURNING address_id
  ),
  updated_addresses AS (
    UPDATE public.campaign_addresses ca
    SET building_gers_id = candidates.building_public_id,
        match_source = 'auto',
        confidence = candidates.confidence
    FROM candidates
    JOIN upserted ON upserted.address_id = candidates.address_id
    WHERE ca.id = candidates.address_id
      AND ca.campaign_id = p_campaign_id
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
    RETURNING ca.id
  )
  SELECT COUNT(*) INTO v_containment FROM updated_addresses;

  IF to_regclass('public.campaign_parcels') IS NOT NULL THEN
    WITH unlinked_addresses AS (
      SELECT ca.*
      FROM public.campaign_addresses ca
      WHERE ca.campaign_id = p_campaign_id
        AND ca.geom IS NOT NULL
        AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
        AND NOT EXISTS (
          SELECT 1 FROM public.building_address_links bal
          WHERE bal.campaign_id = p_campaign_id
            AND bal.address_id = ca.id
        )
    ),
    candidates AS (
      SELECT DISTINCT ON (ca.id)
        ca.id AS address_id,
        b.id AS building_uuid,
        b.gers_id::TEXT AS building_public_id,
        'parcel_bridge'::TEXT AS match_type,
        'auto_parcel'::TEXT AS link_source,
        0.90::DOUBLE PRECISION AS confidence,
        ST_Distance(ca.geom::geography, b.geom::geography) AS distance_meters
      FROM unlinked_addresses ca
      JOIN public.campaign_parcels cp
        ON cp.campaign_id = p_campaign_id
       AND cp.geom IS NOT NULL
       AND ST_Covers(cp.geom, ca.geom)
      JOIN public.buildings b
        ON b.campaign_id = p_campaign_id
       AND b.geom IS NOT NULL
       AND ST_Area(b.geom::geography) >= 45.0
       AND ST_Intersects(b.geom, cp.geom)
      WHERE NULLIF(BTRIM(COALESCE(b.gers_id::TEXT, '')), '') IS NOT NULL
      ORDER BY ca.id, ST_Distance(ca.geom::geography, b.geom::geography), b.id
    ),
    upserted AS (
      INSERT INTO public.building_address_links (
        campaign_id, address_id, building_id, match_type, link_source,
        confidence, distance_meters, source_version
      )
      SELECT p_campaign_id, address_id, building_uuid, match_type, link_source,
        confidence, distance_meters, v_source_version
      FROM candidates
      ON CONFLICT (campaign_id, address_id) DO UPDATE
      SET building_id = EXCLUDED.building_id,
          match_type = EXCLUDED.match_type,
          link_source = EXCLUDED.link_source,
          confidence = EXCLUDED.confidence,
          distance_meters = EXCLUDED.distance_meters,
          source_version = EXCLUDED.source_version
      WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
      RETURNING address_id
    ),
    updated_addresses AS (
      UPDATE public.campaign_addresses ca
      SET building_gers_id = candidates.building_public_id,
          match_source = 'auto',
          confidence = candidates.confidence
      FROM candidates
      JOIN upserted ON upserted.address_id = candidates.address_id
      WHERE ca.id = candidates.address_id
        AND ca.campaign_id = p_campaign_id
        AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
      RETURNING ca.id
    )
    SELECT COUNT(*) INTO v_parcel FROM updated_addresses;
  END IF;

  WITH unlinked_addresses AS (
    SELECT ca.*
    FROM public.campaign_addresses ca
    WHERE ca.campaign_id = p_campaign_id
      AND ca.geom IS NOT NULL
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
      AND NOT EXISTS (
        SELECT 1 FROM public.building_address_links bal
        WHERE bal.campaign_id = p_campaign_id
          AND bal.address_id = ca.id
      )
  ),
  candidates AS (
    SELECT
      ca.id AS address_id,
      nearest.building_uuid,
      nearest.building_public_id,
      'nearest_building_15m'::TEXT AS match_type,
      'auto'::TEXT AS link_source,
      GREATEST(0.0, LEAST(1.0, 1.0 - (nearest.distance_meters / 15.0)))::DOUBLE PRECISION AS confidence,
      nearest.distance_meters
    FROM unlinked_addresses ca
    CROSS JOIN LATERAL (
      SELECT
        ranked.building_uuid,
        ranked.building_public_id,
        ranked.distance_meters
      FROM (
        SELECT
          b.id AS building_uuid,
          b.gers_id::TEXT AS building_public_id,
          COALESCE(b.units_count, 1) AS units_count,
          COALESCE(b.is_townhome_row, false) AS is_townhome_row,
          ST_Distance(ca.geom::geography, b.geom::geography) AS distance_meters,
          LEAD(ST_Distance(ca.geom::geography, b.geom::geography)) OVER (
            ORDER BY ST_Distance(ca.geom::geography, b.geom::geography), b.id
          ) AS next_distance_meters,
          ROW_NUMBER() OVER (
            ORDER BY ST_Distance(ca.geom::geography, b.geom::geography), b.id
          ) AS link_rank
        FROM public.buildings b
        WHERE b.campaign_id = p_campaign_id
          AND b.geom IS NOT NULL
          AND ST_Area(b.geom::geography) >= 45.0
          AND NULLIF(BTRIM(COALESCE(b.gers_id::TEXT, '')), '') IS NOT NULL
          AND ST_DWithin(ca.geom::geography, b.geom::geography, 15.0)
          AND (
            COALESCE(b.units_count, 1) > 1
            OR COALESCE(b.is_townhome_row, false)
            OR NOT EXISTS (
              SELECT 1
              FROM public.building_address_links existing
              WHERE existing.campaign_id = p_campaign_id
                AND existing.building_id = b.id::TEXT
                AND existing.address_id <> ca.id
            )
          )
      ) ranked
      WHERE ranked.link_rank = 1
        AND (
          ranked.next_distance_meters IS NULL
          OR ranked.next_distance_meters - ranked.distance_meters >= 3.0
        )
    ) nearest
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id, address_id, building_id, match_type, link_source,
      confidence, distance_meters, source_version
    )
    SELECT p_campaign_id, address_id, building_uuid, match_type, link_source,
      confidence, distance_meters, v_source_version
    FROM candidates
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET building_id = EXCLUDED.building_id,
        match_type = EXCLUDED.match_type,
        link_source = EXCLUDED.link_source,
        confidence = EXCLUDED.confidence,
        distance_meters = EXCLUDED.distance_meters,
        source_version = EXCLUDED.source_version
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
    RETURNING address_id
  ),
  updated_addresses AS (
    UPDATE public.campaign_addresses ca
    SET building_gers_id = candidates.building_public_id,
        match_source = 'auto',
        confidence = candidates.confidence
    FROM candidates
    JOIN upserted ON upserted.address_id = candidates.address_id
    WHERE ca.id = candidates.address_id
      AND ca.campaign_id = p_campaign_id
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
    RETURNING ca.id
  )
  SELECT COUNT(*) INTO v_nearest FROM updated_addresses;

  RETURN jsonb_build_object(
    'total_addresses', v_total,
    'containment', v_containment,
    'parcel', v_parcel,
    'nearest', v_nearest,
    'nearest_radius_meters', 15,
    'nearest_disambiguation_gap_meters', 3,
    'linked', v_containment + v_parcel + v_nearest,
    'source_version', v_source_version
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.auto_link_campaign_addresses(
  p_campaign_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_linked INTEGER := 0;
  v_skipped_protected INTEGER := 0;
  v_total_addresses INTEGER := 0;
  v_unlinked INTEGER := 0;
BEGIN
  v_result := public.rpc_refresh_campaign_map_links(p_campaign_id);
  v_linked := COALESCE((v_result->>'linked')::INTEGER, 0);

  SELECT COUNT(*)
  INTO v_total_addresses
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL;

  SELECT COUNT(DISTINCT bal.address_id)
  INTO v_skipped_protected
  FROM public.building_address_links bal
  INNER JOIN public.campaign_addresses ca
    ON ca.id = bal.address_id
  WHERE bal.campaign_id = p_campaign_id
    AND ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL
    AND bal.link_source IN ('manual', 'client_auto');

  SELECT COUNT(*)
  INTO v_unlinked
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.building_address_links bal
      WHERE bal.campaign_id = p_campaign_id
        AND bal.address_id = ca.id
    );

  RETURN v_result ||
    jsonb_build_object(
      'linked', v_linked,
      'skipped_manual', v_skipped_protected,
      'unlinked', v_unlinked,
      'total_addresses', v_total_addresses
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_campaign_map_bundle(
  p_campaign_id UUID,
  p_asset_signature TEXT,
  p_source_version TEXT,
  p_buildings_geojson JSONB,
  p_addresses_geojson JSONB,
  p_parcels_geojson JSONB,
  p_roads_geojson JSONB,
  p_links JSONB,
  p_address_orphans JSONB,
  p_building_orphans JSONB,
  p_display_mode_hint TEXT,
  p_counts JSONB,
  p_layer_fetched_at JSONB,
  p_links_status TEXT,
  p_built_at TIMESTAMPTZ,
  p_expires_at TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.campaign_map_bundles%ROWTYPE;
BEGIN
  UPDATE public.campaign_map_bundles
  SET is_current = FALSE
  WHERE campaign_id = p_campaign_id
    AND is_current = TRUE
    AND asset_signature <> p_asset_signature;

  INSERT INTO public.campaign_map_bundles (
    campaign_id,
    asset_signature,
    source_version,
    is_current,
    buildings_geojson,
    addresses_geojson,
    parcels_geojson,
    roads_geojson,
    links,
    address_orphans,
    building_orphans,
    display_mode_hint,
    counts,
    layer_fetched_at,
    links_status,
    built_at,
    expires_at
  )
  VALUES (
    p_campaign_id,
    p_asset_signature,
    p_source_version,
    TRUE,
    COALESCE(p_buildings_geojson, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb)),
    COALESCE(p_addresses_geojson, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb)),
    COALESCE(p_parcels_geojson, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb)),
    COALESCE(p_roads_geojson, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb)),
    COALESCE(p_links, '[]'::jsonb),
    COALESCE(p_address_orphans, '[]'::jsonb),
    COALESCE(p_building_orphans, '[]'::jsonb),
    CASE WHEN p_display_mode_hint = 'addresses' THEN 'addresses' ELSE 'buildings' END,
    COALESCE(p_counts, '{}'::jsonb),
    COALESCE(p_layer_fetched_at, '{}'::jsonb),
    CASE
      WHEN p_links_status = 'fresh' THEN 'ok'
      WHEN p_links_status IN ('ok', 'stale_reused', 'pending_provision', 'client_fallback_required') THEN p_links_status
      ELSE 'pending_provision'
    END,
    COALESCE(p_built_at, NOW()),
    COALESCE(p_expires_at, NOW())
  )
  ON CONFLICT (campaign_id, asset_signature)
  DO UPDATE SET
    source_version = EXCLUDED.source_version,
    is_current = TRUE,
    buildings_geojson = EXCLUDED.buildings_geojson,
    addresses_geojson = EXCLUDED.addresses_geojson,
    parcels_geojson = EXCLUDED.parcels_geojson,
    roads_geojson = EXCLUDED.roads_geojson,
    links = EXCLUDED.links,
    address_orphans = EXCLUDED.address_orphans,
    building_orphans = EXCLUDED.building_orphans,
    display_mode_hint = EXCLUDED.display_mode_hint,
    counts = EXCLUDED.counts,
    layer_fetched_at = EXCLUDED.layer_fetched_at,
    links_status = EXCLUDED.links_status,
    built_at = EXCLUDED.built_at,
    expires_at = EXCLUDED.expires_at
  RETURNING *
  INTO v_row;

  RETURN jsonb_build_object(
    'campaign_id', v_row.campaign_id,
    'asset_signature', v_row.asset_signature,
    'source_version', v_row.source_version,
    'is_current', v_row.is_current,
    'buildings', v_row.buildings_geojson,
    'addresses', v_row.addresses_geojson,
    'parcels', v_row.parcels_geojson,
    'roads', v_row.roads_geojson,
    'links', v_row.links,
    'address_orphans', v_row.address_orphans,
    'building_orphans', v_row.building_orphans,
    'display_mode_hint', v_row.display_mode_hint,
    'counts', v_row.counts,
    'layer_fetched_at', v_row.layer_fetched_at,
    'links_status', v_row.links_status,
    'built_at', v_row.built_at,
    'expires_at', v_row.expires_at,
    'updated_at', v_row.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_address_orphans_batch(UUID, JSONB)
TO service_role;
GRANT EXECUTE ON FUNCTION public.invalidate_campaign_map_bundle(UUID)
TO service_role;
GRANT EXECUTE ON FUNCTION public.bulk_upsert_auto_building_links(UUID, JSONB)
TO service_role;
GRANT EXECUTE ON FUNCTION public.auto_link_campaign_addresses(UUID)
TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_map_source_version(UUID)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_refresh_campaign_map_links(UUID)
TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_campaign_map_bundle(
  UUID, TEXT, TEXT, JSONB, JSONB, JSONB, JSONB, JSONB, JSONB, JSONB, TEXT, JSONB, JSONB, TEXT, TIMESTAMPTZ, TIMESTAMPTZ
)
TO service_role;

UPDATE public.campaign_map_bundles
SET
  is_current = FALSE,
  expires_at = NOW(),
  updated_at = NOW()
WHERE COALESCE(counts->>'bundle_cache_version', '') <> 'canonical-map-bundle-v5';

COMMENT ON COLUMN public.campaign_addresses.client_link_expires_at IS
'Expiry for legacy/client-generated links. Expired rows may be re-evaluated by the canonical backend linker.';

COMMENT ON COLUMN public.building_address_links.source_version IS
'Canonical linker input version used to determine whether automatic links are fresh for current campaign geometry.';

COMMENT ON FUNCTION public.invalidate_campaign_map_bundle(UUID) IS
'Marks the current hydrated map bundle stale after canonical link/manual geometry mutations.';

COMMENT ON FUNCTION public.rpc_refresh_campaign_map_links(UUID) IS
'Manual repair tool only. Normal map-bundle reads are pure hydration and must not call this automatically.';

COMMENT ON FUNCTION public.auto_link_campaign_addresses(UUID) IS
'Provision fallback linker using the canonical containment -> parcel bridge -> 15m proximity rule set.';

NOTIFY pgrst, 'reload schema';

COMMIT;
