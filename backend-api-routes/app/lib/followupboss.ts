/**
 * Follow Up Boss API client for voice-log flow.
 * Uses Basic auth and X-System: FLYR on all requests.
 */

const FUB_API_BASE = "https://api.followupboss.com/v1";
const X_SYSTEM = "FLYR";

function authHeaders(apiKey: string): Record<string, string> {
  const basicAuth = Buffer.from(`${apiKey}:`).toString("base64");
  return {
    "Content-Type": "application/json",
    Authorization: `Basic ${basicAuth}`,
    "X-System": X_SYSTEM,
  };
}

export type FubPersonPayload = {
  id?: number;
  firstName?: string;
  lastName?: string;
  emails?: Array<{ value: string; type?: string }>;
  phones?: Array<{ value: string; type?: string }>;
  addresses?: Array<{
    street?: string;
    city?: string;
    state?: string;
    code?: string;
    country?: string;
  }>;
  source?: string;
};

/**
 * Create or update a lead via Events API (type: General Inquiry so automations run).
 * Returns person id from 200/201 response body.
 */
export async function createOrUpdateLeadViaEvents(
  apiKey: string,
  person: FubPersonPayload
): Promise<{ personId: number }> {
  const event = {
    source: person.source ?? "FLYR",
    system: "FLYR",
    type: "General Inquiry",
    message: "",
    person: {
      firstName: person.firstName ?? "",
      lastName: person.lastName ?? "",
      ...(person.id != null && { id: person.id }),
      ...(person.emails?.length && { emails: person.emails }),
      ...(person.phones?.length && { phones: person.phones }),
      ...(person.addresses?.length && { addresses: person.addresses }),
      ...(person.source && { source: person.source }),
    },
  };

  const res = await fetch(`${FUB_API_BASE}/events`, {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify(event),
  });

  if (res.status === 204) {
    throw new Error("FUB lead flow archived; event not created.");
  }
  if (res.status === 404) {
    throw new Error("Person not found");
  }
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `FUB events returned ${res.status}`);
  }

  const data = (await res.json()) as { id?: number; personId?: number };
  const personId = data?.personId ?? data?.id;
  if (personId == null) {
    throw new Error("FUB events response missing person id");
  }
  return { personId: Number(personId) };
}

/**
 * Create a note on a person.
 */
export async function createNote(
  apiKey: string,
  personId: number,
  body: string,
  subject?: string
): Promise<{ id: number }> {
  const res = await fetch(`${FUB_API_BASE}/notes`, {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify({
      personId,
      body,
      ...(subject && { subject }),
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `FUB notes returned ${res.status}`);
  }

  const data = (await res.json()) as { id?: number };
  const id = data?.id;
  if (id == null) {
    throw new Error("FUB notes response missing id");
  }
  return { id: Number(id) };
}

/**
 * Create a task for a person.
 * dueAt: ISO8601 string; FUB accepts dueDateTime with timezone suffix.
 */
export async function createTask(
  apiKey: string,
  personId: number,
  dueAt: string,
  name: string,
  type: string = "Follow Up",
  assignedTo?: string
): Promise<{ id: number }> {
  const res = await fetch(`${FUB_API_BASE}/tasks`, {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify({
      personId,
      name,
      type,
      dueDateTime: dueAt,
      ...(assignedTo && { assignedTo }),
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `FUB tasks returned ${res.status}`);
  }

  const data = (await res.json()) as { id?: number };
  const id = data?.id;
  if (id == null) {
    throw new Error("FUB tasks response missing id");
  }
  return { id: Number(id) };
}

/**
 * Create an appointment linked to a person.
 * invitees: array of { personId?, userId?, name?, email? } for calendar sync.
 */
export async function createAppointment(
  apiKey: string,
  personId: number,
  startAt: string,
  endAt: string,
  title: string,
  location?: string | null,
  inviteeEmail?: string | null
): Promise<{ id: number }> {
  const invitees: Array<{ personId?: number; userId?: number; name?: string; email?: string }> = [
    { personId, name: "Lead" },
  ];
  if (inviteeEmail) {
    invitees.push({ email: inviteeEmail, name: inviteeEmail });
  }

  const res = await fetch(`${FUB_API_BASE}/appointments`, {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify({
      title,
      start: startAt,
      end: endAt,
      ...(location && { location }),
      invitees,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `FUB appointments returned ${res.status}`);
  }

  const data = (await res.json()) as { id?: number };
  const id = data?.id;
  if (id == null) {
    throw new Error("FUB appointments response missing id");
  }
  return { id: Number(id) };
}
