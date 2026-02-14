// supabase/functions/process-voice-note/index.ts
// Zero-Typing: Transcribe voice note with Whisper, extract JSON with GPT-4o-mini, update campaign_addresses + address_statuses.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// AI status (from GPT) -> address_statuses.status enum
const AI_STATUS_TO_ADDRESS_STATUS: Record<string, string> = {
  not_home: "no_answer",
  interested: "hot_lead",
  not_interested: "do_not_knock",
  follow_up: "appointment",
};

const SYSTEM_PROMPT = `You are a field sales assistant. Extract structured data from this door-knocking voice note.
Return ONLY valid JSON with no markdown or extra text. Use exactly these keys:
- contact_name (string, or null if not mentioned)
- status (exactly one of: "not_home", "interested", "not_interested", "follow_up")
- product_interest (string, or null; e.g. "solar", "roof", "windows")
- follow_up_date (ISO 8601 date string, or null; e.g. "2025-02-15T14:00:00.000Z")
- ai_summary (short 1-2 sentence summary)

Rules:
- "Nobody home", "not home", "left a flyer" -> status: "not_home"
- "Talked to [Name]", "wants quote", "interested" -> status: "interested" or "follow_up", set contact_name
- "Come back [day]", "next Tuesday", "Friday morning" -> status: "follow_up", set follow_up_date relative to today
- Today's date for relative parsing: [CURRENT_DATE] (use this for "tomorrow", "next Tuesday", etc.)
- If unclear, prefer status "follow_up" when a person or follow-up is mentioned.`;

type ExtractedPayload = {
  contact_name: string | null;
  status: string;
  product_interest: string | null;
  follow_up_date: string | null;
  ai_summary: string;
};

function jsonResponse(body: object, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(message: string, status = 400) {
  return jsonResponse({ error: message }, status);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405);
  }

  if (!SERVICE_ROLE || !OPENAI_API_KEY) {
    console.error("Missing SUPABASE_SERVICE_ROLE_KEY or OPENAI_API_KEY");
    return errorResponse("Server configuration error", 500);
  }

  try {
    const formData = await req.formData();
    const audioFile = formData.get("audio");
    const addressId = formData.get("address_id")?.toString()?.trim();
    const campaignId = formData.get("campaign_id")?.toString()?.trim();

    if (!addressId || !campaignId) {
      return errorResponse("Missing address_id or campaign_id");
    }

    if (!audioFile || !(audioFile instanceof File)) {
      return errorResponse("Missing or invalid audio file");
    }

    // 1. Transcribe with Whisper
    const whisperForm = new FormData();
    whisperForm.append("file", audioFile);
    whisperForm.append("model", "whisper-1");

    const whisperRes = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: whisperForm,
    });

    if (!whisperRes.ok) {
      const errText = await whisperRes.text();
      console.error("Whisper error:", whisperRes.status, errText);
      return errorResponse("Could not parse note, please try again.", 422);
    }

    const whisperJson = await whisperRes.json();
    const transcript = (whisperJson?.text ?? "").trim();

    if (!transcript || transcript.length < 2) {
      return errorResponse("Could not parse note, please try again.", 422);
    }

    // 2. Extract structured data with GPT-4o-mini
    const now = new Date();
    const currentDateStr = now.toISOString().slice(0, 10);
    const prompt = SYSTEM_PROMPT.replace("[CURRENT_DATE]", currentDateStr);

    const gptRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: prompt },
          { role: "user", content: `Transcript:\n${transcript}` },
        ],
        temperature: 0.2,
      }),
    });

    if (!gptRes.ok) {
      const errText = await gptRes.text();
      console.error("GPT error:", gptRes.status, errText);
      return errorResponse("Could not parse note, please try again.", 422);
    }

    const gptJson = await gptRes.json();
    const content = gptJson?.choices?.[0]?.message?.content?.trim() ?? "";

    let extracted: ExtractedPayload;
    try {
      const cleaned = content.replace(/^```json\s*/i, "").replace(/\s*```\s*$/i, "").trim();
      extracted = JSON.parse(cleaned) as ExtractedPayload;
    } catch {
      console.error("GPT JSON parse failed:", content);
      return errorResponse("Could not parse note, please try again.", 422);
    }

    const status = String(extracted.status ?? "follow_up").toLowerCase();
    const validStatuses = ["not_home", "interested", "not_interested", "follow_up"];
    const leadStatus = validStatuses.includes(status) ? status : "follow_up";

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

    // 3. Update campaign_addresses
    const campaignAddressUpdate: Record<string, unknown> = {
      contact_name: extracted.contact_name ?? null,
      lead_status: leadStatus,
      product_interest: extracted.product_interest ?? null,
      follow_up_date: extracted.follow_up_date ?? null,
      raw_transcript: transcript,
      ai_summary: extracted.ai_summary ?? "",
    };

    const { error: updateAddrError } = await supabase
      .from("campaign_addresses")
      .update(campaignAddressUpdate)
      .eq("id", addressId)
      .eq("campaign_id", campaignId);

    if (updateAddrError) {
      console.error("campaign_addresses update error:", updateAddrError);
      return errorResponse("Failed to save note", 500);
    }

    // 4. Upsert address_statuses so map pin color updates
    const addressStatus = AI_STATUS_TO_ADDRESS_STATUS[leadStatus] ?? "talked";
    const { data: existing } = await supabase
      .from("address_statuses")
      .select("visit_count")
      .eq("address_id", addressId)
      .eq("campaign_id", campaignId)
      .limit(1)
      .maybeSingle();

    const visitCount = (existing?.visit_count ?? 0) + 1;
    const { error: upsertStatusError } = await supabase
      .from("address_statuses")
      .upsert(
        {
          address_id: addressId,
          campaign_id: campaignId,
          status: addressStatus,
          last_visited_at: new Date().toISOString(),
          visit_count: visitCount,
          notes: extracted.ai_summary ?? "",
          updated_at: new Date().toISOString(),
        },
        { onConflict: "address_id,campaign_id" }
      );

    if (upsertStatusError) {
      console.error("address_statuses upsert error:", upsertStatusError);
      // Non-fatal: campaign_addresses was updated
    }

    return jsonResponse({
      contact_name: extracted.contact_name,
      lead_status: leadStatus,
      product_interest: extracted.product_interest,
      follow_up_date: extracted.follow_up_date,
      ai_summary: extracted.ai_summary,
      raw_transcript: transcript,
    });
  } catch (e) {
    console.error("process-voice-note error:", e);
    return errorResponse("Could not parse note, please try again.", 500);
  }
});
