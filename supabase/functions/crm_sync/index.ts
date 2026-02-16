import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
serve(async (req)=>{
  try {
    // Parse request
    const { lead, user_id } = await req.json();
    if (!lead || !user_id) {
      return new Response(JSON.stringify({
        error: "Missing lead or user_id"
      }), {
        status: 400,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Validate lead has at least one contact field
    const hasContactInfo = lead.name && lead.name.trim() || lead.phone && lead.phone.trim() || lead.email && lead.email.trim() || lead.address && lead.address.trim();
    if (!hasContactInfo) {
      return new Response(JSON.stringify({
        error: "Lead missing contact information"
      }), {
        status: 400,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseKey);
    // Get auth token from request
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({
        error: "Missing authorization header"
      }), {
        status: 401,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Create authenticated client
    const token = authHeader.replace("Bearer ", "");
    const supabaseAuth = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });
    // Fetch user's active integrations
    const { data: integrations, error: fetchError } = await supabaseAuth.from("user_integrations").select("*").eq("user_id", user_id);
    if (fetchError) {
      console.error("Error fetching integrations:", fetchError);
      return new Response(JSON.stringify({
        error: "Failed to fetch integrations"
      }), {
        status: 500,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    console.log("Found integrations:", integrations);
    if (!integrations || integrations.length === 0) {
      return new Response(JSON.stringify({
        message: "No integrations found",
        synced: []
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Sync to each connected integration
    const results = [];
    for (const integration of integrations){
      try {
        let success = false;
        let error;
        switch(integration.provider){
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
        results.push({
          provider: integration.provider,
          success,
          error
        });
      } catch (err) {
        console.error(`Error syncing to ${integration.provider}:`, err);
        results.push({
          provider: integration.provider,
          success: false,
          error: err instanceof Error ? err.message : "Unknown error"
        });
      }
    }
    return new Response(JSON.stringify({
      message: "Sync completed",
      synced: results.filter((r)=>r.success).map((r)=>r.provider),
      failed: results.filter((r)=>!r.success)
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    console.error("Error in crm_sync:", err);
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : "Unknown error"
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});
// ============================================================================
// CRM Sync Functions
// ============================================================================
async function syncToFUB(lead, integration) {
  // FUB can use either api_key (from crm_connection_secrets) or access_token (from user_integrations)
  const fubToken = integration.api_key || integration.access_token;
  console.log("FUB integration:", {
    provider: integration.provider,
    hasApiKey: !!integration.api_key,
    hasAccessToken: !!integration.access_token,
    tokenLength: fubToken?.length,
    tokenPrefix: fubToken?.substring(0, 10)
  });
  if (!fubToken) {
    throw new Error("FUB API key not found");
  }
  // Build payload - only include notes if present (FUB uses 'description' for notes)
  const payload: any = {
    firstName: lead.name?.split(" ")[0] || "",
    lastName: lead.name?.split(" ").slice(1).join(" ") || "",
    emails: lead.email ? [
      {
        address: lead.email,
        type: "work"
      }
    ] : [],
    phones: lead.phone ? [
      {
        number: lead.phone,
        type: "mobile"
      }
    ] : [],
    addresses: lead.address ? [
      {
        street: lead.address,
        city: "",
        state: "",
        zip: "",
        country: "US"
      }
    ] : [],
    source: lead.source || "FLYR"
  };
  
  // Only add description if notes exist
  if (lead.notes && lead.notes.trim()) {
    payload.description = lead.notes.trim();
  }
  // FUB uses Basic auth for API keys: base64(api_key:)
  const authHeader = "Basic " + btoa(fubToken + ":");
  const response = await fetch("https://api.followupboss.com/v1/people", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: authHeader
    },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`FUB API error: ${response.status} - ${errorText}`);
  }
  const personData = await response.json();
  const personId = personData?.id ?? null;

  // Create task in FUB if provided (requires person id from create)
  if (lead.task && personId != null) {
    const dueDate = lead.task.due_date; // YYYY-MM-DD from client
    const taskPayload: Record<string, unknown> = {
      personId: Number(personId),
      name: lead.task.title || "Follow up",
      type: "Follow Up",
      dueDate: dueDate
    };
    const taskRes = await fetch("https://api.followupboss.com/v1/tasks", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authHeader
      },
      body: JSON.stringify(taskPayload)
    });
    if (!taskRes.ok) {
      const errText = await taskRes.text();
      console.warn("FUB task create failed:", errText);
    }
  }

  // Create appointment in FUB if provided
  if (lead.appointment && personId != null) {
    const dateStr = lead.appointment.date; // ISO8601 from client
    const startDate = new Date(dateStr);
    const endDate = new Date(startDate.getTime() + 60 * 60 * 1000); // +1 hour
    const toISO = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, "Z");
    const appointmentPayload: Record<string, unknown> = {
      title: lead.appointment.title?.trim() || "FLYR Appointment",
      start: toISO(startDate),
      end: toISO(endDate),
      invitees: [
        {
          personId: Number(personId),
          name: lead.name || "",
          email: lead.email || ""
        }
      ]
    };
    if (lead.appointment.notes?.trim()) {
      appointmentPayload.description = lead.appointment.notes.trim();
    }
    const apptRes = await fetch("https://api.followupboss.com/v1/appointments", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authHeader
      },
      body: JSON.stringify(appointmentPayload)
    });
    if (!apptRes.ok) {
      const errText = await apptRes.text();
      console.warn("FUB appointment create failed:", errText);
    }
  }

  return true;
}
async function syncToKVCore(lead, integration) {
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
    notes: lead.notes || ""
  };
  const response = await fetch("https://api.kvcore.com/v1/leads", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${integration.api_key}`
    },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`KVCore API error: ${response.status} - ${errorText}`);
  }
  return true;
}
async function syncToHubSpot(lead, integration) {
  if (!integration.access_token) {
    throw new Error("HubSpot access token not found");
  }
  const properties = {
    firstname: lead.name?.split(" ")[0] || "",
    lastname: lead.name?.split(" ").slice(1).join(" ") || "",
    email: lead.email || "",
    phone: lead.phone || "",
    address: lead.address || "",
    hs_lead_status: "NEW"
  };
  if (lead.notes) {
    properties.notes = lead.notes;
  }
  const payload = {
    properties
  };
  const response = await fetch("https://api.hubapi.com/crm/v3/objects/contacts", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${integration.access_token}`
    },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`HubSpot API error: ${response.status} - ${errorText}`);
  }
  return true;
}
async function syncToMonday(lead, integration) {
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
    name: {
      text: lead.name || "New Lead"
    },
    email: {
      email: lead.email || "",
      text: lead.email || ""
    },
    phone: {
      phone: lead.phone || "",
      countryShortName: "US"
    },
    address: {
      text: lead.address || ""
    },
    source: {
      text: lead.source || "FLYR"
    }
  });
  const variables = {
    boardId: "YOUR_BOARD_ID",
    itemName: lead.name || "New Lead",
    columnValues: columnValues
  };
  const response = await fetch("https://api.monday.com/v2", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: integration.access_token,
      "API-Version": "2023-10"
    },
    body: JSON.stringify({
      query: mutation,
      variables
    })
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
async function syncToZapier(lead, integration) {
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
    created_at: lead.created_at
  };
  const response = await fetch(integration.webhook_url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Zapier webhook error: ${response.status} - ${errorText}`);
  }
  return true;
}
