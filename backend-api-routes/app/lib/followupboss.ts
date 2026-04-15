/**
 * Follow Up Boss API client for voice-log flow.
 * Uses Basic auth and X-System: FLYR on all requests.
 */

const FUB_API_BASE = "https://api.followupboss.com/v1";
const X_SYSTEM = "FLYR";
const X_SYSTEM_KEY =
  process.env.FUB_SYSTEM_KEY?.trim() ||
  process.env.X_SYSTEM_KEY?.trim() ||
  null;

function authHeaders(apiKey: string): Record<string, string> {
  const basicAuth = Buffer.from(`${apiKey}:`).toString("base64");
  return {
    "Content-Type": "application/json",
    Authorization: `Basic ${basicAuth}`,
    "X-System": X_SYSTEM,
    ...(X_SYSTEM_KEY ? { "X-System-Key": X_SYSTEM_KEY } : {}),
  };
}

const PERSON_NOT_READY_PATTERNS = [
  /contact not found/i,
  /person not found/i,
  /record not found/i,
];

export function isTransientPersonAvailabilityError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error ?? "");
  return PERSON_NOT_READY_PATTERNS.some((pattern) => pattern.test(message));
}

export async function withFubPersonRetry<T>(
  action: () => Promise<T>,
  options: {
    attempts?: number;
    initialDelayMs?: number;
  } = {}
): Promise<T> {
  const attempts = Math.max(1, options.attempts ?? 5);
  let delayMs = Math.max(100, options.initialDelayMs ?? 400);

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await action();
    } catch (error) {
      if (attempt >= attempts || !isTransientPersonAvailabilityError(error)) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, delayMs));
      delayMs *= 2;
    }
  }

  throw new Error("FUB retry loop exited unexpectedly");
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
  apiKey: string,
  person: FubPersonPayload
): Promise<number | undefined> {
  const email = person.emails?.[0]?.value?.trim();
  if (email) {
    const res = await fetch(
      `${FUB_API_BASE}/people?email=${encodeURIComponent(email)}&limit=1&fields=id`,
      {
        method: "GET",
        headers: authHeaders(apiKey),
      }
    );
    if (res.ok) {
      const data = (await res.json()) as unknown;
      const personId = extractPersonIdFromPeopleSearch(data);
      if (personId != null) return personId;
    }
  }

  const phone = person.phones?.[0]?.value?.trim();
  if (phone) {
    const res = await fetch(
      `${FUB_API_BASE}/people?phone=${encodeURIComponent(phone)}&limit=1&fields=id`,
      {
        method: "GET",
        headers: authHeaders(apiKey),
      }
    );
    if (res.ok) {
      const data = (await res.json()) as unknown;
      const personId = extractPersonIdFromPeopleSearch(data);
      if (personId != null) return personId;
    }
  }

  return undefined;
}

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

  const raw = await res.text();
  if (raw.trim()) {
    const data = JSON.parse(raw) as { id?: number; personId?: number };
    const personId = data?.personId ?? data?.id;
    if (personId != null) {
      return { personId: Number(personId) };
    }
  }

  const fallbackPersonId = await resolvePersonIdByContact(apiKey, person);
  if (fallbackPersonId == null) {
    throw new Error("FUB events response missing person id");
  }
  return { personId: fallbackPersonId };
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

export async function getCurrentUserId(apiKey: string): Promise<number | undefined> {
  const res = await fetch(`${FUB_API_BASE}/me`, {
    method: "GET",
    headers: authHeaders(apiKey),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `FUB /me returned ${res.status}`);
  }

  const data = (await res.json()) as { id?: number | string };
  const id = data?.id;
  if (id == null || !Number.isFinite(Number(id))) {
    return undefined;
  }
  return Number(id);
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
  options: {
    type?: string;
    assignedUserId?: number;
  } = {}
): Promise<{ id: number }> {
  const dueDate = dueAt.slice(0, 10);
  const res = await fetch(`${FUB_API_BASE}/tasks`, {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify({
      personId,
      name,
      type: options.type ?? "Follow Up",
      dueDate,
      dueDateTime: dueAt,
      ...(options.assignedUserId != null ? { assignedUserId: options.assignedUserId } : {}),
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
  options: {
    location?: string | null;
    description?: string | null;
    assignedUserId?: number | null;
  } = {}
): Promise<{ id: number }> {
  const invitees: Array<{ personId?: number; userId?: number }> = [{ personId }];
  if (options.assignedUserId != null) {
    invitees.push({ userId: options.assignedUserId });
  }

  const res = await fetch(`${FUB_API_BASE}/appointments`, {
    method: "POST",
    headers: authHeaders(apiKey),
    body: JSON.stringify({
      title,
      start: startAt,
      end: endAt,
      ...(options.location && { location: options.location }),
      ...(options.description && { description: options.description }),
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
