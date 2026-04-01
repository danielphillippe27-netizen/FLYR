import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { getHubSpotAccessTokenForUser } from "../../../../lib/hubspot-auth";
import { pushLeadToHubSpot, type PushLeadInput } from "../../../../lib/hubspot-crm";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RawBody = {
  id?: string;
  name?: string;
  email?: string;
  phone?: string;
  address?: string;
  notes?: string;
  source?: string;
  campaign_id?: string;
  campaignId?: string;
  created_at?: string;
  createdAt?: string;
  task?: { title?: string; due_date?: string };
  appointment?: { date?: string; title?: string; notes?: string };
};

function normalizeLead(body: RawBody): PushLeadInput | null {
  const id = typeof body.id === "string" ? body.id.trim() : "";
  if (!id) return null;

  return {
    id,
    name: typeof body.name === "string" ? body.name : undefined,
    email: typeof body.email === "string" ? body.email : undefined,
    phone: typeof body.phone === "string" ? body.phone : undefined,
    address: typeof body.address === "string" ? body.address : undefined,
    notes: typeof body.notes === "string" ? body.notes : undefined,
    source: typeof body.source === "string" ? body.source : undefined,
    campaignId: body.campaignId ?? body.campaign_id,
    createdAt: body.createdAt ?? body.created_at,
    task: body.task,
    appointment: body.appointment,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- crm_object_links not in generated DB types
type AdminClient = any;

async function getLinkedContactId(
  supabaseAdmin: AdminClient,
  userId: string,
  leadId: string
): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from("crm_object_links")
    .select("remote_object_id")
    .eq("user_id", userId)
    .eq("crm_type", "hubspot")
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (error) {
    console.error("[hubspot/push-lead] crm_object_links read", error);
    return null;
  }
  if (!data) return null;
  const rid = data.remote_object_id;
  return typeof rid === "string" && rid.trim() ? rid.trim() : null;
}

async function upsertHubSpotLink(
  supabaseAdmin: AdminClient,
  userId: string,
  leadId: string,
  contactId: string
) {
  const { data: existing, error: existingError } = await supabaseAdmin
    .from("crm_object_links")
    .select("id")
    .eq("user_id", userId)
    .eq("crm_type", "hubspot")
    .eq("flyr_lead_id", leadId)
    .maybeSingle();

  if (existingError) {
    console.error("[hubspot/push-lead] link lookup", existingError);
    return;
  }

  const payload = {
    remote_object_id: contactId,
    remote_object_type: "contact",
    remote_metadata: { provider: "hubspot" },
    fub_person_id: null,
  };

  if (existing && existing.id) {
    await supabaseAdmin.from("crm_object_links").update(payload).eq("id", existing.id);
    return;
  }

  await supabaseAdmin.from("crm_object_links").insert({
    user_id: userId,
    crm_type: "hubspot",
    flyr_lead_id: leadId,
    ...payload,
  });
}

export async function POST(request: Request) {
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

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const accessToken = await getHubSpotAccessTokenForUser(supabaseAdmin, user.id);
    if (!accessToken) {
      return NextResponse.json({ success: false, error: "HubSpot is not connected" }, { status: 404 });
    }

    const raw = (await request.json()) as RawBody;
    const lead = normalizeLead(raw);
    if (!lead) {
      return NextResponse.json({ success: false, error: "Lead id is required" }, { status: 400 });
    }

    const linkedId = await getLinkedContactId(supabaseAdmin, user.id, lead.id);
    const result = await pushLeadToHubSpot(accessToken, lead, { existingContactId: linkedId });

    if (!result.success) {
      return NextResponse.json(
        { success: false, error: result.error || "HubSpot push failed" },
        { status: 400 }
      );
    }

    if (result.contactId) {
      await upsertHubSpotLink(supabaseAdmin, user.id, lead.id, result.contactId);
    }

    const partial = result.partialErrors?.length;
    return NextResponse.json({
      success: true,
      message: partial
        ? "Lead synced to HubSpot with some follow-up warnings."
        : "Lead synced to HubSpot",
      hubspotContactId: result.contactId ?? null,
      noteCreated: result.noteCreated,
      taskCreated: result.taskCreated,
      meetingCreated: result.meetingCreated,
      partialErrors: result.partialErrors,
    });
  } catch (error) {
    console.error("[hubspot/push-lead]", error);
    return NextResponse.json(
      { success: false, error: error instanceof Error ? error.message : "Something went wrong" },
      { status: 500 }
    );
  }
}
