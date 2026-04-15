export const BOLDTRAIL_API_BASE =
  process.env.BOLDTRAIL_API_BASE?.trim().replace(/\/$/, "") || "https://api.kvcore.com";

const BOLDTRAIL_CONTACTS_URL = `${BOLDTRAIL_API_BASE}/v2/public/contacts`;
const BOLDTRAIL_CONTACT_URL = `${BOLDTRAIL_API_BASE}/v2/public/contact`;

export type BoldTrailLeadPayload = {
  id?: string;
  name?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  source?: string | null;
  notes?: string | null;
};

export type BoldTrailValidationResult = {
  accountName?: string | null;
  userEmail?: string | null;
};

export type BoldTrailUpsertResult = {
  contactId: string;
  action: "created" | "updated";
  raw: unknown;
};

export class BoldTrailAPIError extends Error {
  kind: "invalid_token" | "network" | "api";
  status?: number;

  constructor(
    kind: "invalid_token" | "network" | "api",
    message: string,
    status?: number
  ) {
    super(message);
    this.name = "BoldTrailAPIError";
    this.kind = kind;
    this.status = status;
  }
}

export class BoldTrailTokenValidator {
  constructor(private readonly client: BoldTrailAPIClient) {}

  async validate(token: string): Promise<BoldTrailValidationResult> {
    return this.client.validateToken(token);
  }
}

export class BoldTrailAPIClient {
  async validateToken(token: string): Promise<BoldTrailValidationResult> {
    const res = await this.requestJson(
      `${BOLDTRAIL_CONTACTS_URL}?limit=1`,
      {
        method: "GET",
      },
      token
    );

    const payload = res.body;
    return {
      accountName: pickString(payload, [
        "account_name",
        "accountName",
        "company",
        "office_name",
      ]),
      userEmail: pickString(payload, [
        "user_email",
        "userEmail",
        "email",
      ]),
    };
  }

  async createContact(
    token: string,
    lead: BoldTrailLeadPayload
  ): Promise<BoldTrailUpsertResult> {
    const payload = buildBoldTrailContactPayload(lead);
    const res = await this.requestJson(
      BOLDTRAIL_CONTACT_URL,
      {
        method: "POST",
        body: JSON.stringify(payload),
      },
      token
    );

    const contactId = extractBoldTrailContactId(res.body);
    if (!contactId) {
      throw new BoldTrailAPIError(
        "api",
        "BoldTrail did not return a contact ID for the created record."
      );
    }

    return {
      contactId,
      action: "created",
      raw: res.body,
    };
  }

  async updateContact(
    token: string,
    contactId: string,
    lead: BoldTrailLeadPayload
  ): Promise<BoldTrailUpsertResult> {
    const payload = buildBoldTrailContactPayload(lead);
    const res = await this.requestJson(
      `${BOLDTRAIL_CONTACT_URL}/${encodeURIComponent(contactId)}`,
      {
        method: "PUT",
        body: JSON.stringify(payload),
      },
      token
    );

    return {
      contactId,
      action: "updated",
      raw: res.body,
    };
  }

  private async requestJson(
    url: string,
    init: RequestInit,
    token: string
  ): Promise<{ body: unknown; response: Response }> {
    const trimmedToken = token.trim();
    if (!trimmedToken) {
      throw new BoldTrailAPIError("invalid_token", "BoldTrail token is missing.");
    }

    let response: Response;
    try {
      response = await fetch(url, {
        ...init,
        headers: {
          Authorization: `Bearer ${trimmedToken}`,
          "Content-Type": "application/json",
          ...(init.headers ?? {}),
        },
      });
    } catch {
      throw new BoldTrailAPIError(
        "network",
        "Unable to connect to BoldTrail. Please try again."
      );
    }

    const text = await response.text();
    const body = text.trim() ? safeJsonParse(text) : null;

    if (!response.ok) {
      throw normalizeBoldTrailError(response.status, body, text);
    }

    return { body, response };
  }
}

export function buildBoldTrailContactPayload(
  lead: BoldTrailLeadPayload
): Record<string, unknown> {
  const { firstName, lastName } = splitFullName(lead.name);

  // Keep the MVP payload intentionally small. Notes, tasks, and appointments
  // should layer onto provider-specific endpoints after the contact mapping is verified.
  return compactRecord({
    first_name: firstName,
    last_name: lastName,
    email: cleanedValue(lead.email),
    cell_phone_1: cleanedValue(lead.phone),
    primary_address: cleanedValue(lead.address),
    source: cleanedValue(lead.source) || "FLYR",
    capture_method: "FLYR",
    external_vendor_id: cleanedValue(lead.id),
    notes: cleanedValue(lead.notes),
  });
}

export function extractBoldTrailContactId(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const record = payload as Record<string, unknown>;

  for (const key of ["id", "contact_id", "contactId"]) {
    const value = record[key];
    if (value != null && `${value}`.trim()) return `${value}`.trim();
  }

  for (const key of ["data", "contact", "result"]) {
    const nested = record[key];
    const nestedId = extractBoldTrailContactId(nested);
    if (nestedId) return nestedId;
  }

  return null;
}

export function maskBoldTrailToken(token: string): string {
  const trimmed = token.trim();
  if (!trimmed) return "saved";
  const suffix = trimmed.slice(-4);
  return `••••${suffix || "saved"}`;
}

export function normalizeBoldTrailError(
  status: number,
  payload: unknown,
  rawText?: string
): BoldTrailAPIError {
  const message =
    pickString(payload, ["message", "error", "detail", "details"]) ||
    rawText?.trim() ||
    `BoldTrail returned ${status}.`;

  if (status === 401 || status === 403) {
    return new BoldTrailAPIError("invalid_token", "Invalid token", status);
  }

  if (status >= 500) {
    return new BoldTrailAPIError(
      "network",
      "Unable to connect to BoldTrail. Please try again.",
      status
    );
  }

  return new BoldTrailAPIError("api", sanitizeBoldTrailMessage(message), status);
}

function sanitizeBoldTrailMessage(message: string): string {
  const trimmed = message.trim();
  if (!trimmed) return "BoldTrail request failed.";
  if (/unauthorized|forbidden|invalid token|invalid api/i.test(trimmed)) {
    return "Invalid token";
  }
  return trimmed.length > 240 ? `${trimmed.slice(0, 237)}...` : trimmed;
}

function safeJsonParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function pickString(
  payload: unknown,
  keys: string[]
): string | null {
  if (!payload || typeof payload !== "object") return null;
  const record = payload as Record<string, unknown>;
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

function splitFullName(name?: string | null): { firstName?: string; lastName?: string } {
  const trimmed = cleanedValue(name);
  if (!trimmed) return {};
  const parts = trimmed.split(/\s+/);
  return {
    firstName: parts[0],
    lastName: parts.slice(1).join(" ") || undefined,
  };
}

function compactRecord(
  value: Record<string, unknown>
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry != null && entry !== "")
  );
}

function cleanedValue(value?: string | null): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}
