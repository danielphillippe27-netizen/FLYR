import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { getHubSpotAccessTokenForUser } from "../../../../lib/hubspot-auth";
import { hubspotMinimalApiTest } from "../../../../lib/hubspot-crm";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

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

    const result = await hubspotMinimalApiTest(accessToken);
    if (!result.ok) {
      const status = /invalid|expired|scope/i.test(result.message) ? 400 : 502;
      return NextResponse.json({ success: false, error: result.message }, { status });
    }

    return NextResponse.json({
      success: true,
      message: result.message,
    });
  } catch (error) {
    console.error("[hubspot/test]", error);
    return NextResponse.json({ success: false, error: "Something went wrong" }, { status: 500 });
  }
}
