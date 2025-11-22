import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

interface OAuthExchangeRequest {
  provider: "hubspot" | "monday";
  code: string;
  user_id: string;
}

serve(async (req) => {
  try {
    const { provider, code, user_id }: OAuthExchangeRequest = await req.json();

    if (!provider || !code || !user_id) {
      return new Response(
        JSON.stringify({ error: "Missing provider, code, or user_id" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (provider !== "hubspot" && provider !== "monday") {
      return new Response(
        JSON.stringify({ error: "Invalid provider. Must be 'hubspot' or 'monday'" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client with service role for token updates
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let accessToken: string;
    let refreshToken: string | undefined;
    let expiresAt: number | undefined;

    // Exchange authorization code for tokens
    if (provider === "hubspot") {
      const tokens = await exchangeHubSpotCode(code);
      accessToken = tokens.access_token;
      refreshToken = tokens.refresh_token;
      expiresAt = tokens.expires_in
        ? Math.floor(Date.now() / 1000) + tokens.expires_in
        : undefined;
    } else {
      // Monday.com
      const tokens = await exchangeMondayCode(code);
      accessToken = tokens.access_token;
      refreshToken = tokens.refresh_token;
      expiresAt = tokens.expires_in
        ? Math.floor(Date.now() / 1000) + tokens.expires_in
        : undefined;
    }

    // Upsert integration in database
    const { data, error } = await supabase
      .from("user_integrations")
      .upsert(
        {
          user_id: user_id,
          provider: provider,
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_at: expiresAt,
          updated_at: new Date().toISOString(),
        },
        {
          onConflict: "user_id,provider",
        }
      )
      .select()
      .single();

    if (error) {
      console.error("Error upserting integration:", error);
      return new Response(
        JSON.stringify({ error: "Failed to save integration" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        provider: provider,
        message: "Integration connected successfully",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("Error in oauth_exchange:", err);
    return new Response(
      JSON.stringify({
        error: err instanceof Error ? err.message : "Unknown error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

// ============================================================================
// OAuth Token Exchange Functions
// ============================================================================

async function exchangeHubSpotCode(code: string): Promise<{
  access_token: string;
  refresh_token: string;
  expires_in: number;
}> {
  const clientId = Deno.env.get("HUBSPOT_CLIENT_ID");
  const clientSecret = Deno.env.get("HUBSPOT_CLIENT_SECRET");
  const redirectUri = Deno.env.get("HUBSPOT_REDIRECT_URI") || "flyr://oauth";

  if (!clientId || !clientSecret) {
    throw new Error("HubSpot OAuth credentials not configured");
  }

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientId,
    client_secret: clientSecret,
    redirect_uri: redirectUri,
    code: code,
  });

  const response = await fetch("https://api.hubapi.com/oauth/v1/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`HubSpot token exchange failed: ${response.status} - ${errorText}`);
  }

  const data = await response.json();
  return {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_in: data.expires_in || 3600,
  };
}

async function exchangeMondayCode(code: string): Promise<{
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
}> {
  const clientId = Deno.env.get("MONDAY_CLIENT_ID");
  const clientSecret = Deno.env.get("MONDAY_CLIENT_SECRET");
  const redirectUri = Deno.env.get("MONDAY_REDIRECT_URI") || "flyr://oauth";

  if (!clientId || !clientSecret) {
    throw new Error("Monday.com OAuth credentials not configured");
  }

  const params = new URLSearchParams({
    code: code,
    client_id: clientId,
    client_secret: clientSecret,
    redirect_uri: redirectUri,
  });

  const response = await fetch("https://auth.monday.com/oauth2/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Monday.com token exchange failed: ${response.status} - ${errorText}`);
  }

  const data = await response.json();
  return {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_in: data.expires_in,
  };
}


