BEGIN;

ALTER TABLE public.campaigns
  DROP CONSTRAINT IF EXISTS campaigns_provision_phase_check;

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_provision_phase_check
  CHECK (
    provision_phase IN (
      'created',
      'source_probed',
      'addresses_loading',
      'addresses_ready',
      'map_ready',
      'optimizing',
      'optimized',
      'linked',
      'linking_failed',
      'failed'
    )
  );

COMMENT ON COLUMN public.campaigns.provision_phase IS
'Fine-grained provisioning lifecycle phase. provision_status remains the backward-compatible ready/failed gate; linking_failed means addresses/buildings loaded but automatic building linking produced zero usable links.';

COMMIT;
