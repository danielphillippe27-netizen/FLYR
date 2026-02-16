import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getFubApiKeyForUser } from "../../../../lib/crm-auth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const FUB_API_BASE = "https://api.followupboss.com/v1";

type PushLeadBody = {
  firstName?: string;
  lastName?: string;
  email?: string;
  phone?: string;
  address?: string;
  city?: string;
  state?: string;
  zip?: string;
  message?: string;
  source?: string;
  sourceUrl?: string;
  campaignId?: string;
  metadata?: Record<string, unknown>;
};

function buildFubEvent(body: PushLeadBody) {
  const hasEmail = body.email != null && String(body.email).trim() !== "";
  const hasPhone = body.phone != null && String(body.phone).trim() !== "";
  if (!hasEmail && !hasPhone) {
    throw new Error("At least one of email or phone is required");
  }

  const person: Record<string, unknown> = {
    firstName: body.firstName ?? "",
    lastName: body.lastName ?? "",
  };
  if (hasEmail) {
    person.emails = [{ value: String(body.email).trim() }];
  }
  if (hasPhone) {
    person.phones = [{ value: String(body.phone).trim() }];
  }
  if (body.address || body.city || body.state || body.zip) {
    person.addresses = [
      {
        street: body.address ?? "",
        city: body.city ?? "",
        state: body.state ?? "",
        code: body.zip ?? "",
        country: "US",
      },
    ];
  }

  return {
    source: body.source ?? "FLYR",
    system: "FLYR",
    type: "General Inquiry",
    message: body.message ?? "",
    person,
  };
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

    const apiKey = await getFubApiKeyForUser(
      createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY),
      user.id
    );
    if (!apiKey) {
      return NextResponse.json(
        { success: false, error: "Follow Up Boss not connected" },
        { status: 400 }
      );
    }

    const body = (await request.json()) as PushLeadBody;
    let event: ReturnType<typeof buildFubEvent>;
    try {
      event = buildFubEvent(body);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Invalid request";
      return NextResponse.json({ success: false, error: msg }, { status: 400 });
    }

    const basicAuth = Buffer.from(`${apiKey}:`).toString("base64");
    const res = await fetch(`${FUB_API_BASE}/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${basicAuth}`,
      },
      body: JSON.stringify(event),
    });

    if (res.status === 204) {
      return NextResponse.json({
        success: true,
        message: "Lead flow archived; event not created.",
      });
    }
    if (res.status === 404) {
      return NextResponse.json({ success: false, error: "Person not found" }, { status: 404 });
    }
    if (!res.ok) {
      const text = await res.text();
      return NextResponse.json(
        { success: false, error: text || `FUB returned ${res.status}` },
        { status: 502 }
      );
    }

    let fubEventId: string | undefined;
    try {
      const data = await res.json();
      fubEventId = data?.id != null ? String(data.id) : undefined;
    } catch {
      // ignore
    }

    return NextResponse.json({
      success: true,
      message: "Lead pushed to Follow Up Boss",
      fubEventId,
    });
  } catch (err) {
    console.error("[fub/push-lead]", err);
    return NextResponse.json(
      { success: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
