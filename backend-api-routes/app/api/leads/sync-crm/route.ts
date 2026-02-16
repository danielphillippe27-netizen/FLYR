import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getFubApiKeyForUser } from "../../../lib/crm-auth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const FUB_API_BASE = "https://api.followupboss.com/v1";

const SYNC_LIMIT = 500;

type ContactRow = {
  id: string;
  full_name: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
};

async function pushContactToFub(
  apiKey: string,
  contact: ContactRow
): Promise<{ ok: boolean; error?: string }> {
  const hasEmail = contact.email != null && String(contact.email).trim() !== "";
  const hasPhone = contact.phone != null && String(contact.phone).trim() !== "";
  if (!hasEmail && !hasPhone) return { ok: false, error: "No email or phone" };

  const parts = (contact.full_name ?? "").trim().split(/\s+/);
  const firstName = parts[0] ?? "";
  const lastName = parts.slice(1).join(" ") ?? "";

  const person: Record<string, unknown> = {
    firstName,
    lastName,
  };
  if (hasEmail) person.emails = [{ value: String(contact.email).trim() }];
  if (hasPhone) person.phones = [{ value: String(contact.phone).trim() }];
  if (contact.address?.trim()) {
    person.addresses = [{ street: contact.address.trim(), country: "US" }];
  }

  const event = {
    source: "FLYR",
    system: "FLYR",
    type: "General Inquiry" as const,
    message: "",
    person,
  };

  const basicAuth = Buffer.from(`${apiKey}:`).toString("base64");
  const res = await fetch(`${FUB_API_BASE}/events`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${basicAuth}`,
    },
    body: JSON.stringify(event),
  });

  if (res.status === 204 || res.ok) return { ok: true };
  const text = await res.text();
  return { ok: false, error: `${res.status}: ${text}` };
}

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ success: false, error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: { user }, error: userError } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ success: false, error: "Invalid or expired token" }, { status: 401 });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const apiKey = await getFubApiKeyForUser(supabaseAdmin, user.id);
    if (!apiKey) {
      return NextResponse.json(
        { success: false, error: "Follow Up Boss not connected" },
        { status: 400 }
      );
    }

    const { data: contacts, error: fetchError } = await supabaseAdmin
      .from("contacts")
      .select("id, full_name, phone, email, address")
      .eq("user_id", user.id)
      .limit(SYNC_LIMIT);

    if (fetchError) {
      console.error("[sync-crm] fetch contacts", fetchError);
      return NextResponse.json(
        { success: false, error: "Failed to fetch contacts" },
        { status: 500 }
      );
    }

    const rows = (contacts ?? []) as ContactRow[];
    let synced = 0;
    const errors: string[] = [];
    for (const contact of rows) {
      const result = await pushContactToFub(apiKey, contact);
      if (result.ok) synced++;
      else if (result.error && errors.length < 5) errors.push(result.error);
    }

    return NextResponse.json({
      success: true,
      message: `Synced ${synced} of ${rows.length} contacts to Follow Up Boss`,
      synced,
    });
  } catch (err) {
    console.error("[sync-crm]", err);
    return NextResponse.json(
      { success: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
