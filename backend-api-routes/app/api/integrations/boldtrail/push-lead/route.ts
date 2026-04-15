import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  BoldTrailAPIClient,
  BoldTrailAPIError,
  type BoldTrailLeadPayload,
} from "../../../../lib/boldtrail";
import { enrichBoldTrailLeadPayload } from "../../../../lib/crm-sparse-enrich";
import { getBoldTrailTokenForUser } from "../../../../lib/crm-auth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type PushLeadBody = BoldTrailLeadPayload & {
  created_at?: string;
  campaign_id?: string | null;
};

export async function POST(request: Request) {
  let parsedLead: PushLeadBody | null = null;
  let currentUserId: string | null = null;

  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ success: false, error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ success: false, error: "Invalid or expired token" }, { status: 401 });
    }
    currentUserId = user.id;

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const boldTrailToken = await getBoldTrailTokenForUser(supabaseAdmin, user.id);
    if (!boldTrailToken) {
      return NextResponse.json(
        { success: false, error: "BoldTrail is not connected" },
        { status: 404 }
      );
    }

    parsedLead = (await request.json()) as PushLeadBody;
    const lead = enrichBoldTrailLeadPayload(normalizeLead(parsedLead));
    if (!lead.id) {
      return NextResponse.json(
        { success: false, error: "Lead ID is required" },
        { status: 400 }
      );
    }
    if (!lead.email && !lead.phone) {
      return NextResponse.json(
        { success: false, error: "Lead must have at least one of email or phone for BoldTrail sync." },
        { status: 400 }
      );
    }

    const existingRemoteId = await getExistingRemoteId(supabaseAdmin, user.id, lead.id);
    const client = new BoldTrailAPIClient();

    const result = existingRemoteId
      ? await client.updateContact(boldTrailToken, existingRemoteId, lead)
      : await client.createContact(boldTrailToken, lead);

    await upsertBoldTrailLink(supabaseAdmin, user.id, lead.id, result.contactId);
    await updateLeadSyncState(supabaseAdmin, user.id, lead.id, {
      remoteObjectId: result.contactId,
      syncStatus: "synced",
    });
    await updateConnectionSyncStatus(supabaseAdmin, user.id, {
      errorReason: null,
      lastSyncAt: new Date().toISOString(),
    });

    console.info("[boldtrail/push-lead]", {
      userId: user.id,
      leadId: lead.id,
      remoteContactId: result.contactId,
      action: result.action,
    });

    return NextResponse.json({
      success: true,
      message: "Lead synced to BoldTrail",
      remoteContactId: result.contactId,
      action: result.action,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "BoldTrail sync failed";
    console.error("[boldtrail/push-lead]", {
      error: message,
      kind: error instanceof BoldTrailAPIError ? error.kind : "unknown",
    });

    try {
      if (currentUserId) {
        const leadId = typeof parsedLead?.id === "string" ? parsedLead.id : null;
        const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
        if (leadId) {
          await updateLeadSyncState(supabaseAdmin, currentUserId, leadId, {
            syncStatus: "failed",
          });
        }
        await updateConnectionSyncStatus(supabaseAdmin, currentUserId, {
          errorReason: message,
        });
      }
    } catch {
      // Best-effort sync status updates should never mask the original error.
    }

    const status =
      error instanceof BoldTrailAPIError && error.kind === "invalid_token"
        ? 401
        : error instanceof BoldTrailAPIError && error.kind === "network"
          ? 502
          : 500;
    return NextResponse.json({ success: false, error: message }, { status });
  }
}

function normalizeLead(body: PushLeadBody): PushLeadBody {
  return {
    id: cleaned(body.id),
    name: cleaned(body.name),
    phone: cleaned(body.phone),
    email: cleaned(body.email),
    address: cleaned(body.address),
    source: cleaned(body.source) || "FLYR",
    notes: cleaned(body.notes),
    created_at: cleaned(body.created_at),
    campaign_id: cleaned(body.campaign_id),
  };
}

function cleaned(value?: string | null): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

async function getExistingRemoteId(
  supabaseAdmin: any,
  userId: string,
  leadId: string
): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from("crm_object_links")
    .select("remote_object_id")
    .eq("user_id", userId)
    .eq("crm_type", "boldtrail")
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (error) {
    console.error("[boldtrail/push-lead] failed to load crm_object_links row", error);
    return null;
  }

  return data?.remote_object_id ? String(data.remote_object_id) : null;
}

async function upsertBoldTrailLink(
  supabaseAdmin: any,
  userId: string,
  leadId: string,
  remoteObjectId: string
) {
  const { data: existing, error: existingError } = await supabaseAdmin
    .from("crm_object_links")
    .select("id")
    .eq("user_id", userId)
    .eq("crm_type", "boldtrail")
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }

  const payload = {
    remote_object_id: remoteObjectId,
    remote_object_type: "contact",
    remote_metadata: {
      provider: "boldtrail",
    },
    fub_person_id: null,
  };

  if (existing?.id) {
    const { error } = await supabaseAdmin
      .from("crm_object_links")
      .update(payload)
      .eq("id", existing.id);
    if (error) throw error;
    return;
  }

  const { error } = await supabaseAdmin
    .from("crm_object_links")
    .insert({
      user_id: userId,
      crm_type: "boldtrail",
      flyr_lead_id: leadId,
      ...payload,
    });
  if (error) throw error;
}

async function updateLeadSyncState(
  supabaseAdmin: any,
  userId: string,
  leadId: string,
  update: {
    remoteObjectId?: string;
    syncStatus: "synced" | "failed";
  }
) {
  const now = new Date().toISOString();
  const payload = {
    external_crm_id: update.remoteObjectId ?? undefined,
    last_synced_at: update.syncStatus === "synced" ? now : undefined,
    sync_status: update.syncStatus,
    updated_at: now,
  };

  await supabaseAdmin
    .from("contacts")
    .update(payload)
    .eq("id", leadId)
    .eq("user_id", userId);

  await supabaseAdmin
    .from("field_leads")
    .update(payload)
    .eq("id", leadId)
    .eq("user_id", userId);
}

async function updateConnectionSyncStatus(
  supabaseAdmin: any,
  userId: string,
  update: {
    errorReason: string | null;
    lastSyncAt?: string;
  }
) {
  await supabaseAdmin
    .from("crm_connections")
    .update({
      error_reason: update.errorReason,
      last_sync_at: update.lastSyncAt,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId)
    .eq("provider", "boldtrail");
}
