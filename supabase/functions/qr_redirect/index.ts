import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const url = new URL(req.url);

    // Extract slug from /q/<slug>
    const segments = url.pathname.split("/").filter(Boolean); // removes empty ""
    const slugIndex = segments.indexOf("q") + 1;
    const slug = segments[slugIndex];

    if (!slug) {
      return new Response("Not Found", { status: 404 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );

    // Lookup QR code by slug
    const { data: qrCode, error: qrError } = await supabase
      .from("qr_codes")
      .select("id, landing_page_id, campaign_id")
      .eq("slug", slug)
      .single();

    if (qrError || !qrCode) {
      return new Response("QR Code Not Found", { status: 404 });
    }

    if (!qrCode.landing_page_id) {
      return new Response("Landing page not found", { status: 404 });
    }

    // Get landing page slug
    const { data: landingPage, error: lpError } = await supabase
      .from("campaign_landing_pages")
      .select("slug")
      .eq("id", qrCode.landing_page_id)
      .single();

    if (lpError || !landingPage) {
      return new Response("Landing page not found", { status: 404 });
    }

    // Increment analytics (non-blocking)
    await supabase.rpc("increment_landing_page_views", {
      landing_page_id: qrCode.landing_page_id,
    });

    // Redirect to landing page
    return Response.redirect(`https://flyrpro.app/l/${landingPage.slug}`, 302);

  } catch (err) {
    return new Response("Server Error: " + err.message, { status: 500 });
  }
});

