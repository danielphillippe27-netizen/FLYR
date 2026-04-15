import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  mondayGraphQLRequest,
  mondayPseudoValues,
  resolveMondayColumnMapping,
  type MondayColumn,
  type MondayColumnMappingEntry,
} from "../_shared/monday.ts";

const BOLDTRAIL_API_BASE = (Deno.env.get("BOLDTRAIL_API_BASE") ?? "https://api.kvcore.com").replace(/\/$/, "");

serve(async (req)=>{
  try {
    // Parse request
    const { lead, user_id, exclude_providers } = await req.json();
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
    const supabaseAuth = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = serviceRoleKey ? createClient(supabaseUrl, serviceRoleKey) : null;
    // Fetch user's active integrations
    const { data: userIntegrations, error: fetchError } = await supabaseAuth.from("user_integrations").select("*").eq("user_id", user_id);
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
    const integrations = [...(userIntegrations ?? [])];
    if (supabaseAdmin) {
      const { data: boldTrailConnection, error: boldTrailError } = await supabaseAdmin
        .from("crm_connections")
        .select("id")
        .eq("user_id", user_id)
        .eq("provider", "boldtrail")
        .eq("status", "connected")
        .maybeSingle();
      if (boldTrailError) {
        console.error("[crm_sync] failed to fetch boldtrail connection", boldTrailError);
      } else if (boldTrailConnection?.id) {
        integrations.push({
          provider: "boldtrail",
          connection_id: boldTrailConnection.id,
        });
      }
    }
    console.log("Found integrations:", integrations.map((integration)=>integration.provider));
    if (integrations.length === 0) {
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
    const excludedProviders = new Set<string>(
      Array.isArray(exclude_providers)
        ? exclude_providers
            .map((provider: unknown)=>typeof provider === "string" ? provider.trim().toLowerCase() : "")
            .filter((provider: string)=>provider.length > 0)
        : []
    );
    // Sync to each connected integration
    const results = [];
    for (const integration of integrations){
      if (excludedProviders.has(String(integration.provider ?? "").toLowerCase())) {
        results.push({
          provider: integration.provider,
          success: true,
          skipped: true
        });
        continue;
      }
      try {
        let success = false;
        let error;
        switch(integration.provider){
          case "boldtrail":
            success = await syncToBoldTrail(lead, user_id, supabaseAdmin, supabaseAuth);
            break;
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
            success = await syncToMonday(lead, integration, supabaseAuth, user_id);
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
      synced: results.filter((r)=>r.success && !r.skipped).map((r)=>r.provider),
      skipped: results.filter((r)=>r.skipped).map((r)=>r.provider),
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
/** @param integration { api_key?: string | null; access_token?: string | null } */
function fubIntegrationAuthHeaders(integration) {
  const access =
    typeof integration.access_token === "string" ? integration.access_token.trim() : "";
  const apiKey = typeof integration.api_key === "string" ? integration.api_key.trim() : "";
  // OAuth tokens require Bearer; API keys use Basic per FUB docs.
  if (access) {
    return {
      Authorization: `Bearer ${access}`,
      "X-System": "FLYR"
    };
  }
  if (apiKey) {
    return {
      Authorization: "Basic " + btoa(apiKey + ":"),
      "X-System": "FLYR"
    };
  }
  throw new Error("FUB credentials not found (OAuth access_token or API key required)");
}

async function syncToFUB(lead, integration) {
  const authHeaders = fubIntegrationAuthHeaders(integration);
  console.log("FUB integration:", {
    provider: integration.provider,
    hasApiKey: !!integration.api_key,
    hasAccessToken: !!integration.access_token,
    authMode: integration.access_token?.trim() ? "bearer" : "basic"
  });
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
  const response = await fetch("https://api.followupboss.com/v1/people", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...authHeaders
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
        ...authHeaders
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
        ...authHeaders
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

async function syncToBoldTrail(lead, userId, supabaseAdmin, supabaseAuth) {
  if (!supabaseAdmin) {
    throw new Error("BoldTrail sync requires SUPABASE_SERVICE_ROLE_KEY");
  }

  const accessToken = await getBoldTrailAccessToken(supabaseAdmin, userId);
  if (!accessToken) {
    throw new Error("BoldTrail token not found");
  }

  const existingContactId = await findExistingRemoteObjectId(supabaseAuth, userId, "boldtrail", lead.id);
  const payload = buildBoldTrailContactPayload(lead);
  let remoteContactId = existingContactId;

  if (existingContactId) {
    await boldTrailRequest(
      accessToken,
      `${BOLDTRAIL_API_BASE}/v2/public/contact/${encodeURIComponent(existingContactId)}`,
      "PUT",
      payload,
    );
    console.log("[crm_sync] boldtrail contact updated", { userId, leadId: lead.id, remoteContactId: existingContactId });
  } else {
    const created = await boldTrailRequest(
      accessToken,
      `${BOLDTRAIL_API_BASE}/v2/public/contact`,
      "POST",
      payload,
    );
    remoteContactId = extractBoldTrailContactId(created);
    if (!remoteContactId) {
      throw new Error("BoldTrail did not return a contact ID");
    }
    console.log("[crm_sync] boldtrail contact created", { userId, leadId: lead.id, remoteContactId });
  }

  await upsertRemoteObjectLink(supabaseAuth, userId, "boldtrail", lead.id, remoteContactId, "contact", {
    provider: "boldtrail",
  });
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

async function syncToMonday(lead, integration, supabaseAuth, userId) {
  if (!integration.access_token) {
    throw new Error("Monday.com access token not found");
  }
  if (!integration.selected_board_id) {
    throw new Error("Monday.com is connected but no board is selected");
  }

  const board = await fetchMondayBoard(integration.access_token, String(integration.selected_board_id));
  if (!board) {
    throw new Error("Selected monday.com board could not be loaded");
  }

  const mapping = resolveMondayColumnMapping(
    board.columns,
    integration.provider_config?.columnMapping ?? null
  );
  console.log("[crm_sync] monday mapping resolved", {
    userId,
    boardId: board.id,
    mappedFields: Object.keys(mapping),
  });

  const itemName = trimmed(lead.name) || trimmed(lead.email) || trimmed(lead.phone) || "FLYR Lead";
  const columnValues = buildMondayColumnValues(lead, board.columns, mapping);
  const existingItemId = await findExistingMondayItemId(supabaseAuth, userId, lead.id);

  let mondayItemId: string;
  if (existingItemId) {
    await updateMondayItem(integration.access_token, board.id, existingItemId, columnValues);
    mondayItemId = existingItemId;
    console.log("[crm_sync] monday item updated", { userId, boardId: board.id, itemId: mondayItemId });
  } else {
    mondayItemId = await createMondayItem(integration.access_token, board.id, itemName, columnValues);
    console.log("[crm_sync] monday item created", { userId, boardId: board.id, itemId: mondayItemId });
  }

  const notesText = trimmed(lead.notes);
  const notesMapping = mapping.notes;
  if (notesText && notesMapping?.strategy === "update_comment") {
    await createMondayUpdate(integration.access_token, mondayItemId, notesText);
    console.log("[crm_sync] monday item update created", { userId, boardId: board.id, itemId: mondayItemId });
  }

  await upsertMondayLink(supabaseAuth, userId, lead.id, mondayItemId, board.id, board.name);
  return true;
}

async function fetchMondayBoard(accessToken, boardId) {
  const data = await mondayGraphQLRequest<{
    boards: Array<{
      id: string | number;
      name: string;
      columns: Array<{ id: string; title: string; type: string }>;
    }>;
  }>(
    accessToken,
    `
      query ($boardId: [ID!]) {
        boards(ids: $boardId) {
          id
          name
          columns {
            id
            title
            type
          }
        }
      }
    `,
    { boardId: [boardId] }
  );

  const board = data.boards?.[0];
  if (!board) return null;
  return {
    id: String(board.id),
    name: board.name,
    columns: (board.columns ?? []).map((column) => ({
      id: column.id,
      title: column.title,
      type: column.type,
    })),
  };
}

async function createMondayItem(accessToken, boardId, itemName, columnValues) {
  const data = await mondayGraphQLRequest<{
    create_item: { id: string | number };
  }>(
    accessToken,
    `
      mutation ($boardId: ID!, $itemName: String!, $columnValues: JSON!) {
        create_item(board_id: $boardId, item_name: $itemName, column_values: $columnValues) {
          id
        }
      }
    `,
    {
      boardId,
      itemName,
      columnValues: JSON.stringify(columnValues),
    }
  );

  return String(data.create_item.id);
}

async function updateMondayItem(accessToken, boardId, itemId, columnValues) {
  await mondayGraphQLRequest(
    accessToken,
    `
      mutation ($boardId: ID!, $itemId: ID!, $columnValues: JSON!) {
        change_multiple_column_values(board_id: $boardId, item_id: $itemId, column_values: $columnValues) {
          id
        }
      }
    `,
    {
      boardId,
      itemId,
      columnValues: JSON.stringify(columnValues),
    }
  );
}

async function createMondayUpdate(accessToken, itemId, body) {
  await mondayGraphQLRequest(
    accessToken,
    `
      mutation ($itemId: ID!, $body: String!) {
        create_update(item_id: $itemId, body: $body) {
          id
        }
      }
    `,
    { itemId, body }
  );
}

async function findExistingMondayItemId(supabaseAuth, userId, leadId) {
  const { data, error } = await supabaseAuth
    .from("crm_object_links")
    .select("remote_object_id")
    .eq("user_id", userId)
    .eq("crm_type", "monday")
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (error) {
    console.error("[crm_sync] failed to load monday crm_object_links row", error);
    throw new Error("Failed to load monday link state");
  }

  return data?.remote_object_id ? String(data.remote_object_id) : null;
}

async function upsertMondayLink(supabaseAuth, userId, leadId, itemId, boardId, boardName) {
  const { data: existing, error: existingError } = await supabaseAuth
    .from("crm_object_links")
    .select("id")
    .eq("user_id", userId)
    .eq("crm_type", "monday")
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (existingError) {
    console.error("[crm_sync] failed to lookup monday crm_object_links row", existingError);
    throw new Error("Failed to load monday remote link");
  }

  const payload = {
    remote_object_id: itemId,
    remote_object_type: "item",
    remote_metadata: {
      boardId,
      boardName,
    },
    fub_person_id: null,
  };

  if (existing?.id) {
    const { error } = await supabaseAuth
      .from("crm_object_links")
      .update(payload)
      .eq("id", existing.id);
    if (error) {
      console.error("[crm_sync] failed to update monday crm_object_links row", error);
      throw new Error("Failed to update monday remote link");
    }
    return;
  }

  const { error } = await supabaseAuth
    .from("crm_object_links")
    .insert({
      user_id: userId,
      crm_type: "monday",
      flyr_lead_id: leadId,
      ...payload,
    });
  if (error) {
    console.error("[crm_sync] failed to insert monday crm_object_links row", error);
    throw new Error("Failed to save monday remote link");
  }
}

async function getBoldTrailAccessToken(supabaseAdmin, userId) {
  const { data: connection, error: connectionError } = await supabaseAdmin
    .from("crm_connections")
    .select("id")
    .eq("user_id", userId)
    .eq("provider", "boldtrail")
    .eq("status", "connected")
    .maybeSingle();

  if (connectionError) {
    console.error("[crm_sync] failed to load boldtrail connection", connectionError);
    throw new Error("Failed to load BoldTrail connection");
  }
  if (!connection?.id) {
    return null;
  }

  const { data: secret, error: secretError } = await supabaseAdmin
    .from("crm_connection_secrets")
    .select("encrypted_api_key")
    .eq("connection_id", connection.id)
    .maybeSingle();

  if (secretError) {
    console.error("[crm_sync] failed to load boldtrail secret", secretError);
    throw new Error("Failed to load BoldTrail credentials");
  }

  const encrypted = typeof secret?.encrypted_api_key === "string" ? secret.encrypted_api_key.trim() : "";
  if (!encrypted) {
    return null;
  }

  return await decryptCRMSecret(encrypted);
}

async function decryptCRMSecret(encryptedBase64) {
  const keySource = Deno.env.get("CRM_ENCRYPTION_KEY") ?? "";
  if (!keySource || keySource.length < 32) {
    throw new Error("CRM_ENCRYPTION_KEY must be configured");
  }

  const blobJson = decodeBase64ToString(encryptedBase64);
  const blob = JSON.parse(blobJson);
  const keyBytes = deriveCRMEncryptionKey(keySource);
  const iv = decodeBase64ToBytes(blob.iv);
  const tag = decodeBase64ToBytes(blob.tag);
  const ciphertext = decodeBase64ToBytes(blob.ciphertext);
  const encryptedBytes = new Uint8Array(ciphertext.length + tag.length);
  encryptedBytes.set(ciphertext, 0);
  encryptedBytes.set(tag, ciphertext.length);

  const cryptoKey = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["decrypt"]);
  const decrypted = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv,
      tagLength: 128,
    },
    cryptoKey,
    encryptedBytes,
  );

  return new TextDecoder().decode(decrypted);
}

function deriveCRMEncryptionKey(keySource) {
  const normalized = keySource.trim();
  if (/^[0-9a-fA-F]+$/.test(normalized) && normalized.length >= 64) {
    const hexBytes = hexToBytes(normalized);
    if (hexBytes.length === 32) {
      return hexBytes;
    }
  }

  return new TextEncoder().encode(normalized.slice(0, 32));
}

function hexToBytes(hex) {
  const output = new Uint8Array(Math.floor(hex.length / 2));
  for (let index = 0; index < output.length; index += 1) {
    output[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return output;
}

async function boldTrailRequest(accessToken, url, method, body) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const rawText = await response.text();
  const payload = rawText.trim() ? safeJsonParse(rawText) : null;
  if (!response.ok) {
    throw new Error(normalizeBoldTrailError(response.status, payload, rawText));
  }

  return payload;
}

function buildBoldTrailContactPayload(lead) {
  const { firstName, lastName } = splitFullName(lead.name);
  return compactRecord({
    first_name: firstName,
    last_name: lastName,
    email: trimmed(lead.email) || undefined,
    cell_phone_1: trimmed(lead.phone) || undefined,
    primary_address: trimmed(lead.address) || undefined,
    source: trimmed(lead.source) || "FLYR",
    capture_method: "FLYR",
    external_vendor_id: trimmed(lead.id) || undefined,
  });
}

function extractBoldTrailContactId(payload) {
  if (!payload || typeof payload !== "object") return null;
  for (const key of ["id", "contact_id", "contactId"]) {
    const value = payload[key];
    if (value != null && String(value).trim()) {
      return String(value).trim();
    }
  }
  for (const key of ["data", "contact", "result"]) {
    const nestedValue = extractBoldTrailContactId(payload[key]);
    if (nestedValue) return nestedValue;
  }
  return null;
}

function normalizeBoldTrailError(status, payload, rawText) {
  const message = pickString(payload, ["message", "error", "detail", "details"])
    || rawText?.trim()
    || `BoldTrail returned ${status}.`;

  if (status === 401 || status === 403) {
    return "Invalid BoldTrail token";
  }
  if (status >= 500) {
    return "Unable to connect to BoldTrail right now.";
  }
  return message.length > 240 ? `${message.slice(0, 237)}...` : message;
}

function safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function pickString(payload, keys) {
  if (!payload || typeof payload !== "object") return null;
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

function splitFullName(name) {
  const value = trimmed(name);
  if (!value) {
    return { firstName: undefined, lastName: undefined };
  }
  const parts = value.split(/\s+/);
  return {
    firstName: parts[0],
    lastName: parts.length > 1 ? parts.slice(1).join(" ") : undefined,
  };
}

function compactRecord(record) {
  return Object.fromEntries(
    Object.entries(record).filter(([, value])=>value != null && value !== "")
  );
}

async function findExistingRemoteObjectId(supabaseAuth, userId, crmType, leadId) {
  const { data, error } = await supabaseAuth
    .from("crm_object_links")
    .select("remote_object_id")
    .eq("user_id", userId)
    .eq("crm_type", crmType)
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (error) {
    console.error(`[crm_sync] failed to load ${crmType} crm_object_links row`, error);
    throw new Error(`Failed to load ${crmType} link state`);
  }

  return data?.remote_object_id ? String(data.remote_object_id) : null;
}

async function upsertRemoteObjectLink(supabaseAuth, userId, crmType, leadId, remoteObjectId, remoteObjectType, remoteMetadata = {}) {
  const { data: existing, error: existingError } = await supabaseAuth
    .from("crm_object_links")
    .select("id")
    .eq("user_id", userId)
    .eq("crm_type", crmType)
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (existingError) {
    console.error(`[crm_sync] failed to lookup ${crmType} crm_object_links row`, existingError);
    throw new Error(`Failed to load ${crmType} remote link`);
  }

  const payload = {
    remote_object_id: remoteObjectId,
    remote_object_type: remoteObjectType,
    remote_metadata: remoteMetadata,
    fub_person_id: null,
  };

  if (existing?.id) {
    const { error } = await supabaseAuth
      .from("crm_object_links")
      .update(payload)
      .eq("id", existing.id);
    if (error) {
      console.error(`[crm_sync] failed to update ${crmType} crm_object_links row`, error);
      throw new Error(`Failed to update ${crmType} remote link`);
    }
    return;
  }

  const { error } = await supabaseAuth
    .from("crm_object_links")
    .insert({
      user_id: userId,
      crm_type: crmType,
      flyr_lead_id: leadId,
      ...payload,
    });
  if (error) {
    console.error(`[crm_sync] failed to insert ${crmType} crm_object_links row`, error);
    throw new Error(`Failed to save ${crmType} remote link`);
  }
}

function decodeBase64ToBytes(value) {
  const binary = atob(value);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function decodeBase64ToString(value) {
  return new TextDecoder().decode(decodeBase64ToBytes(value));
}

function buildMondayColumnValues(lead, columns: MondayColumn[], mapping: Record<string, MondayColumnMappingEntry>) {
  const pseudo = mondayPseudoValues();
  const columnTypeById = new Map(columns.map((column) => [column.id, column.type]));
  const values: Record<string, unknown> = {};

  setMappedValue(values, columnTypeById, mapping.phone, trimmed(lead.phone));
  setMappedValue(values, columnTypeById, mapping.email, trimmed(lead.email));
  setMappedValue(values, columnTypeById, mapping.address, trimmed(lead.address));

  if (mapping.notes?.strategy !== "update_comment") {
    setMappedValue(values, columnTypeById, mapping.notes, trimmed(lead.notes));
  }

  const followUpDate = trimmed(lead.task?.due_date);
  setMappedValue(values, columnTypeById, mapping.followUpDate, followUpDate);

  const appointmentStart = trimmed(lead.appointment?.date);
  const appointmentEnd = appointmentStart
    ? new Date(new Date(appointmentStart).getTime() + 60 * 60 * 1000).toISOString()
    : null;
  setMappedValue(values, columnTypeById, mapping.appointmentStart, appointmentStart);
  setMappedValue(values, columnTypeById, mapping.appointmentEnd, appointmentEnd);
  setMappedValue(values, columnTypeById, mapping.appointmentTitle, trimmed(lead.appointment?.title));

  if (mapping.status && mapping.status.columnId !== pseudo.itemName && mapping.status.columnId !== pseudo.itemUpdate) {
    setMappedValue(values, columnTypeById, mapping.status, trimmed(lead.status));
  }

  return values;
}

function setMappedValue(values, columnTypeById, mappingEntry, rawValue) {
  const pseudo = mondayPseudoValues();
  if (!mappingEntry?.columnId || mappingEntry.columnId === pseudo.itemName || mappingEntry.columnId === pseudo.itemUpdate) {
    return;
  }
  if (rawValue == null || rawValue === "") {
    return;
  }

  const columnType = normalizeMondayType(columnTypeById.get(mappingEntry.columnId));
  values[mappingEntry.columnId] = formatMondayValue(columnType, rawValue);
}

function formatMondayValue(columnType, rawValue) {
  switch (columnType) {
    case "email":
      return { email: rawValue, text: rawValue };
    case "phone":
      return { phone: rawValue, countryShortName: "US" };
    case "location":
      return { address: rawValue };
    case "status":
      return { label: rawValue };
    case "date":
    case "datetime":
      return formatMondayDateValue(rawValue);
    default:
      return rawValue;
  }
}

function formatMondayDateValue(rawValue) {
  const date = new Date(rawValue);
  if (Number.isNaN(date.getTime())) {
    return rawValue;
  }

  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const hours = String(date.getUTCHours()).padStart(2, "0");
  const minutes = String(date.getUTCMinutes()).padStart(2, "0");
  const seconds = String(date.getUTCSeconds()).padStart(2, "0");

  return {
    date: `${year}-${month}-${day}`,
    time: `${hours}:${minutes}:${seconds}`,
  };
}

function normalizeMondayType(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase();
}

function trimmed(value) {
  return typeof value === "string" ? value.trim() : "";
}
