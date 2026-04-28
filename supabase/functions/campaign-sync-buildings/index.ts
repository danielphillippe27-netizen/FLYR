// supabase/functions/campaign-sync-buildings/index.ts
// Edge Function: Generate stylized rectangle polygons for all addresses in a campaign
// Replaces Mapbox tilequery logic with simple 12m x 10m rectangles

import { createClient } from "npm:@supabase/supabase-js@2";
import { createRectangleAroundPoint } from "../_shared/geometry.ts";

type SyncPayload = {
  campaign_id: string;
};

type SyncResult = {
  campaign_id: string;
  processed: number;
  created: number;
  skipped: number;
  errors: number;
};

// ------------------------------
// Configuration Constants
// ------------------------------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SERVICE_ROLE) {
  throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY - required for database writes");
}

const supabase = createClient(
  SUPABASE_URL,
  SERVICE_ROLE,
  { auth: { persistSession: false } },
);

// ------------------------------
// Database Operations
// ------------------------------

async function upsertAddressBuilding(
  addressId: string,
  polygon: GeoJSON.Polygon,
): Promise<{ upserted: boolean; created: boolean }> {
  // Check if exists to determine created vs updated
  const { data: existing, error: selectError } = await supabase
    .from("address_buildings")
    .select("id")
    .eq("address_id", addressId)
    .maybeSingle();

  if (selectError && selectError.code !== "PGRST116") {
    console.error(`[UPSERT] Select check failed for address_id=${addressId}:`, selectError);
    return { upserted: false, created: false };
  }

  const isCreated = existing === null;

  try {
    // Use RPC function to handle PostGIS geometry conversion
    const { error: rpcError } = await supabase.rpc("fn_upsert_address_building", {
      p_address_id: addressId,
      p_geojson: polygon as any,
    });

    if (rpcError) {
      console.error(`[UPSERT] RPC failed for address_id=${addressId}:`, rpcError);
      return { upserted: false, created: false };
    }

    return { upserted: true, created: isCreated };
  } catch (e: any) {
    console.error(`[UPSERT] Error for address_id=${addressId}:`, e);
    return { upserted: false, created: false };
  }
}

// ------------------------------
// HTTP handler
// ------------------------------

Deno.serve(async (req) => {
  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response("Use POST", { status: 405 });
  }

  const started = performance.now();
  const body = await req.json().catch(() => null) as SyncPayload | null;

  if (!body || !body.campaign_id) {
    return new Response(JSON.stringify({ error: "campaign_id is required" }), { status: 400 });
  }

  const campaignId = body.campaign_id;

  console.log(`[SYNC] Starting stylized polygon generation for campaign_id=${campaignId}`);

  // Fetch all addresses for the campaign with their geometry
  // Query campaign_addresses_v view which has geom_json (pre-computed GeoJSON)
  const { data: addrRows, error: addressesError } = await supabase
    .from("campaign_addresses_v")
    .select("id, geom_json")
    .eq("campaign_id", campaignId);

  if (addressesError) {
    console.error(`[SYNC] Failed to fetch addresses:`, addressesError);
    return new Response(
      JSON.stringify({ error: "Failed to fetch campaign addresses", details: addressesError.message }),
      { status: 500 }
    );
  }

  if (!addrRows || addrRows.length === 0) {
    console.log(`[SYNC] No addresses found for campaign_id=${campaignId}`);
    return new Response(JSON.stringify({
      campaign_id: campaignId,
      processed: 0,
      created: 0,
      skipped: 0,
      errors: 0,
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      status: 200,
    });
  }

  // Extract coordinates from geom_json
  const addressesWithCoords: Array<{ id: string; lon: number; lat: number }> = [];
  for (const row of addrRows) {
    try {
      const geom = typeof row.geom_json === "string" ? JSON.parse(row.geom_json) : row.geom_json;
      if (geom?.type === "Point" && Array.isArray(geom.coordinates) && geom.coordinates.length >= 2) {
        addressesWithCoords.push({
          id: row.id,
          lon: geom.coordinates[0],
          lat: geom.coordinates[1],
        });
      } else {
        console.warn(`[SYNC] Invalid geom_json for address_id=${row.id}:`, geom);
      }
    } catch (e) {
      console.error(`[SYNC] Failed to parse geom_json for address_id=${row.id}:`, e);
    }
  }

  if (addressesWithCoords.length === 0) {
    console.log(`[SYNC] No valid addresses with coordinates found for campaign_id=${campaignId}`);
    return new Response(JSON.stringify({
      campaign_id: campaignId,
      processed: 0,
      created: 0,
      skipped: 0,
      errors: 0,
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      status: 200,
    });
  }

  console.log(`[SYNC] Found ${addressesWithCoords.length} addresses for campaign_id=${campaignId}`);

  // Process each address: generate stylized rectangle if polygon doesn't exist
  let processed = 0;
  let created = 0;
  let skipped = 0;
  let errors = 0;

  for (const addr of addressesWithCoords) {
    try {
      const lon = addr.lon;
      const lat = addr.lat;

      if (typeof lon !== "number" || typeof lat !== "number" || !isFinite(lon) || !isFinite(lat)) {
        console.error(`[SYNC] Invalid coordinates for address_id=${addr.id}: lon=${lon}, lat=${lat}`);
        errors++;
        continue;
      }

      // Always generate stylized rectangle for every address
      // The unique constraint on address_id will handle duplicates via upsert
      const polygon = createRectangleAroundPoint(lat, lon, 12, 10);

      // Check if polygon already exists to determine if it's a new creation
      const { data: existing, error: checkError } = await supabase
        .from("address_buildings")
        .select("id")
        .eq("address_id", addr.id)
        .maybeSingle();

      if (checkError && checkError.code !== "PGRST116") {
        console.error(`[SYNC] Error checking existing polygon for address_id=${addr.id}:`, checkError);
        // Continue anyway - we'll try to upsert
      }

      const isExisting = existing != null;

      // Upsert into address_buildings (will update if exists, create if not)
      const { upserted, created: isCreated } = await upsertAddressBuilding(addr.id, polygon);

      if (upserted) {
        processed++;
        if (isCreated || !isExisting) {
          // Count as created if it was actually created, or if we regenerated it
          created++;
        } else {
          // Was updated (regenerated)
          skipped++;
        }

        // Compute front_bearing for the address_building after upsert
        // Get the address_building ID first
        const { data: addressBuilding, error: fetchError } = await supabase
          .from("address_buildings")
          .select("id")
          .eq("address_id", addr.id)
          .maybeSingle();

        if (!fetchError && addressBuilding?.id) {
          try {
            const { error: bearingError } = await supabase.rpc(
              "compute_front_bearing_for_address_building",
              { p_building_id: addressBuilding.id }
            );

            if (bearingError) {
              console.warn(
                `[SYNC] Failed to compute front_bearing for address_building_id=${addressBuilding.id}:`,
                bearingError
              );
              // Don't fail the sync, just log the warning
            } else {
              console.log(
                `[SYNC] Computed front_bearing for address_building_id=${addressBuilding.id}`
              );
            }
          } catch (e: any) {
            console.warn(
              `[SYNC] Error computing front_bearing for address_building_id=${addressBuilding.id}:`,
              e
            );
            // Don't fail the sync, just log the warning
          }
        }
      } else {
        errors++;
      }
    } catch (error) {
      console.error(`[SYNC] Error processing address_id=${addr.id}:`, error);
      errors++;
    }
  }

  const done = performance.now();
  const result: SyncResult = {
    campaign_id: campaignId,
    processed,
    created,
    skipped,
    errors,
  };

  console.log(`[SYNC] Completed in ${Math.round(done - started)}ms:`, result);

  return new Response(JSON.stringify(result), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    status: 200,
  });
});
