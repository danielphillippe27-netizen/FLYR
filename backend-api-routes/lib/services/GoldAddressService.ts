import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const GOLD_THRESHOLD = 10; // Minimum Gold addresses to use Gold path

// Shape returned from get_gold_addresses_in_polygon_geojson RPC
export interface GoldAddressRow {
  id: string;
  source_id: string | null;
  street_number: string | null;
  street_name: string | null;
  unit: string | null;
  city: string | null;
  zip: string | null;
  province: string | null;
  country: string | null;
  address_type: string | null;
  precision: string | null;
  street_number_normalized: number | null;
  street_name_normalized: string | null;
  zip_normalized: string | null;
  geom_geojson: { type: string; coordinates: [number, number] } | null;
}

// Normalized shape written into campaign_addresses
export interface NormalizedCampaignAddress {
  campaign_id: string;
  owner_id: string;
  house_number: string | null;
  street_name: string | null;
  locality: string | null;
  region: string | null;
  postal_code: string | null;
  country: string | null;
  formatted: string;
  geom: string | null; // GeoJSON geometry string for Supabase PostGIS insert
  gers_id: string | null;
  source: "gold" | "lambda" | "silver";
}

export type AddressSource = "gold" | "lambda" | "silver";

export interface GoldAddressResult {
  addresses: NormalizedCampaignAddress[];
  source: AddressSource;
  goldCount: number;
}

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

function formatAddress(row: GoldAddressRow): string {
  const parts: string[] = [];
  if (row.street_number) parts.push(row.street_number);
  if (row.unit) parts.push(`Unit ${row.unit}`);
  if (row.street_name) parts.push(row.street_name);
  if (row.city) parts.push(row.city);
  if (row.province) parts.push(row.province);
  if (row.zip) parts.push(row.zip);
  return parts.join(", ");
}

function normalizeGoldRow(
  row: GoldAddressRow,
  campaignId: string,
  ownerId: string
): NormalizedCampaignAddress {
  return {
    campaign_id:  campaignId,
    owner_id:     ownerId,
    house_number: row.street_number ?? null,
    street_name:  row.street_name ?? null,
    locality:     row.city ?? null,
    region:       row.province ?? null,
    postal_code:  row.zip ?? null,
    country:      row.country ?? null,
    formatted:    formatAddress(row),
    geom:         row.geom_geojson ? JSON.stringify(row.geom_geojson) : null,
    gers_id:      null,
    source:       "gold",
  };
}

/**
 * Queries ref_addresses_gold within a polygon and returns normalized campaign addresses.
 *
 * If the Gold count is below GOLD_THRESHOLD, returns source: 'lambda' with an empty
 * addresses array so the caller falls through to the Lambda/S3 path.
 */
export async function getGoldAddressesForPolygon(
  campaignId: string,
  ownerId: string,
  polygonGeoJSON: string,
  province?: string
): Promise<GoldAddressResult> {
  const supabase = adminClient();

  const params: Record<string, string> = {
    p_polygon_geojson: polygonGeoJSON,
  };
  if (province) params.p_province = province;

  const { data, error } = await supabase
    .rpc("get_gold_addresses_in_polygon_geojson", params)
    .single();

  if (error) {
    console.error("[GoldAddressService] RPC error:", error);
    return { addresses: [], source: "lambda", goldCount: 0 };
  }

  const rows: GoldAddressRow[] = Array.isArray(data) ? data : [];
  const goldCount = rows.length;

  if (goldCount < GOLD_THRESHOLD) {
    console.log(
      `[GoldAddressService] Gold count ${goldCount} < ${GOLD_THRESHOLD}, using Lambda path`
    );
    return { addresses: [], source: "lambda", goldCount };
  }

  const addresses = rows.map((r) => normalizeGoldRow(r, campaignId, ownerId));
  console.log(
    `[GoldAddressService] Gold path: ${goldCount} addresses for campaign ${campaignId}`
  );
  return { addresses, source: "gold", goldCount };
}

/**
 * Inserts or replaces campaign_addresses for a campaign (deletes existing first).
 * Returns count of inserted rows.
 */
export async function insertCampaignAddresses(
  campaignId: string,
  addresses: NormalizedCampaignAddress[]
): Promise<number> {
  if (addresses.length === 0) return 0;
  const supabase = adminClient();

  // Clear existing addresses for this campaign to allow re-provision
  await supabase
    .from("campaign_addresses")
    .delete()
    .eq("campaign_id", campaignId);

  const BATCH = 500;
  let inserted = 0;
  for (let i = 0; i < addresses.length; i += BATCH) {
    const batch = addresses.slice(i, i + BATCH);
    const { error } = await supabase.from("campaign_addresses").insert(batch);
    if (error) {
      console.error(`[GoldAddressService] Insert batch ${i} error:`, error);
      throw error;
    }
    inserted += batch.length;
  }
  console.log(`[GoldAddressService] Inserted ${inserted} addresses`);
  return inserted;
}
