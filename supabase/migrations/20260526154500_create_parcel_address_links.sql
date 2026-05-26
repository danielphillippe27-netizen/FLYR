BEGIN;

CREATE TABLE IF NOT EXISTS public.parcel_address_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  parcel_id UUID NOT NULL REFERENCES public.campaign_parcels(id) ON DELETE CASCADE,
  address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
  match_type TEXT NOT NULL DEFAULT 'centroid_in_parcel',
  link_source TEXT NOT NULL DEFAULT 'auto'
    CHECK (link_source IN ('auto', 'manual')),
  confidence DOUBLE PRECISION
    CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (campaign_id, address_id)
);

CREATE INDEX IF NOT EXISTS parcel_address_links_campaign_id_idx
  ON public.parcel_address_links (campaign_id);

CREATE INDEX IF NOT EXISTS parcel_address_links_parcel_id_idx
  ON public.parcel_address_links (parcel_id);

CREATE INDEX IF NOT EXISTS parcel_address_links_address_id_idx
  ON public.parcel_address_links (address_id);

COMMENT ON TABLE public.parcel_address_links IS
'Persistent parcel-to-address evidence used for parcel bridge building links, map coloring, and manual overrides.';

COMMENT ON COLUMN public.parcel_address_links.match_type IS
'How the parcel-address association was determined, for example centroid_in_parcel or manual.';

DROP TRIGGER IF EXISTS set_parcel_address_links_updated_at
  ON public.parcel_address_links;

CREATE OR REPLACE FUNCTION public.set_parcel_address_links_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_parcel_address_links_updated_at
  BEFORE UPDATE ON public.parcel_address_links
  FOR EACH ROW
  EXECUTE FUNCTION public.set_parcel_address_links_updated_at();

NOTIFY pgrst, 'reload schema';

COMMIT;
