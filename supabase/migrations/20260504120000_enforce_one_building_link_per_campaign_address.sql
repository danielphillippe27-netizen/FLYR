-- Tighten building-address linking so one campaign address cannot be attached
-- to multiple buildings at the same time.

ALTER TABLE public.building_address_links
  ADD COLUMN IF NOT EXISTS match_type TEXT,
  ADD COLUMN IF NOT EXISTS confidence DOUBLE PRECISION CHECK (confidence >= 0 AND confidence <= 1),
  ADD COLUMN IF NOT EXISTS distance_meters DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS street_match_score DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS building_area_sqm DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS building_class TEXT,
  ADD COLUMN IF NOT EXISTS building_height DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS is_multi_unit BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS unit_count INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS unit_arrangement TEXT,
  ADD COLUMN IF NOT EXISTS overture_release TEXT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'building_address_links'
      AND column_name = 'method'
  ) THEN
    EXECUTE '
      UPDATE public.building_address_links
      SET match_type = COALESCE(match_type, LOWER(method))
      WHERE match_type IS NULL
    ';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'building_address_links'
      AND column_name = 'confidence_score'
  ) THEN
    EXECUTE '
      UPDATE public.building_address_links
      SET confidence = COALESCE(confidence, confidence_score::double precision)
      WHERE confidence IS NULL
    ';
  END IF;
END $$;

WITH ranked_links AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY campaign_id, address_id
      ORDER BY
        CASE LOWER(COALESCE(match_type, ''))
          WHEN 'manual' THEN 60
          WHEN 'containment_verified' THEN 50
          WHEN 'point_on_surface' THEN 40
          WHEN 'parcel_verified' THEN 30
          WHEN 'proximity_verified' THEN 20
          WHEN 'proximity_fallback' THEN 10
          ELSE 0
        END DESC,
        COALESCE(confidence, 0) DESC,
        id DESC
    ) AS rn
  FROM public.building_address_links
)
DELETE FROM public.building_address_links bal
USING ranked_links ranked
WHERE bal.id = ranked.id
  AND ranked.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_building_address_links_campaign_address_unique
  ON public.building_address_links(campaign_id, address_id);

COMMENT ON INDEX public.idx_building_address_links_campaign_address_unique IS
'Ensures a campaign address has one current building assignment. Buildings can still hold many addresses for townhomes/apartments.';
