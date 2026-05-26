export type AddressCandidateConfidenceLabel = "high" | "medium" | "low";

export type AddressCandidateTrust = {
  confidenceLabel: AddressCandidateConfidenceLabel;
  trusted: boolean;
  rejectedReason: string | null;
  requiresConfirmation: boolean;
};

export function assessOfficialAddressTrust(distanceMeters: number, sameStreet: boolean): AddressCandidateTrust {
  if (distanceMeters <= 25) {
    return {
      confidenceLabel: "high",
      trusted: true,
      rejectedReason: null,
      requiresConfirmation: false,
    };
  }
  if (distanceMeters <= 60) {
    return {
      confidenceLabel: "medium",
      trusted: true,
      rejectedReason: null,
      requiresConfirmation: false,
    };
  }
  if (distanceMeters <= 120 && sameStreet) {
    return {
      confidenceLabel: "low",
      trusted: true,
      rejectedReason: null,
      requiresConfirmation: true,
    };
  }
  return {
    confidenceLabel: "low",
    trusted: false,
    rejectedReason: "missing_same_street_validation",
    requiresConfirmation: true,
  };
}

export function shouldUseReverseGeocode(
  candidates: Array<{ distanceMeters: number; sameStreet: boolean }>
): {
  usedReverseGeocode: boolean;
  reason: string;
  nearestCandidateDistanceMeters: number | null;
  nearestCandidateRejectedReason: string | null;
} {
  const sorted = [...candidates]
    .filter((candidate) => Number.isFinite(candidate.distanceMeters) && candidate.distanceMeters <= 120)
    .sort((a, b) => a.distanceMeters - b.distanceMeters);

  if (sorted.length === 0) {
    return {
      usedReverseGeocode: true,
      reason: "no_official_candidate_within_120m",
      nearestCandidateDistanceMeters: null,
      nearestCandidateRejectedReason: null,
    };
  }

  for (const candidate of sorted) {
    const trust = assessOfficialAddressTrust(candidate.distanceMeters, candidate.sameStreet);
    if (trust.trusted) {
      return {
        usedReverseGeocode: false,
        reason: `trusted_official_candidate_${trust.confidenceLabel}`,
        nearestCandidateDistanceMeters: candidate.distanceMeters,
        nearestCandidateRejectedReason: null,
      };
    }
  }

  const nearest = sorted[0];
  const trust = assessOfficialAddressTrust(nearest.distanceMeters, nearest.sameStreet);
  return {
    usedReverseGeocode: true,
    reason: "no_trusted_official_candidate_within_120m",
    nearestCandidateDistanceMeters: nearest.distanceMeters,
    nearestCandidateRejectedReason: trust.rejectedReason,
  };
}
