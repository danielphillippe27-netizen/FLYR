type AddressIdentityInput = {
  formatted?: unknown;
  address_text?: unknown;
  house_number?: unknown;
  street_name?: unknown;
  unit?: unknown;
  locality?: unknown;
  city?: unknown;
  postal_code?: unknown;
  zip?: unknown;
};

const STREET_SUFFIX_REPLACEMENTS: Array<[RegExp, string]> = [
  [/\bavenue\b/g, 'ave'],
  [/\bave\.?\b/g, 'ave'],
  [/\bstreet\b/g, 'st'],
  [/\bst\.?\b/g, 'st'],
  [/\bdrive\b/g, 'dr'],
  [/\bdr\.?\b/g, 'dr'],
  [/\bboulevard\b/g, 'blvd'],
  [/\bblvd\.?\b/g, 'blvd'],
  [/\broad\b/g, 'rd'],
  [/\brd\.?\b/g, 'rd'],
  [/\blane\b/g, 'ln'],
  [/\bln\.?\b/g, 'ln'],
  [/\bcourt\b/g, 'ct'],
  [/\bct\.?\b/g, 'ct'],
  [/\bplace\b/g, 'pl'],
  [/\bpl\.?\b/g, 'pl'],
  [/\bcircle\b/g, 'cir'],
  [/\bcir\.?\b/g, 'cir'],
  [/\bparkway\b/g, 'pkwy'],
  [/\bpkwy\.?\b/g, 'pkwy'],
  [/\bhighway\b/g, 'hwy'],
  [/\bhwy\.?\b/g, 'hwy'],
  [/\bterrace\b/g, 'ter'],
  [/\bter\.?\b/g, 'ter'],
  [/\btrail\b/g, 'trl'],
  [/\btrl\.?\b/g, 'trl'],
  [/\bway\b/g, 'wy'],
];

function stringValue(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function isStreetOnlyOrdinalAddressLabel(value: unknown): boolean {
  const raw = stringValue(value);
  return Boolean(raw && /^\d+(?:st|nd|rd|th)$/i.test(raw));
}

export function isNumericOnlyAddressLabel(value: unknown): boolean {
  const raw = stringValue(value);
  return Boolean(raw && /^[\d\s#./-]+$/.test(raw));
}

export function isUsableHouseNumberAddressLabel(value: unknown): boolean {
  const raw = stringValue(value);
  return Boolean(raw && !isStreetOnlyOrdinalAddressLabel(raw) && /^\d+[A-Za-z0-9/-]*$/.test(raw));
}

export function normalizedAddressPart(value: unknown): string | null {
  const raw = stringValue(value);
  if (!raw) return null;
  let output = raw.toLowerCase();
  for (const [pattern, replacement] of STREET_SUFFIX_REPLACEMENTS) {
    output = output.replace(pattern, replacement);
  }
  output = output
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9#-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return output.length > 0 ? output : null;
}

function addressLineFromFormatted(formatted: string | null): string | null {
  if (!formatted) return null;
  return stringValue(formatted.split(',')[0]) ?? formatted;
}

function unitFromAddressText(value: string | null): string | null {
  if (!value) return null;
  const match = value.match(/(?:\b(?:unit|apt|apartment|suite|ste)\s*|#\s*)([a-z0-9-]+)\b/i);
  return normalizedAddressPart(match?.[1]);
}

function withoutUnitText(value: string | null): string | null {
  if (!value) return null;
  return stringValue(
    value
      .replace(/(?:\b(?:unit|apt|apartment|suite|ste)\s*|#\s*)[a-z0-9-]+\b/ig, ' ')
      .replace(/\s+/g, ' ')
  );
}

function houseNumberFromAddressLine(addressLine: string | null): string | null {
  if (!addressLine) return null;
  const match = addressLine.match(/^\s*([0-9]+[a-z0-9-]*)\b/i);
  const candidate = match?.[1];
  if (isStreetOnlyOrdinalAddressLabel(candidate)) return null;
  return normalizedAddressPart(candidate);
}

function streetFromAddressLine(addressLine: string | null, houseNumber: string | null): string | null {
  if (!addressLine) return null;
  let street = withoutUnitText(addressLine) ?? addressLine;
  if (houseNumber) {
    street = street.replace(new RegExp(`^\\s*${houseNumber.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i'), '');
  } else {
    const prefix = street.match(/^\s*([0-9]+[a-z0-9-]*)\b/i)?.[1];
    if (prefix && !isStreetOnlyOrdinalAddressLabel(prefix)) {
      street = street.replace(/^\s*[0-9]+[a-z0-9-]*\b/i, '');
    }
  }
  return normalizedAddressPart(street);
}

export function normalizedAddressDisplayIdentity(input: AddressIdentityInput): string | null {
  const formatted = stringValue(input.formatted) ?? stringValue(input.address_text);
  const addressLine = addressLineFromFormatted(formatted);
  const explicitHouseNumber = isUsableHouseNumberAddressLabel(input.house_number)
    ? normalizedAddressPart(input.house_number)
    : null;
  const houseNumber = explicitHouseNumber ?? houseNumberFromAddressLine(addressLine);
  const unit = normalizedAddressPart(input.unit) ?? unitFromAddressText(addressLine) ?? unitFromAddressText(formatted);
  const explicitStreet = isNumericOnlyAddressLabel(input.street_name)
    ? null
    : normalizedAddressPart(input.street_name);
  const street = explicitStreet ?? streetFromAddressLine(addressLine, houseNumber);

  if (houseNumber && street) {
    return [
      `h:${houseNumber}`,
      `s:${street}`,
      unit ? `u:${unit}` : 'u:',
    ].join('|');
  }

  const locality = normalizedAddressPart(input.locality) ?? normalizedAddressPart(input.city);
  const postalCode = normalizedAddressPart(input.postal_code) ?? normalizedAddressPart(input.zip);
  const normalizedFormatted = normalizedAddressPart(formatted);
  if (!normalizedFormatted && !postalCode) return null;
  return [
    normalizedFormatted ? `f:${normalizedFormatted}` : 'f:',
    locality ? `l:${locality}` : 'l:',
    postalCode ? `p:${postalCode}` : 'p:',
  ].join('|');
}

export function canonicalBedrockAddressExternalId(value: string | null | undefined): string {
  const raw = typeof value === 'string' ? value.trim() : '';
  if (!raw) return '';
  return raw.replace(/^(bedrock_us:)?master:us:/i, '$1');
}
