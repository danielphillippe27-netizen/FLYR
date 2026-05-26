/**
 * Address candidate trust regression fixtures
 *
 * Run with: npx tsx lib/services/__tests__/AddressCandidateTrustService.test.ts
 */

import {
  assessOfficialAddressTrust,
  shouldUseReverseGeocode,
} from "../AddressCandidateTrustService";

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

console.log("Running address candidate trust fixtures...\n");

test("20m official candidate is high confidence and suppresses fallback", () => {
  assertEqual(assessOfficialAddressTrust(20, false), {
    confidenceLabel: "high",
    trusted: true,
    rejectedReason: null,
    requiresConfirmation: false,
  });
  assertEqual(shouldUseReverseGeocode([{ distanceMeters: 20, sameStreet: false }]).usedReverseGeocode, false);
});

test("50m official candidate is medium confidence and suppresses fallback", () => {
  assertEqual(assessOfficialAddressTrust(50, false), {
    confidenceLabel: "medium",
    trusted: true,
    rejectedReason: null,
    requiresConfirmation: false,
  });
  assertEqual(shouldUseReverseGeocode([{ distanceMeters: 50, sameStreet: false }]).reason, "trusted_official_candidate_medium");
});

test("90m same-street official candidate is low confidence and requires confirmation", () => {
  assertEqual(assessOfficialAddressTrust(90, true), {
    confidenceLabel: "low",
    trusted: true,
    rejectedReason: null,
    requiresConfirmation: true,
  });
  assertEqual(shouldUseReverseGeocode([{ distanceMeters: 90, sameStreet: true }]).usedReverseGeocode, false);
});

test("90m candidate without same-street validation triggers reverse geocode", () => {
  assertEqual(assessOfficialAddressTrust(90, false), {
    confidenceLabel: "low",
    trusted: false,
    rejectedReason: "missing_same_street_validation",
    requiresConfirmation: true,
  });
  assertEqual(shouldUseReverseGeocode([{ distanceMeters: 90, sameStreet: false }]), {
    usedReverseGeocode: true,
    reason: "no_trusted_official_candidate_within_120m",
    nearestCandidateDistanceMeters: 90,
    nearestCandidateRejectedReason: "missing_same_street_validation",
  });
});

test("no official candidate within 120m triggers reverse geocode", () => {
  assertEqual(shouldUseReverseGeocode([{ distanceMeters: 125, sameStreet: true }]), {
    usedReverseGeocode: true,
    reason: "no_official_candidate_within_120m",
    nearestCandidateDistanceMeters: null,
    nearestCandidateRejectedReason: null,
  });
});

if (testsFailed > 0) {
  console.error(`\n${testsFailed} test(s) failed, ${testsPassed} passed.`);
  process.exit(1);
}

console.log(`\nAll ${testsPassed} address candidate trust tests passed.`);
