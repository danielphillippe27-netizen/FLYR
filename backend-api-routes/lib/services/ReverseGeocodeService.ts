export type ReverseGeocodePoint = {
  lat: number;
  lng: number;
};

export type ReverseGeocodeAddress = {
  formatted_address: string;
  street_line: string | null;
  house_number: string | null;
  street: string | null;
  locality: string | null;
  region: string | null;
  postal_code: string | null;
  country: string | null;
  coordinate: ReverseGeocodePoint;
};

type MapboxContext = {
  id?: string;
  text?: string;
  short_code?: string;
};

type MapboxFeature = {
  place_name?: string;
  address?: string;
  text?: string;
  center?: [number, number];
  context?: MapboxContext[];
};

type MapboxReverseResponse = {
  features?: MapboxFeature[];
};

function mapboxToken(): string | null {
  return (
    process.env.MAPBOX_TOKEN ||
    process.env.MAPBOX_ACCESS_TOKEN ||
    process.env.NEXT_PUBLIC_MAPBOX_TOKEN ||
    process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN ||
    null
  );
}

function contextText(feature: MapboxFeature, prefix: string): string | null {
  const context = feature.context?.find((item) => item.id?.startsWith(prefix));
  return context?.text?.trim() || null;
}

function cleanAddressPart(value: string | null | undefined): string | null {
  const cleaned = value?.trim().replace(/\s+/g, " ");
  return cleaned || null;
}

function firstFormattedLine(formatted: string | null | undefined): string | null {
  return cleanAddressPart(formatted?.split(",", 1)[0]);
}

function streetStartsWithHouseNumber(street: string, houseNumber: string): boolean {
  const escapedHouseNumber = houseNumber.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${escapedHouseNumber}(\\b|\\s)`, "i").test(street);
}

function normalizedStreetLine(
  houseNumber: string | null,
  street: string | null,
  formatted: string | null | undefined,
): string | null {
  const cleanedHouseNumber = cleanAddressPart(houseNumber);
  const cleanedStreet = cleanAddressPart(street);
  const formattedLine = firstFormattedLine(formatted);
  if (cleanedHouseNumber && cleanedStreet) {
    return streetStartsWithHouseNumber(cleanedStreet, cleanedHouseNumber)
      ? cleanedStreet
      : `${cleanedHouseNumber} ${cleanedStreet}`;
  }
  if (formattedLine && /^\d+\b/.test(formattedLine)) return formattedLine;
  return cleanedStreet ?? formattedLine;
}

export class ReverseGeocodeService {
  static async mapboxReverseAddress(point: ReverseGeocodePoint): Promise<ReverseGeocodeAddress | null> {
    const token = mapboxToken();
    if (!token) return null;

    const params = new URLSearchParams({
      types: "address",
      limit: "1",
      access_token: token,
    });
    const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${point.lng},${point.lat}.json?${params}`;

    try {
      const response = await fetch(url);
      if (!response.ok) return null;

      const payload = (await response.json()) as MapboxReverseResponse;
      const feature = Array.isArray(payload.features) ? payload.features[0] : null;
      if (!feature) return null;

      const center = Array.isArray(feature.center) && feature.center.length >= 2
        ? { lng: Number(feature.center[0]), lat: Number(feature.center[1]) }
        : point;
      const formatted = feature.place_name?.trim();
      if (!formatted || !Number.isFinite(center.lng) || !Number.isFinite(center.lat)) {
        return null;
      }

      const houseNumber = feature.address?.trim() || null;
      const street = feature.text?.trim() || null;

      return {
        formatted_address: formatted,
        street_line: normalizedStreetLine(houseNumber, street, formatted),
        house_number: houseNumber,
        street,
        locality: contextText(feature, "place") ?? contextText(feature, "locality"),
        region: contextText(feature, "region"),
        postal_code: contextText(feature, "postcode"),
        country: contextText(feature, "country"),
        coordinate: center,
      };
    } catch {
      return null;
    }
  }
}
