import assert from 'node:assert/strict';
import { resolveProvisionPostProcessingDecision } from '../CampaignProvisionPostProcessing';

const cases = [
  {
    name: 'Gold creation runs post-processing inline',
    input: {
      addressSource: 'gold' as const,
      forceStableLinking: false,
      parcelRegionSupported: false,
    },
    expected: {
      shouldDeferPostProcessing: false,
      parcelEnrichmentStatus: 'skipped',
    },
  },
  {
    name: 'Lambda creation in parcel-supported region runs inline for parcel bridge',
    input: {
      addressSource: 'lambda' as const,
      forceStableLinking: false,
      parcelRegionSupported: true,
    },
    expected: {
      shouldDeferPostProcessing: false,
      parcelEnrichmentStatus: 'processing',
    },
  },
  {
    name: 'Lambda creation outside parcel-supported regions can defer',
    input: {
      addressSource: 'lambda' as const,
      forceStableLinking: false,
      parcelRegionSupported: false,
    },
    expected: {
      shouldDeferPostProcessing: true,
      parcelEnrichmentStatus: 'skipped',
    },
  },
  {
    name: 'Forced stable Lambda creation runs inline even without parcels',
    input: {
      addressSource: 'lambda' as const,
      forceStableLinking: true,
      parcelRegionSupported: false,
    },
    expected: {
      shouldDeferPostProcessing: false,
      parcelEnrichmentStatus: 'skipped',
    },
  },
];

for (const testCase of cases) {
  assert.deepEqual(
    resolveProvisionPostProcessingDecision(testCase.input),
    testCase.expected,
    testCase.name
  );
  console.log(`✓ ${testCase.name}`);
}

console.log(`\nAll ${cases.length} campaign provision post-processing decision tests passed.`);
