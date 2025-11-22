import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

interface LeadPayload {
  id: string;
  name?: string;
  phone?: string;
  email?: string;
  address?: string;
  source: string;
  campaign_id?: string;
  notes?: string;
  created_at: string;
}

interface SyncRequest {
  lead: LeadPayload;
  user_id: string;
}

interface UserIntegration {
  id: string;
  user_id: string;
  provider: "fub" | "kvcore" | "hubspot" | "monday" | "zapier";
  access_token?: string;
  refresh_token?: string;
  api_key?: string;
  webhook_url?: string;
  expires_at?: number;
}

serve(async (req) => {
  try {
    // Parse request
    const { lead, user_id }: SyncRequest = await req.json();

    if (!lead || !user_id) {
      return new Response(
        JSON.stringify({ error: "Missing lead or user_id" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Validate lead has at least one contact field
    const hasContactInfo =
      (lead.name && lead.name.trim()) ||
      (lead.phone && lead.phone.trim()) ||
      (lead.email && lead.email.trim()) ||
      (lead.address && lead.address.trim());

    if (!hasContactInfo) {
      return new Response(
        JSON.stringify({ error: "Lead missing contact information" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Get auth token from request
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // Create authenticated client
    const token = authHeader.replace("Bearer ", "");
    const supabaseAuth = createClient(supabaseUrl, supabaseKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Fetch user's active integrations
    const { data: integrations, error: fetchError } = await supabaseAuth
      .from("user_integrations")
      .select("*")
      .eq("user_id", user_id);

    if (fetchError) {
      console.error("Error fetching integrations:", fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch integrations" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!integrations || integrations.length === 0) {
      return new Response(
        JSON.stringify({ message: "No integrations found", synced: [] }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Sync to each connected integration
    const results: Array<{ provider: string; success: boolean; error?: string }> = [];

    for (const integration of integrations as UserIntegration[]) {
      try {
        let success = false;
        let error: string | undefined;

        switch (integration.provider) {
          case "fub":
            success = await syncToFUB(lead, integration);
            break;
          case "kvcore":
            success = await syncToKVCore(lead, integration);
            break;
          case "hubspot":
            success = await syncToHubSpot(lead, integration);
            break;
          case "monday":
            success = await syncToMonday(lead, integration);
            break;
          case "zapier":
            success = await syncToZapier(lead, integration);
            break;
        }

        results.push({ provider: integration.provider, success, error });
      } catch (err) {
        console.error(`Error syncing to ${integration.provider}:`, err);
        results.push({
          provider: integration.provider,
          success: false,
          error: err instanceof Error ? err.message : "Unknown error",
        });
      }
    }

    return new Response(
      JSON.stringify({
        message: "Sync completed",
        synced: results.filter((r) => r.success).map((r) => r.provider),
        failed: results.filter((r) => !r.success),
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("Error in crm_sync:", err);
    return new Response(
      JSON.stringify({
        error: err instanceof Error ? err.message : "Unknown error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

// ============================================================================
// CRM Sync Functions
// ============================================================================

async function syncToFUB(lead: LeadPayload, integration: UserIntegration): Promise<boolean> {
  if (!integration.api_key) {
    throw new Error("FUB API key not found");
  }

  const payload = {
    firstName: lead.name?.split(" ")[0] || "",
    lastName: lead.name?.split(" ").slice(1).join(" ") || "",
    emails: lead.email ? [{ address: lead.email, type: "work" }] : [],
    phones: lead.phone ? [{ number: lead.phone, type: "mobile" }] : [],
    addresses: lead.address
      ? [
          {
            street: lead.address,
            city: "",
            state: "",
            zip: "",
            country: "US",
          },
        ]
      : [],
    source: lead.source || "FLYR",
    notes: lead.notes || "",
  };

  const response = await fetch("https://api.followupboss.com/v1/people", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${integration.api_key}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`FUB API error: ${response.status} - ${errorText}`);
  }

  return true;
}

async function syncToKVCore(lead: LeadPayload, integration: UserIntegration): Promise<boolean> {
  if (!integration.api_key) {
    throw new Error("KVCore API key not found");
  }

  const payload = {
    firstName: lead.name?.split(" ")[0] || "",
    lastName: lead.name?.split(" ").slice(1).join(" ") || "",
    email: lead.email || "",
    phone: lead.phone || "",
    address: lead.address || "",
    source: lead.source || "FLYR",
    notes: lead.notes || "",
  };

  const response = await fetch("https://api.kvcore.com/v1/leads", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${integration.api_key}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`KVCore API error: ${response.status} - ${errorText}`);
  }

  return true;
}

async function syncToHubSpot(lead: LeadPayload, integration: UserIntegration): Promise<boolean> {
  if (!integration.access_token) {
    throw new Error("HubSpot access token not found");
  }

  const properties: Record<string, string> = {
    firstname: lead.name?.split(" ")[0] || "",
    lastname: lead.name?.split(" ").slice(1).join(" ") || "",
    email: lead.email || "",
    phone: lead.phone || "",
    address: lead.address || "",
    hs_lead_status: "NEW",
  };

  if (lead.notes) {
    properties.notes = lead.notes;
  }

  const payload = {
    properties,
  };

  const response = await fetch("https://api.hubapi.com/crm/v3/objects/contacts", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${integration.access_token}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`HubSpot API error: ${response.status} - ${errorText}`);
  }

  return true;
}

async function syncToMonday(lead: LeadPayload, integration: UserIntegration): Promise<boolean> {
  if (!integration.access_token) {
    throw new Error("Monday.com access token not found");
  }

  // Monday.com uses GraphQL
  const mutation = `
    mutation ($boardId: ID!, $itemName: String!, $columnValues: JSON!) {
      create_item(board_id: $boardId, item_name: $itemName, column_values: $columnValues) {
        id
      }
    }
  `;

  // Note: This requires a board_id to be configured. For now, we'll use a simplified approach
  // In production, you'd want to store board_id in the integration or use a default board
  const columnValues = JSON.stringify({
    name: { text: lead.name || "New Lead" },
    email: { email: lead.email || "", text: lead.email || "" },
    phone: { phone: lead.phone || "", countryShortName: "US" },
    address: { text: lead.address || "" },
    source: { text: lead.source || "FLYR" },
  });

  const variables = {
    boardId: "YOUR_BOARD_ID", // This should be configurable per user
    itemName: lead.name || "New Lead",
    columnValues: columnValues,
  };

  const response = await fetch("https://api.monday.com/v2", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: integration.access_token,
      "API-Version": "2023-10",
    },
    body: JSON.stringify({
      query: mutation,
      variables,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Monday.com API error: ${response.status} - ${errorText}`);
  }

  const result = await response.json();
  if (result.errors) {
    throw new Error(`Monday.com GraphQL error: ${JSON.stringify(result.errors)}`);
  }

  return true;
}

async function syncToZapier(lead: LeadPayload, integration: UserIntegration): Promise<boolean> {
  if (!integration.webhook_url) {
    throw new Error("Zapier webhook URL not found");
  }

  const payload = {
    name: lead.name,
    phone: lead.phone,
    email: lead.email,
    address: lead.address,
    source: lead.source || "FLYR",
    campaign_id: lead.campaign_id,
    notes: lead.notes,
    created_at: lead.created_at,
  };

  const response = await fetch(integration.webhook_url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Zapier webhook error: ${response.status} - ${errorText}`);
  }

  return true;
}


