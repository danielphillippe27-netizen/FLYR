type ProvisionSource = 'gold' | 'lambda';
type ParcelEnrichmentStatus = 'processing' | 'queued' | 'skipped';

export interface ProvisionPostProcessingDecisionInput {
  addressSource: ProvisionSource;
  forceStableLinking: boolean;
  parcelRegionSupported: boolean;
}

export interface ProvisionPostProcessingDecision {
  shouldDeferPostProcessing: boolean;
  parcelEnrichmentStatus: ParcelEnrichmentStatus;
}

export function resolveProvisionPostProcessingDecision(
  input: ProvisionPostProcessingDecisionInput
): ProvisionPostProcessingDecision {
  const shouldDeferPostProcessing =
    input.addressSource !== 'gold' &&
    !input.forceStableLinking &&
    !input.parcelRegionSupported;

  return {
    shouldDeferPostProcessing,
    parcelEnrichmentStatus: input.parcelRegionSupported
      ? (shouldDeferPostProcessing ? 'queued' : 'processing')
      : 'skipped',
  };
}
