import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getFubApiKeyForUser } from "../../../../lib/crm-auth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const FUB_API_BASE = "https://api.followupboss.com/v1";

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

    const event = {
      source: "FLYR",
      system: "FLYR",
      type: "General Inquiry",
      message: "Test lead from FLYR iOS app",
      person: {
        firstName: "FLYR",
        lastName: "Test",
        emails: [{ value: "test@flyrpro.app" }],
        phones: [{ value: "5555555555" }],
      },
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

    if (res.status === 204) {
      return NextResponse.json({
        success: true,
        message: "Test lead sent (flow archived; event not created).",
      });
    }
    if (!res.ok) {
      const text = await res.text();
      return NextResponse.json(
        { success: false, error: text || `FUB returned ${res.status}` },
        { status: 502 }
      );
    }

    return NextResponse.json({
      success: true,
      message: "Test lead sent to Follow Up Boss.",
    });
  } catch (err) {
    console.error("[fub/test-push]", err);
    return NextResponse.json(
      { success: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
