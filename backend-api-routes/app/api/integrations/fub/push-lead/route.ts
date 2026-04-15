import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getFubAuthForUser } from "../../../../lib/fub-auth";
import { withFubPersonRetry } from "../../../../lib/followupboss";

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
  task?: {
    title?: string;
    due_date?: string;
  };
  appointment?: {
    date?: string;
    title?: string;
    notes?: string;
  };
};

type FubAuth = { headers: Record<string, string> };

function extractPersonId(payload: unknown): number | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const obj = payload as Record<string, unknown>;

  const direct = obj.personId;
  if (direct != null && Number.isFinite(Number(direct))) {
    return Number(direct);
  }

  const person = obj.person;
  if (person && typeof person === "object") {
    const id = (person as Record<string, unknown>).id;
    if (id != null && Number.isFinite(Number(id))) {
      return Number(id);
    }
  }

  const nested = obj.data;
  if (nested && typeof nested === "object") {
    return extractPersonId(nested);
  }

  return undefined;
}

function extractPersonIdFromPeopleSearch(payload: unknown): number | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const obj = payload as Record<string, unknown>;
  const people = obj.people;
  if (!Array.isArray(people) || people.length === 0) return undefined;
  const first = people[0];
  if (!first || typeof first !== "object") return undefined;
  const id = (first as Record<string, unknown>).id;
  if (id != null && Number.isFinite(Number(id))) {
    return Number(id);
  }
  return undefined;
}

async function resolvePersonIdByContact(
  fubAuth: FubAuth,
  body: PushLeadBody
): Promise<number | undefined> {
  const authHeaders = {
    "Content-Type": "application/json",
    ...fubAuth.headers,
  };

  const email = body.email?.trim();
  if (email) {
    const byEmail = await fetch(
      `${FUB_API_BASE}/people?email=${encodeURIComponent(email)}&limit=1&fields=id`,
      { method: "GET", headers: authHeaders }
    );
    if (byEmail.ok) {
      const json = (await byEmail.json()) as unknown;
      const personId = extractPersonIdFromPeopleSearch(json);
      if (personId != null) return personId;
    }
  }

  const phone = body.phone?.trim();
  if (phone) {
    const byPhone = await fetch(
      `${FUB_API_BASE}/people?phone=${encodeURIComponent(phone)}&limit=1&fields=id`,
      { method: "GET", headers: authHeaders }
    );
    if (byPhone.ok) {
      const json = (await byPhone.json()) as unknown;
      const personId = extractPersonIdFromPeopleSearch(json);
      if (personId != null) return personId;
    }
  }

  return undefined;
}

/** Prefer lead message; if empty, synthesize from appointment title/notes so FUB gets a note when only scheduling. */
function buildFollowUpNoteBody(body: PushLeadBody): string | undefined {
  const msg = body.message?.trim();
  if (msg) return msg;
  const parts: string[] = [];
  const title = body.appointment?.title?.trim();
  const notes = body.appointment?.notes?.trim();
  if (title) parts.push(title);
  if (notes) parts.push(notes);
  if (parts.length === 0) return undefined;
  return parts.join("\n\n");
}

function normalizeDueDateTime(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;

  if (trimmed.includes("T")) {
    const parsed = new Date(trimmed);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed.toISOString();
    }
  }

  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    // Default date-only tasks to midday UTC.
    return `${trimmed}T17:00:00.000Z`;
  }

  const fallback = new Date(trimmed);
  if (!Number.isNaN(fallback.getTime())) {
    return fallback.toISOString();
  }

  return null;
}

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

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const fubAuth = await getFubAuthForUser(supabaseAdmin, user.id);
    if (!fubAuth) {
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

    const res = await fetch(`${FUB_API_BASE}/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...fubAuth.headers,
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
    let fubPersonId: number | undefined;
    let fubNoteId: number | undefined;
    let fubTaskId: number | undefined;
    let fubAppointmentId: number | undefined;
    let noteCreated: boolean | undefined;
    let taskCreated: boolean | undefined;
    let appointmentCreated: boolean | undefined;
    const followUpErrors: string[] = [];

    // FUB /events may return an empty body for 200/201, so parse defensively.
    const eventResponseText = await res.text();
    if (eventResponseText.trim()) {
      try {
        const data = JSON.parse(eventResponseText) as unknown;
        const parsed = data as Record<string, unknown>;
        fubEventId = parsed.id != null ? String(parsed.id) : undefined;
        fubPersonId = extractPersonId(parsed);
      } catch {
        console.warn("[fub/push-lead] Failed to parse /events response JSON");
      }
    }

    // Some event responses omit personId, so fetch event details as fallback.
    if (fubPersonId == null && fubEventId) {
      const eventFetchRes = await fetch(`${FUB_API_BASE}/events/${encodeURIComponent(fubEventId)}`, {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          ...fubAuth.headers,
        },
      });
      if (eventFetchRes.ok) {
        try {
          const eventDetails = await eventFetchRes.json();
          fubPersonId = extractPersonId(eventDetails);
        } catch {
          // ignore event decode errors
        }
      }
    }
    // Current docs allow /events with empty response body; use contact lookup as fallback.
    if (fubPersonId == null) {
      fubPersonId = await resolvePersonIdByContact(fubAuth, body);
    }

    // Best-effort follow-up artifacts on the same person created/resolved by event.
    if (fubPersonId != null) {
      const authHeaders = {
        "Content-Type": "application/json",
        ...fubAuth.headers,
      };
      let currentUserId: number | undefined;
      const taskTitle = body.task?.title?.trim();
      const dueDate = body.task?.due_date?.trim();
      const appointmentDateRaw = body.appointment?.date?.trim();
      const shouldFetchCurrentUser = Boolean((taskTitle && dueDate) || appointmentDateRaw);

      if (shouldFetchCurrentUser) {
        try {
          const meRes = await fetch(`${FUB_API_BASE}/me`, {
            method: "GET",
            headers: authHeaders,
          });
          if (meRes.ok) {
            const meJson = (await meRes.json()) as Record<string, unknown>;
            const id = meJson.id;
            if (id != null && Number.isFinite(Number(id))) {
              currentUserId = Number(id);
            }
          }
        } catch {
          // Ignore /me failures and allow FUB default assignment behavior.
        }
      }

      const noteBody = buildFollowUpNoteBody(body);
      if (noteBody) {
        try {
          const noteData = await withFubPersonRetry(async () => {
            const noteRes = await fetch(`${FUB_API_BASE}/notes`, {
              method: "POST",
              headers: authHeaders,
              body: JSON.stringify({
                personId: fubPersonId,
                subject: "FLYR Note",
                body: noteBody,
              }),
            });
            if (!noteRes.ok) {
              const noteErr = await noteRes.text();
              throw new Error(noteErr || `Note creation failed (${noteRes.status})`);
            }
            try {
              return (await noteRes.json()) as { id?: number };
            } catch {
              return {} as { id?: number };
            }
          });
          noteCreated = true;
          if (noteData?.id != null) {
            fubNoteId = Number(noteData.id);
          }
        } catch (error) {
          const noteErr = error instanceof Error ? error.message : String(error);
          followUpErrors.push(noteErr || "Note creation failed");
          console.warn("[fub/push-lead] Note creation failed", {
            body: noteErr,
            personId: fubPersonId,
          });
        }
      }

      if (taskTitle && dueDate) {
        const dueDateTime = normalizeDueDateTime(dueDate);
        if (!dueDateTime) {
          followUpErrors.push(`Invalid task due_date: "${dueDate}"`);
        } else {
          try {
            const taskData = await withFubPersonRetry(async () => {
              const taskRes = await fetch(`${FUB_API_BASE}/tasks`, {
                method: "POST",
                headers: authHeaders,
                body: JSON.stringify({
                  personId: fubPersonId,
                  name: taskTitle,
                  type: "Follow Up",
                  dueDate: dueDateTime.slice(0, 10),
                  dueDateTime,
                  ...(currentUserId != null ? { assignedUserId: currentUserId } : {}),
                }),
              });
              if (!taskRes.ok) {
                const taskErr = await taskRes.text();
                throw new Error(taskErr || `Task creation failed (${taskRes.status})`);
              }
              try {
                return (await taskRes.json()) as { id?: number };
              } catch {
                return {} as { id?: number };
              }
            });
            taskCreated = true;
            if (taskData?.id != null) {
              fubTaskId = Number(taskData.id);
            }
          } catch (error) {
            const taskErr = error instanceof Error ? error.message : String(error);
            followUpErrors.push(taskErr || "Task creation failed");
            console.warn("[fub/push-lead] Task creation failed", {
              body: taskErr,
              personId: fubPersonId,
            });
          }
        }
      }

      if (appointmentDateRaw) {
        const startDate = new Date(appointmentDateRaw);
        if (!Number.isNaN(startDate.getTime())) {
          const endDate = new Date(startDate.getTime() + 60 * 60 * 1000);
          try {
            const appointmentData = await withFubPersonRetry(async () => {
              const appointmentRes = await fetch(`${FUB_API_BASE}/appointments`, {
                method: "POST",
                headers: authHeaders,
                body: JSON.stringify({
                  title: body.appointment?.title?.trim() || "FLYR Appointment",
                  start: startDate.toISOString(),
                  end: endDate.toISOString(),
                  ...(body.appointment?.notes?.trim()
                    ? { description: body.appointment.notes.trim() }
                    : {}),
                  invitees: [
                    { personId: fubPersonId },
                    ...(currentUserId != null ? [{ userId: currentUserId }] : []),
                  ],
                }),
              });
              if (!appointmentRes.ok) {
                const appointmentErr = await appointmentRes.text();
                throw new Error(appointmentErr || `Appointment creation failed (${appointmentRes.status})`);
              }
              try {
                return (await appointmentRes.json()) as { id?: number };
              } catch {
                return {} as { id?: number };
              }
            });
            appointmentCreated = true;
            if (appointmentData?.id != null) {
              fubAppointmentId = Number(appointmentData.id);
            }
          } catch (error) {
            const appointmentErr = error instanceof Error ? error.message : String(error);
            followUpErrors.push(appointmentErr || "Appointment creation failed");
            console.warn("[fub/push-lead] Appointment creation failed", {
              body: appointmentErr,
              personId: fubPersonId,
            });
          }
        } else {
          followUpErrors.push(`Invalid appointment date: "${appointmentDateRaw}"`);
        }
      }
    } else {
      const hasFollowUps =
        Boolean(body.message?.trim()) ||
        Boolean(body.task?.title?.trim()) ||
        Boolean(body.appointment?.date?.trim()) ||
        Boolean(body.appointment?.title?.trim()) ||
        Boolean(body.appointment?.notes?.trim());
      if (hasFollowUps) {
        followUpErrors.push(
          "Lead event created but personId could not be resolved, so notes/tasks/appointments were skipped."
        );
      }
    }

    console.info("[fub/push-lead] completed", {
      fubEventId,
      fubPersonId,
      noteCreated,
      taskCreated,
      appointmentCreated,
      followUpErrorCount: followUpErrors.length,
    });

    return NextResponse.json({
      success: true,
      message: "Lead pushed to Follow Up Boss",
      fubEventId: fubEventId != null ? String(fubEventId) : null,
      fubPersonId: fubPersonId ?? null,
      fubNoteId: fubNoteId ?? null,
      fubTaskId: fubTaskId ?? null,
      fubAppointmentId: fubAppointmentId ?? null,
      noteCreated,
      taskCreated,
      appointmentCreated,
      followUpErrors: followUpErrors.length ? followUpErrors : undefined,
    });
  } catch (err) {
    console.error("[fub/push-lead]", err);
    return NextResponse.json(
      { success: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
