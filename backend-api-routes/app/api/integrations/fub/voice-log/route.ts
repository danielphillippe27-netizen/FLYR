import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getFubApiKeyForUser } from "../../../../../lib/crm-auth";
import {
  createOrUpdateLeadViaEvents,
  createNote,
  createTask,
  createAppointment,
  type FubPersonPayload,
} from "../../../../../lib/followupboss";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

// Strict AI output schema (plan)
type AIAppointment = {
  title: string;
  start_at: string;
  end_at: string;
  location: string | null;
  invitee_email: string | null;
};
type AIContact = {
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
};
type AIJson = {
  summary: string;
  outcome: string;
  follow_up_at: string | null;
  next_action: string;
  priority: string;
  appointment: AIAppointment | null;
  contact: AIContact;
  tags: string[];
  confidence: number;
};

const OUTCOMES = ["no_answer", "spoke", "follow_up", "not_interested", "hot_lead", "appointment_set"];
const CONFIDENCE_THRESHOLD = 0.65;

const VOICE_LOG_SYSTEM_PROMPT = `You are a field sales assistant. Extract structured data from this door-knocking voice note.
Return ONLY valid JSON with no markdown, no code block, no extra text. Use exactly these keys:
- summary (string): clean 1-3 sentence summary
- outcome (exactly one of: no_answer, spoke, follow_up, not_interested, hot_lead, appointment_set)
- follow_up_at (ISO 8601 datetime string or null; resolve relative times like "next Tuesday at 6" using the provided timezone and current date)
- next_action (one of: call, text, email, drop_by, send_cma, none)
- priority (one of: hot, warm, cold)
- appointment (object or null): { title, start_at (ISO8601), end_at (ISO8601), location (string or null), invitee_email (string or null) }; if end missing use start + 30 minutes
- contact (object): { first_name, last_name, email, phone } (all string or null)
- tags (array of strings)
- confidence (number 0.0 to 1.0)

Rules:
- "No answer", "left flyer", "nobody home" -> outcome: no_answer
- "Talked to [name]", "spoke with" -> outcome: spoke or follow_up
- "Follow up next Tuesday at 6" -> set follow_up_at to that datetime in the given timezone
- If appointment intent is clear (e.g. "booked a showing", "scheduled for Friday 2pm") set appointment object; else null
- Extract any spoken name/phone/email into contact
- Today's date for relative parsing: [CURRENT_DATE]
- If follow_up_at is ambiguous, set null and put the suggestion in summary
- confidence: 0.9+ when clear, &lt; 0.65 when ambiguous (then we will not auto-create task/appointment)`;

function stripJsonBlock(raw: string): string {
  return raw
    .replace(/^```json\s*/i, "")
    .replace(/\s*```\s*$/i, "")
    .trim();
}

function parseAIJson(content: string): AIJson | null {
  try {
    const cleaned = stripJsonBlock(content);
    const parsed = JSON.parse(cleaned) as AIJson;
    if (typeof parsed.summary !== "string") return null;
    if (!OUTCOMES.includes(parsed.outcome)) parsed.outcome = "follow_up";
    const conf = Number(parsed.confidence);
    parsed.confidence = Number.isFinite(conf) ? Math.max(0, Math.min(1, conf)) : 0.5;
    return parsed;
  } catch {
    return null;
  }
}

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Invalid or expired token" }, { status: 401 });
    }

    const apiKey = await getFubApiKeyForUser(
      createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY),
      user.id
    );
    if (!apiKey) {
      return NextResponse.json(
        { error: "Follow Up Boss not connected" },
        { status: 400 }
      );
    }

    const formData = await request.formData();
    const audio = formData.get("audio");
    const flyrEventIdRaw = formData.get("flyr_event_id")?.toString()?.trim();
    const leadIdRaw = formData.get("lead_id")?.toString()?.trim();
    const addressIdRaw = formData.get("address_id")?.toString()?.trim();
    const campaignIdRaw = formData.get("campaign_id")?.toString()?.trim();
    const address = formData.get("address")?.toString()?.trim() ?? "";
    const timezone = formData.get("timezone")?.toString()?.trim() ?? "America/Toronto";
    const userContext = formData.get("user_context")?.toString()?.trim();

    if (!flyrEventIdRaw) {
      return NextResponse.json({ error: "Missing flyr_event_id" }, { status: 400 });
    }
    if (!addressIdRaw || !campaignIdRaw) {
      return NextResponse.json({ error: "Missing address_id or campaign_id" }, { status: 400 });
    }
    if (!audio || !(audio instanceof Blob)) {
      return NextResponse.json({ error: "Missing or invalid audio file" }, { status: 400 });
    }

    if (!OPENAI_API_KEY) {
      return NextResponse.json({ error: "Server configuration error" }, { status: 500 });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Idempotency: already processed?
    const { data: existingEvent } = await supabaseAdmin
      .from("crm_events")
      .select("transcript, ai_json, fub_person_id, fub_note_id, fub_task_id, fub_appointment_id")
      .eq("user_id", user.id)
      .eq("flyr_event_id", flyrEventIdRaw)
      .maybeSingle();

    if (existingEvent) {
      const aiJson = existingEvent.ai_json as AIJson | null;
      return NextResponse.json({
        transcript: existingEvent.transcript ?? "",
        ai_json: aiJson,
        fub_results: {
          personId: existingEvent.fub_person_id ?? undefined,
          noteId: existingEvent.fub_note_id ?? undefined,
          taskId: existingEvent.fub_task_id ?? undefined,
          appointmentId: existingEvent.fub_appointment_id ?? undefined,
        },
      });
    }

    // Transcribe with Whisper
    const whisperForm = new FormData();
    whisperForm.append("file", audio, "audio.m4a");
    whisperForm.append("model", "whisper-1");

    const whisperRes = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: whisperForm,
    });

    if (!whisperRes.ok) {
      const errText = await whisperRes.text();
      console.error("[voice-log] Whisper error:", whisperRes.status, errText);
      return NextResponse.json(
        { error: "Could not transcribe audio. Please try again." },
        { status: 422 }
      );
    }

    const whisperJson = (await whisperRes.json()) as { text?: string };
    const transcript = (whisperJson?.text ?? "").trim();
    if (!transcript || transcript.length < 2) {
      return NextResponse.json(
        { error: "No speech detected. Please try again." },
        { status: 422 }
      );
    }

    // LLM extraction
    const now = new Date();
    const currentDateStr = now.toISOString().slice(0, 10);
    const systemPrompt = VOICE_LOG_SYSTEM_PROMPT.replace("[CURRENT_DATE]", currentDateStr);
    const userPrompt = `Timezone: ${timezone}\nAddress: ${address}\n${userContext ? `Context: ${userContext}\n` : ""}\nTranscript:\n${transcript}`;

    const gptRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.2,
      }),
    });

    if (!gptRes.ok) {
      const errText = await gptRes.text();
      console.error("[voice-log] GPT error:", gptRes.status, errText);
      return NextResponse.json(
        { error: "Could not analyze note. Please try again." },
        { status: 422 }
      );
    }

    const gptJson = (await gptRes.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const content = gptJson?.choices?.[0]?.message?.content?.trim() ?? "";
    let aiJson = parseAIJson(content);
    if (!aiJson) {
      // Retry once with fix instruction
      const retryRes = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
            { role: "user", content: "Fix and return only valid JSON with the required keys. No markdown." },
          ],
          temperature: 0.1,
        }),
      });
      if (retryRes.ok) {
        const retryJson = (await retryRes.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const retryContent = retryJson?.choices?.[0]?.message?.content?.trim() ?? "";
        aiJson = parseAIJson(retryContent);
      }
    }
    if (!aiJson) {
      return NextResponse.json(
        { error: "Could not parse note. Please try again.", transcript },
        { status: 422 }
      );
    }

    const fubResults: {
      personId?: number;
      noteId?: number;
      taskId?: number;
      appointmentId?: number;
      skippedLowConfidence?: boolean;
      errors?: string[];
    } = {};
    const errors: string[] = [];

    const lowConfidence = aiJson.confidence < CONFIDENCE_THRESHOLD;
    if (lowConfidence && (aiJson.follow_up_at || aiJson.appointment)) {
      fubResults.skippedLowConfidence = true;
    }

    try {
      // Resolve or create FUB person
      let personId: number | null = null;
      const leadIdUuid = leadIdRaw ?? null;
      const addressIdUuid = addressIdRaw;

      const { data: linkByLead } =
        leadIdUuid != null
          ? await supabaseAdmin
              .from("crm_object_links")
              .select("fub_person_id")
              .eq("user_id", user.id)
              .eq("crm_type", "fub")
              .eq("flyr_lead_id", leadIdUuid)
              .maybeSingle()
          : { data: null };

      const { data: linkByAddress } = await supabaseAdmin
        .from("crm_object_links")
        .select("fub_person_id")
        .eq("user_id", user.id)
        .eq("crm_type", "fub")
        .eq("flyr_address_id", addressIdUuid)
        .maybeSingle();

      const existingFubPersonId = linkByLead?.fub_person_id ?? linkByAddress?.fub_person_id ?? null;

      const personPayload: FubPersonPayload = {
        ...(existingFubPersonId != null && { id: existingFubPersonId }),
        firstName: aiJson.contact?.first_name ?? undefined,
        lastName: aiJson.contact?.last_name ?? undefined,
        source: "FLYR",
      };
      if (aiJson.contact?.email) {
        personPayload.emails = [{ value: aiJson.contact.email }];
      }
      if (aiJson.contact?.phone) {
        personPayload.phones = [{ value: aiJson.contact.phone }];
      }
      if (address) {
        personPayload.addresses = [{ street: address, country: "US" }];
      }
      if (!personPayload.emails?.length && !personPayload.phones?.length) {
        personPayload.emails = [{ value: `lead+${addressIdUuid}@flyr.placeholder` }];
      }

      const { personId: createdPersonId } = await createOrUpdateLeadViaEvents(apiKey, personPayload);
      personId = createdPersonId;
      fubResults.personId = personId;

      // Note (summary + optional transcript snippet)
      const noteBody = [aiJson.summary].concat(transcript ? [`\n\nTranscript: ${transcript.slice(0, 2000)}`] : []).join("");
      const { id: noteId } = await createNote(apiKey, personId, noteBody, "Voice log");
      fubResults.noteId = noteId;

      if (!lowConfidence && aiJson.follow_up_at) {
        const { id: taskId } = await createTask(
          apiKey,
          personId,
          aiJson.follow_up_at,
          `Follow up: ${aiJson.summary.slice(0, 80)}`,
          "Follow Up"
        );
        fubResults.taskId = taskId;
      }

      if (!lowConfidence && aiJson.appointment?.start_at && aiJson.appointment?.end_at) {
        const { id: appointmentId } = await createAppointment(
          apiKey,
          personId,
          aiJson.appointment.start_at,
          aiJson.appointment.end_at,
          aiJson.appointment.title || "Appointment",
          aiJson.appointment.location ?? undefined,
          aiJson.appointment.invitee_email ?? undefined
        );
        fubResults.appointmentId = appointmentId;
      }

      // Upsert crm_object_links (by address_id; partial unique index)
      const { data: existingByAddress } = await supabaseAdmin
        .from("crm_object_links")
        .select("id")
        .eq("user_id", user.id)
        .eq("crm_type", "fub")
        .eq("flyr_address_id", addressIdUuid)
        .maybeSingle();

      if (existingByAddress?.id) {
        await supabaseAdmin
          .from("crm_object_links")
          .update({ fub_person_id: personId })
          .eq("id", existingByAddress.id);
      } else {
        await supabaseAdmin.from("crm_object_links").insert({
          user_id: user.id,
          crm_type: "fub",
          flyr_lead_id: leadIdUuid,
          flyr_address_id: addressIdUuid,
          fub_person_id: personId,
        });
      }

      if (leadIdUuid) {
        const { data: existingByLead } = await supabaseAdmin
          .from("crm_object_links")
          .select("id")
          .eq("user_id", user.id)
          .eq("crm_type", "fub")
          .eq("flyr_lead_id", leadIdUuid)
          .maybeSingle();

        if (existingByLead?.id) {
          await supabaseAdmin
            .from("crm_object_links")
            .update({ fub_person_id: personId })
            .eq("id", existingByLead.id);
        } else {
          await supabaseAdmin.from("crm_object_links").insert({
            user_id: user.id,
            crm_type: "fub",
            flyr_lead_id: leadIdUuid,
            flyr_address_id: addressIdUuid,
            fub_person_id: personId,
          });
        }
      }

      // Insert crm_events for idempotency
      await supabaseAdmin.from("crm_events").insert({
        user_id: user.id,
        crm_type: "fub",
        flyr_event_id: flyrEventIdRaw,
        fub_person_id: personId,
        fub_note_id: fubResults.noteId ?? null,
        fub_task_id: fubResults.taskId ?? null,
        fub_appointment_id: fubResults.appointmentId ?? null,
        transcript,
        ai_json: aiJson as unknown as Record<string, unknown>,
      });
    } catch (fubErr) {
      const msg = fubErr instanceof Error ? fubErr.message : String(fubErr);
      console.error("[voice-log] FUB error:", msg);
      errors.push(msg);
      fubResults.errors = errors;
      return NextResponse.json(
        {
          error: "Failed to push to Follow Up Boss. You can retry or save locally.",
          transcript,
          ai_json: aiJson,
          fub_results: fubResults,
        },
        { status: 502 }
      );
    }

    return NextResponse.json({
      transcript,
      ai_json: aiJson,
      fub_results: fubResults,
    });
  } catch (err) {
    console.error("[voice-log]", err);
    return NextResponse.json(
      { error: "Something went wrong. Please try again." },
      { status: 500 }
    );
  }
}
