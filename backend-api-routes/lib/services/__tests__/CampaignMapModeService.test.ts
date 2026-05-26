/**
 * CampaignMapModeService decision regression fixtures
 *
 * Run with: npx tsx lib/services/__tests__/CampaignMapModeService.test.ts
 */

import {
  resolveCampaignMapMode,
  type CampaignMapMode,
} from '../CampaignMapModeService';

let testsPassed = 0;
let testsFailed = 0;

function test(name: string, fn: () => void) {
  try {
    fn();
    console.log(`✓ ${name}`);
    testsPassed++;
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`✗ ${name}`);
    console.error(`  ${message}`);
    testsFailed++;
  }
}

function assertEqual(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(message || `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function expectMode(
  hasParcels: boolean,
  buildingLinkConfidence: number,
  expected: CampaignMapMode
) {
  assertEqual(
    resolveCampaignMapMode({ hasParcels, buildingLinkConfidence }),
    expected,
    `Expected mode ${expected} for hasParcels=${hasParcels}, confidence=${buildingLinkConfidence}`
  );
}

test('Parcels present and low confidence uses hybrid', () => {
  expectMode(true, 45, 'hybrid');
});

test('No parcels and low confidence uses hybrid', () => {
  expectMode(false, 45, 'hybrid');
});

test('No parcels and mid confidence uses hybrid', () => {
  expectMode(false, 70, 'hybrid');
});

test('No parcels and high confidence uses hybrid', () => {
  expectMode(false, 92, 'hybrid');
});

test('Parcels present and high confidence uses hybrid', () => {
  expectMode(true, 92, 'hybrid');
});

if (testsFailed > 0) {
  console.error(`\n${testsFailed} test(s) failed, ${testsPassed} passed.`);
  process.exit(1);
}

console.log(`\nAll ${testsPassed} campaign map mode tests passed.`);
