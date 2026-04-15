/**
 * Shared sparse-lead enrichment for secure CRM routes (parity with iOS CRMLeadEnrichment).
 * Fills synthetic email / display name only when required so field-captured address-only leads still push.
 */

import type { PushLeadInput } from "./hubspot-crm";
import type { BoldTrailLeadPayload } from "./boldtrail";

const CAPTURE_EMAIL_DOMAIN = "capture.flyrpro.app";

export function placeholderCaptureEmail(leadId: string): string {
  const hex = leadId.replace(/-/g, "").slice(0, 12).toLowerCase();
  return `field+${hex}@${CAPTURE_EMAIL_DOMAIN}`;
}

export function displayNameFromAddress(address?: string | null): string | undefined {
  const raw = address?.trim();
  if (!raw) return undefined;
  const firstLine = raw
    .split("\n")
    .map((s) => s.trim())
    .find((s) => s.length > 0);
  if (!firstLine) return undefined;
  const clipped = firstLine.length > 80 ? `${firstLine.slice(0, 80)}…` : firstLine;
  return `Property: ${clipped}`;
}

export function enrichHubSpotPushLeadInput(lead: PushLeadInput): PushLeadInput {
  let email = lead.email?.trim() || undefined;
  let phone = lead.phone?.trim() || undefined;
  let name = lead.name?.trim() || undefined;

  if (!email && !phone) {
    email = placeholderCaptureEmail(lead.id);
  }

  const hubSpotOk = Boolean((email && email.length > 0) || (name && name.length > 0));
  if (!hubSpotOk) {
    name = displayNameFromAddress(lead.address) ?? "FLYR field lead";
  } else if (!(name && name.length > 0) && lead.address?.trim()) {
    // Synthetic email satisfies HubSpot; still set a readable label from the address when possible.
    name = displayNameFromAddress(lead.address);
  }

  return {
    ...lead,
    email,
    phone,
    name,
  };
}

export function enrichBoldTrailLeadPayload<T extends BoldTrailLeadPayload & { id?: string }>(lead: T): T {
  let email = lead.email?.trim() || undefined;
  let phone = lead.phone?.trim() || undefined;
  const id = typeof lead.id === "string" ? lead.id.trim() : "";

  if (!email && !phone && id) {
    email = placeholderCaptureEmail(id);
  }

  return {
    ...lead,
    email,
    phone,
  };
}
