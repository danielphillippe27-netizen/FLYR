import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getFubAuthForUser } from "../../../../lib/fub-auth";
import { withFubPersonRetry } from "../../../../lib/followupboss";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const FUB_API_BASE = "https://api.followupboss.com/v1";

function extractPersonId(payload: unknown): number | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const obj = payload as Record<string, unknown>;

  const direct = obj.personId;
  if (direct != null && Number.isFinite(Number(direct))) return Number(direct);

  const person = obj.person;
  if (person && typeof person === "object") {
    const personId = (person as Record<string, unknown>).id;
    if (personId != null && Number.isFinite(Number(personId))) return Number(personId);
  }

  const data = obj.data;
  if (data && typeof data === "object") {
    return extractPersonId(data);
  }

  return undefined;
}

function extractPersonIdFromPeopleSearch(payload: unknown): number | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const people = (payload as { people?: unknown }).people;
  if (!Array.isArray(people) || people.length === 0) return undefined;
  const first = people[0];
  if (!first || typeof first !== "object") return undefined;
  const id = (first as { id?: unknown }).id;
  if (id == null || !Number.isFinite(Number(id))) return undefined;
  return Number(id);
}

async function resolvePersonIdByContact(
  authHeaders: Record<string, string>,
  email: string,
  phone: string
): Promise<number | undefined> {
  const byEmail = await fetch(
    `${FUB_API_BASE}/people?email=${encodeURIComponent(email)}&limit=1&fields=id`,
    { method: "GET", headers: authHeaders }
  );
  if (byEmail.ok) {
    const json = (await byEmail.json()) as unknown;
    const found = extractPersonIdFromPeopleSearch(json);
    if (found != null) return found;
  }

  const byPhone = await fetch(
    `${FUB_API_BASE}/people?phone=${encodeURIComponent(phone)}&limit=1&fields=id`,
    { method: "GET", headers: authHeaders }
  );
  if (byPhone.ok) {
    const json = (await byPhone.json()) as unknown;
    const found = extractPersonIdFromPeopleSearch(json);
    if (found != null) return found;
  }

  return undefined;
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
    const fubAuth = await getFubAuthForUser(supabaseAdmin, user.id);
    if (!fubAuth) {
      return NextResponse.json(
        { success: false, error: "Follow Up Boss not connected" },
        { status: 400 }
      );
    }

    const authHeaders = {
      "Content-Type": "application/json",
      ...fubAuth.headers,
    };

    const now = new Date();
    const plusOneDay = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const appointmentStart = new Date(now.getTime() + 2 * 60 * 60 * 1000);
    const appointmentEnd = new Date(appointmentStart.getTime() + 60 * 60 * 1000);

    const event = {
      source: "FLYR",
      system: "FLYR",
      type: "General Inquiry",
      message: "Test lead from FLYR iOS app (includes note/task/appointment)",
      person: {
        firstName: "FLYR",
        lastName: "Test",
        emails: [{ value: "test@flyrpro.app" }],
        phones: [{ value: "5555555555" }],
      },
    };

    const res = await fetch(`${FUB_API_BASE}/events`, {
      method: "POST",
      headers: authHeaders,
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

    let fubPersonId: number | undefined;
    const raw = await res.text();
    if (raw.trim()) {
      try {
        fubPersonId = extractPersonId(JSON.parse(raw) as unknown);
      } catch {
        // ignore parse errors, we'll resolve by contact
      }
    }
    if (fubPersonId == null) {
      fubPersonId = await resolvePersonIdByContact(
        authHeaders,
        "test@flyrpro.app",
        "5555555555"
      );
    }

    if (fubPersonId == null) {
      return NextResponse.json(
        {
          success: false,
          error: "Test lead sent, but person id could not be resolved for note/task/appointment.",
        },
        { status: 502 }
      );
    }

    let assignedUserId: number | undefined;
    try {
      const meRes = await fetch(`${FUB_API_BASE}/me`, {
        method: "GET",
        headers: authHeaders,
      });
      if (meRes.ok) {
        const me = (await meRes.json()) as Record<string, unknown>;
        if (me.id != null && Number.isFinite(Number(me.id))) {
          assignedUserId = Number(me.id);
        }
      }
    } catch {
      // allow default assignment behavior in FUB
    }

    const followUpErrors: string[] = [];
    let fubNoteId: number | null = null;
    let fubTaskId: number | null = null;
    let fubAppointmentId: number | null = null;
    let noteCreated = false;
    let taskCreated = false;
    let appointmentCreated = false;

    try {
      const noteJson = await withFubPersonRetry(async () => {
        const noteRes = await fetch(`${FUB_API_BASE}/notes`, {
          method: "POST",
          headers: authHeaders,
          body: JSON.stringify({
            personId: fubPersonId,
            subject: "FLYR Test Note",
            body: "This is an automated test note from FLYR test-push.",
          }),
        });
        if (!noteRes.ok) {
          const text = await noteRes.text();
          throw new Error(text || `FUB notes returned ${noteRes.status}`);
        }
        try {
          return (await noteRes.json()) as { id?: number };
        } catch {
          return {} as { id?: number };
        }
      });
      noteCreated = true;
      if (noteJson.id != null) fubNoteId = Number(noteJson.id);
    } catch (error) {
      followUpErrors.push(error instanceof Error ? error.message : String(error));
    }

    try {
      const taskJson = await withFubPersonRetry(async () => {
        const taskRes = await fetch(`${FUB_API_BASE}/tasks`, {
          method: "POST",
          headers: authHeaders,
          body: JSON.stringify({
            personId: fubPersonId,
            name: "FLYR Test Follow Up",
            type: "Follow Up",
            dueDate: plusOneDay.toISOString().slice(0, 10),
            dueDateTime: plusOneDay.toISOString(),
            ...(assignedUserId != null ? { assignedUserId } : {}),
          }),
        });
        if (!taskRes.ok) {
          const text = await taskRes.text();
          throw new Error(text || `FUB tasks returned ${taskRes.status}`);
        }
        try {
          return (await taskRes.json()) as { id?: number };
        } catch {
          return {} as { id?: number };
        }
      });
      taskCreated = true;
      if (taskJson.id != null) fubTaskId = Number(taskJson.id);
    } catch (error) {
      followUpErrors.push(error instanceof Error ? error.message : String(error));
    }

    try {
      const appointmentJson = await withFubPersonRetry(async () => {
        const appointmentRes = await fetch(`${FUB_API_BASE}/appointments`, {
          method: "POST",
          headers: authHeaders,
          body: JSON.stringify({
            title: "FLYR Test Appointment",
            start: appointmentStart.toISOString(),
            end: appointmentEnd.toISOString(),
            description: "This is an automated test appointment from FLYR test-push.",
            invitees: [
              { personId: fubPersonId },
              ...(assignedUserId != null ? [{ userId: assignedUserId }] : []),
            ],
          }),
        });
        if (!appointmentRes.ok) {
          const text = await appointmentRes.text();
          throw new Error(text || `FUB appointments returned ${appointmentRes.status}`);
        }
        try {
          return (await appointmentRes.json()) as { id?: number };
        } catch {
          return {} as { id?: number };
        }
      });
      appointmentCreated = true;
      if (appointmentJson.id != null) fubAppointmentId = Number(appointmentJson.id);
    } catch (error) {
      followUpErrors.push(error instanceof Error ? error.message : String(error));
    }

    return NextResponse.json({
      success: true,
      message: "Test lead sent to Follow Up Boss with note, task, and appointment attempts.",
      fubPersonId,
      fubNoteId,
      fubTaskId,
      fubAppointmentId,
      noteCreated,
      taskCreated,
      appointmentCreated,
      followUpErrors: followUpErrors.length ? followUpErrors : undefined,
    });
  } catch (err) {
    console.error("[fub/test-push]", err);
    return NextResponse.json(
      { success: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
