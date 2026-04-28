BEGIN;

ALTER TABLE public.campaigns
    ADD COLUMN IF NOT EXISTS has_parcels BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS building_link_confidence DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS map_mode TEXT
        CHECK (map_mode IN ('smart_buildings', 'hybrid', 'standard_pins'));

COMMENT ON COLUMN public.campaigns.has_parcels IS
'True when the campaign has usable parcel records loaded for parcel-aware map behavior.';

COMMENT ON COLUMN public.campaigns.building_link_confidence IS
'Campaign-level percentage of addresses linked to buildings at acceptable confidence (0-100).';

COMMENT ON COLUMN public.campaigns.map_mode IS
'Campaign map presentation mode: smart_buildings, hybrid, or standard_pins.';

COMMIT;
