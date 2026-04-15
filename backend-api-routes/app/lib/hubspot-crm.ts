/**
 * HubSpot CRM helpers (contacts, notes, tasks, appointments).
 * Association type IDs: https://developers.hubspot.com/docs/api-reference/crm-associations-v3/guide
 */

const API_BASE = "https://api.hubapi.com";

/** HUBSPOT_DEFINED: note → contact (214 is note → deal) */
const ASSOC_NOTE_TO_CONTACT = 202;
/** HUBSPOT_DEFINED: task → contact */
const ASSOC_TASK_TO_CONTACT = 204;
/** HUBSPOT_DEFINED: appointment → contact */
const ASSOC_APPOINTMENT_TO_CONTACT = 906;

export type PushLeadInput = {
  id: string;
  name?: string;
  email?: string;
  phone?: string;
  address?: string;
  notes?: string;
  source?: string;
  campaignId?: string;
  createdAt?: string;
  task?: { title?: string; due_date?: string };
  appointment?: { date?: string; title?: string; notes?: string };
};

export type PushLeadResult = {
  success: boolean;
  contactId?: string;
  noteCreated?: boolean;
  taskCreated?: boolean;
  meetingCreated?: boolean;
  partialErrors?: string[];
  error?: string;
};

function trim(s: unknown): string {
  return typeof s === "string" ? s.trim() : "";
}

function splitName(full: string): { first: string; last: string } {
  const p = full.split(/\s+/).filter(Boolean);
  if (p.length === 0) return { first: "", last: "" };
  if (p.length === 1) return { first: p[0]!, last: "" };
  return { first: p[0]!, last: p.slice(1).join(" ") };
}

function normalizeDueDateTime(raw: string): string | null {
  const t = raw.trim();
  if (!t) return null;
  if (t.includes("T")) {
    const d = new Date(t);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  }
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) {
    return `${t}T17:00:00.000Z`;
  }
  const d = new Date(t);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

async function hsJson<T>(
  accessToken: string,
  path: string,
  init?: RequestInit
): Promise<{ ok: boolean; status: number; data: T | null; text: string }> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      ...(init?.headers as Record<string, string>),
    },
  });
  const text = await res.text();
  let data: T | null = null;
  if (text.trim()) {
    try {
      data = JSON.parse(text) as T;
    } catch {
      data = null;
    }
  }
  return { ok: res.ok, status: res.status, data, text };
}

async function searchContactByProperty(
  accessToken: string,
  propertyName: string,
  value: string
): Promise<string | null> {
  const { ok, data } = await hsJson<{ results?: Array<{ id: string }> }>(accessToken, "/crm/v3/objects/contacts/search", {
    method: "POST",
    body: JSON.stringify({
      filterGroups: [
        {
          filters: [{ propertyName, operator: "EQ", value }],
        },
      ],
      properties: ["email", "firstname", "lastname", "phone"],
      limit: 1,
    }),
  });
  if (!ok || !data?.results?.length) return null;
  return data.results[0]?.id ?? null;
}

async function patchContact(accessToken: string, id: string, properties: Record<string, string>): Promise<boolean> {
  const { ok } = await hsJson(accessToken, `/crm/v3/objects/contacts/${encodeURIComponent(id)}`, {
    method: "PATCH",
    body: JSON.stringify({ properties }),
  });
  return ok;
}

async function createNoteForContact(
  accessToken: string,
  contactId: string,
  body: string
): Promise<boolean> {
  const ts = new Date().toISOString();
  const { ok, text } = await hsJson<{ id?: string }>(accessToken, "/crm/v3/objects/notes", {
    method: "POST",
    body: JSON.stringify({
      properties: {
        hs_note_body: body,
        hs_timestamp: ts,
      },
      associations: [
        {
          to: { id: contactId },
          types: [
            {
              associationCategory: "HUBSPOT_DEFINED",
              associationTypeId: ASSOC_NOTE_TO_CONTACT,
            },
          ],
        },
      ],
    }),
  });
  if (!ok) {
    console.warn("[hubspot-crm] note create failed", text);
  }
  return ok;
}

async function createTaskForContact(
  accessToken: string,
  contactId: string,
  title: string,
  dueIso: string
): Promise<boolean> {
  const dueDateOnly = dueIso.slice(0, 10);
  const { ok, text } = await hsJson<{ id?: string }>(accessToken, "/crm/v3/objects/tasks", {
    method: "POST",
    body: JSON.stringify({
      properties: {
        hs_task_subject: title,
        hs_task_status: "NOT_STARTED",
        hs_task_priority: "MEDIUM",
        hs_timestamp: dueIso,
        hs_task_type: "TODO",
      },
      associations: [
        {
          to: { id: contactId },
          types: [
            {
              associationCategory: "HUBSPOT_DEFINED",
              associationTypeId: ASSOC_TASK_TO_CONTACT,
            },
          ],
        },
      ],
    }),
  });
  if (!ok) {
    console.warn("[hubspot-crm] task create failed", { text, dueDateOnly });
  }
  return ok;
}

/** Uses CRM “appointments” object + scopes (`crm.objects.appointments.write`), not legacy meetings. */
async function createAppointmentForContact(
  accessToken: string,
  contactId: string,
  startIso: string,
  title: string,
  description?: string
): Promise<boolean> {
  const start = new Date(startIso);
  if (Number.isNaN(start.getTime())) return false;
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  // Default appointment properties (see HubSpot Appointments API). Title/description use a
  // timeline note so we don’t depend on portal-specific appointment property internal names.
  const props: Record<string, string> = {
    hs_appointment_start: start.toISOString(),
    hs_appointment_end: end.toISOString(),
  };
  const { ok, text } = await hsJson<{ id?: string }>(accessToken, "/crm/v3/objects/appointments", {
    method: "POST",
    body: JSON.stringify({
      properties: props,
      associations: [
        {
          to: { id: contactId },
          types: [
            {
              associationCategory: "HUBSPOT_DEFINED",
              associationTypeId: ASSOC_APPOINTMENT_TO_CONTACT,
            },
          ],
        },
      ],
    }),
  });
  if (!ok) {
    console.warn("[hubspot-crm] appointment create failed", text);
    return false;
  }
  const extra = [title?.trim(), description?.trim()].filter(Boolean).join("\n\n");
  if (extra) {
    const noteOk = await createNoteForContact(accessToken, contactId, extra);
    if (!noteOk) {
      console.warn("[hubspot-crm] appointment title/notes could not be saved as activity note");
    }
  }
  return true;
}

export async function hubspotMinimalApiTest(accessToken: string): Promise<{ ok: boolean; message: string }> {
  const { ok, status, text } = await hsJson<unknown>(
    accessToken,
    "/crm/v3/objects/contacts?limit=1&properties=email",
    { method: "GET" }
  );
  if (ok) {
    return { ok: true, message: "HubSpot API reachable." };
  }
  if (status === 401 || status === 403) {
    return { ok: false, message: "Invalid or expired HubSpot token or missing scopes." };
  }
  return { ok: false, message: text?.slice(0, 500) || `HubSpot API error (${status})` };
}

export async function pushLeadToHubSpot(
  accessToken: string,
  input: PushLeadInput,
  options?: { existingContactId?: string | null }
): Promise<PushLeadResult> {
  const email = trim(input.email);
  const phone = trim(input.phone);
  const name = trim(input.name);
  const address = trim(input.address);
  const { first, last } = splitName(name);

  const hasEmail = email.length > 0;
  const hasName = first.length > 0 || last.length > 0;
  if (!hasEmail && !hasName) {
    return {
      success: false,
      error: "HubSpot contact requires at least an email or a contact name.",
    };
  }

  // Only include properties that have actual values.
  // HubSpot treats empty strings in PATCH requests as clearing the field, which can
  // silently wipe data already in HubSpot (e.g. an address entered manually).
  const rawProperties: Record<string, string> = {
    firstname: first,
    lastname: last,
    email,
    phone,
    address,
    hs_lead_status: "NEW",
  };
  const properties = Object.fromEntries(
    Object.entries(rawProperties).filter(([, v]) => v.length > 0)
  );

  let contactId = options?.existingContactId?.trim() || null;

  if (!contactId) {
    if (hasEmail) {
      contactId = await searchContactByProperty(accessToken, "email", email);
    }
    if (!contactId && phone) {
      contactId = await searchContactByProperty(accessToken, "phone", phone);
    }
  }

  const partialErrors: string[] = [];

  if (contactId) {
    const patched = await patchContact(accessToken, contactId, properties);
    if (!patched) {
      return { success: false, error: "Failed to update HubSpot contact." };
    }
  } else {
    const res = await hsJson<{ id?: string }>(accessToken, "/crm/v3/objects/contacts", {
      method: "POST",
      body: JSON.stringify({ properties }),
    });
    if (!res.ok || !res.data?.id) {
      if (hasEmail) {
        contactId = await searchContactByProperty(accessToken, "email", email);
      }
      if (!contactId && phone) {
        contactId = await searchContactByProperty(accessToken, "phone", phone);
      }
      if (contactId) {
        const patched = await patchContact(accessToken, contactId, properties);
        if (!patched) {
          return {
            success: false,
            error: res.text?.slice(0, 800) || "Failed to create or update HubSpot contact.",
          };
        }
      } else {
        return {
          success: false,
          error: res.text?.slice(0, 800) || "Failed to create HubSpot contact.",
        };
      }
    } else {
      contactId = res.data.id;
    }
  }

  let noteCreated: boolean | undefined;
  let taskCreated: boolean | undefined;
  let meetingCreated: boolean | undefined;

  const noteText = trim(input.notes);
  if (noteText) {
    const n = await createNoteForContact(accessToken, contactId, noteText);
    noteCreated = n;
    if (!n) partialErrors.push("Note could not be created (check HubSpot note scopes).");
  }

  const taskTitle = trim(input.task?.title);
  const taskDue = trim(input.task?.due_date);
  if (taskTitle && taskDue) {
    const dueIso = normalizeDueDateTime(taskDue);
    if (!dueIso) {
      partialErrors.push(`Invalid task due_date: "${taskDue}"`);
    } else {
      const t = await createTaskForContact(accessToken, contactId, taskTitle, dueIso);
      taskCreated = t;
      if (!t) partialErrors.push("Task could not be created (check HubSpot task scopes).");
    }
  }

  const apptDate = trim(input.appointment?.date);
  if (apptDate) {
    const startIso = normalizeDueDateTime(apptDate) || (Number.isNaN(new Date(apptDate).getTime()) ? null : new Date(apptDate).toISOString());
    if (!startIso) {
      partialErrors.push(`Invalid appointment date: "${apptDate}"`);
    } else {
      const m = await createAppointmentForContact(
        accessToken,
        contactId,
        startIso,
        trim(input.appointment?.title) || "FLYR Appointment",
        trim(input.appointment?.notes)
      );
      meetingCreated = m;
      if (!m) partialErrors.push("Appointment could not be created (check HubSpot appointment scopes and property names).");
    }
  }

  return {
    success: true,
    contactId,
    noteCreated,
    taskCreated,
    meetingCreated,
    partialErrors: partialErrors.length ? partialErrors : undefined,
  };
}
