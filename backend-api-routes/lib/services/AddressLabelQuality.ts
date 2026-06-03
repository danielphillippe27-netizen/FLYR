import type { StandardCampaignAddress } from '@/lib/services/AddressAdapter';
import {
  isStreetOnlyOrdinalAddressLabel,
  isUsableHouseNumberAddressLabel,
} from '@/lib/services/AddressDisplayIdentity';

export type AddressLabelQuality = {
  usable: number;
  numericOnly: number;
  houseNumberUsable: number;
  streetOnlyOrdinal: number;
  usableRatio: number;
  houseNumberUsableRatio: number;
  streetOnlyOrdinalRatio: number;
  acceptable: boolean;
};

export function isNumericOnlyAddressLabel(value: string | null | undefined): boolean {
  return typeof value === 'string' && /^[\d\s#./-]+$/.test(value.trim());
}

function hasHouseNumber(value: string | null | undefined): boolean {
  return isUsableHouseNumberAddressLabel(value);
}

export function addressLabelQuality(addresses: StandardCampaignAddress[]): AddressLabelQuality {
  if (addresses.length === 0) {
    return {
      usable: 0,
      numericOnly: 0,
      houseNumberUsable: 0,
      streetOnlyOrdinal: 0,
      usableRatio: 0,
      houseNumberUsableRatio: 0,
      streetOnlyOrdinalRatio: 0,
      acceptable: false,
    };
  }

  let usable = 0;
  let numericOnly = 0;
  let houseNumberUsable = 0;
  let streetOnlyOrdinal = 0;

  for (const address of addresses) {
    const streetName = address.street_name?.trim();
    const formatted = address.formatted?.trim();
    const hasNamedStreet = Boolean(streetName && !isNumericOnlyAddressLabel(streetName));
    const hasReadableFormatted = Boolean(formatted && !isNumericOnlyAddressLabel(formatted));
    const hasUsableHouseNumber = Boolean(
      hasHouseNumber(address.house_number) ||
        hasHouseNumber(formatted)
    );

    if (hasNamedStreet || hasReadableFormatted) {
      usable += 1;
    }
    if (hasUsableHouseNumber) {
      houseNumberUsable += 1;
    }
    if (
      isNumericOnlyAddressLabel(streetName) ||
      (formatted && isNumericOnlyAddressLabel(formatted))
    ) {
      numericOnly += 1;
    }
    if (isStreetOnlyOrdinalAddressLabel(streetName) || isStreetOnlyOrdinalAddressLabel(formatted)) {
      streetOnlyOrdinal += 1;
    }
  }

  const usableRatio = usable / addresses.length;
  const houseNumberUsableRatio = houseNumberUsable / addresses.length;
  const streetOnlyOrdinalRatio = streetOnlyOrdinal / addresses.length;

  return {
    usable,
    numericOnly,
    houseNumberUsable,
    streetOnlyOrdinal,
    usableRatio,
    houseNumberUsableRatio,
    streetOnlyOrdinalRatio,
    acceptable: usableRatio >= 0.6 && houseNumberUsableRatio >= 0.6,
  };
}
