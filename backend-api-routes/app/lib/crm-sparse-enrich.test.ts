import assert from "node:assert/strict";
import test from "node:test";

import type { BoldTrailLeadPayload } from "./boldtrail";
import {
  displayNameFromAddress,
  enrichBoldTrailLeadPayload,
  enrichHubSpotPushLeadInput,
  placeholderCaptureEmail,
} from "./crm-sparse-enrich";

test("placeholderCaptureEmail is stable and uses capture domain", () => {
  const id = "550e8400-e29b-41d4-a716-446655440000";
  assert.equal(placeholderCaptureEmail(id), "field+550e8400e29b@capture.flyrpro.app");
});

test("displayNameFromAddress uses first line", () => {
  assert.match(displayNameFromAddress("123 Main St\nUnit 2") ?? "", /^Property: 123 Main St/);
});

test("enrichHubSpotPushLeadInput fills email and name for address-only lead", () => {
  const out = enrichHubSpotPushLeadInput({
    id: "550e8400-e29b-41d4-a716-446655440000",
    address: "88 River Rd",
  });
  assert.ok(out.email?.includes("@capture.flyrpro.app"));
  assert.ok(out.name?.startsWith("Property:"));
});

test("enrichHubSpotPushLeadInput leaves rich lead unchanged", () => {
  const out = enrichHubSpotPushLeadInput({
    id: "550e8400-e29b-41d4-a716-446655440000",
    name: "Jane Doe",
    email: "jane@example.com",
  });
  assert.equal(out.email, "jane@example.com");
  assert.equal(out.name, "Jane Doe");
});

test("enrichBoldTrailLeadPayload adds synthetic email when only address", () => {
  const out = enrichBoldTrailLeadPayload({
    id: "550e8400-e29b-41d4-a716-446655440000",
    address: "1 Lake Ave",
  } as BoldTrailLeadPayload & { id: string });
  assert.ok(out.email?.includes("field+"));
});

test("enrichBoldTrailLeadPayload keeps phone when present", () => {
  const out = enrichBoldTrailLeadPayload({
    id: "550e8400-e29b-41d4-a716-446655440000",
    phone: "+15551234567",
  } as BoldTrailLeadPayload & { id: string });
  assert.equal(out.phone, "+15551234567");
  assert.equal(out.email, undefined);
});
