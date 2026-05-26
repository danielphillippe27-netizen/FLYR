ALTER TABLE public.campaigns
  DROP CONSTRAINT IF EXISTS campaigns_provision_source_check;

UPDATE public.campaigns
SET provision_source = 'bedrock'
WHERE provision_source IN ('bedrock_nz', 'bedrock_au', 'bedrock_ca', 'bedrock_us', 'bedrock_za', 'bedrock_uk');

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_provision_source_check
  CHECK (
    provision_source IS NULL
    OR provision_source IN ('diamond', 'bedrock')
  );

COMMENT ON COLUMN public.campaigns.provision_source IS
'Top-level provisioning path. Detailed country/provider provenance lives in campaign_snapshots.tile_metrics and campaign_addresses.source.';
