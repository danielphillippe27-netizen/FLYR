export interface MondayColumn {
  id: string;
  title: string;
  type: string;
}

export interface MondayBoard {
  id: string;
  name: string;
  state?: string | null;
  workspace?: {
    id?: string | null;
    name?: string | null;
  } | null;
  columns: MondayColumn[];
}

export interface MondayColumnMappingEntry {
  columnId: string;
  columnTitle?: string;
  columnType?: string;
  strategy?: string;
}

export interface MondayProviderConfig {
  workspaceId?: string;
  workspaceName?: string;
  columnMapping?: Record<string, MondayColumnMappingEntry>;
}

const MONDAY_API_URL = "https://api.monday.com/v2";
const PSEUDO_ITEM_NAME = "__item_name__";
const PSEUDO_ITEM_UPDATE = "__item_update__";

type MondayFieldKey =
  | "name"
  | "phone"
  | "email"
  | "address"
  | "notes"
  | "followUpDate"
  | "appointmentStart"
  | "appointmentEnd"
  | "appointmentTitle"
  | "status";

const FIELD_ORDER: MondayFieldKey[] = [
  "phone",
  "email",
  "address",
  "notes",
  "followUpDate",
  "appointmentStart",
  "appointmentEnd",
  "appointmentTitle",
  "status",
];

const FIELD_KEYWORDS: Record<MondayFieldKey, string[]> = {
  name: ["name", "lead", "contact"],
  phone: ["phone", "mobile", "cell", "telephone"],
  email: ["email", "e-mail"],
  address: ["address", "street", "location"],
  notes: ["note", "notes", "details", "comments", "comment", "summary"],
  followUpDate: ["follow up", "follow-up", "reminder", "task due", "due", "call back", "callback"],
  appointmentStart: ["appointment start", "meeting start", "start", "appointment date", "meeting date"],
  appointmentEnd: ["appointment end", "meeting end", "end"],
  appointmentTitle: ["appointment title", "meeting title", "appointment", "meeting", "subject", "event"],
  status: ["status", "stage", "pipeline"],
};

const FIELD_TYPES: Record<MondayFieldKey, string[]> = {
  name: ["name"],
  phone: ["phone", "text"],
  email: ["email", "text"],
  address: ["location", "text", "long_text", "long-text"],
  notes: ["long_text", "long-text", "text"],
  followUpDate: ["date", "datetime"],
  appointmentStart: ["date", "datetime"],
  appointmentEnd: ["date", "datetime"],
  appointmentTitle: ["text", "long_text", "long-text"],
  status: ["status", "dropdown", "text"],
};

export function mondayPseudoValues() {
  return {
    itemName: PSEUDO_ITEM_NAME,
    itemUpdate: PSEUDO_ITEM_UPDATE,
  };
}

export async function mondayGraphQLRequest<T>(
  accessToken: string,
  query: string,
  variables?: Record<string, unknown>,
): Promise<T> {
  const response = await fetch(MONDAY_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: accessToken,
      "API-Version": "2023-10",
    },
    body: JSON.stringify({ query, variables }),
  });

  const payload = await response.json().catch(async () => ({
    errors: [{ message: await response.text() }],
  }));

  if (!response.ok) {
    throw new Error(`Monday API request failed: ${response.status} - ${JSON.stringify(payload)}`);
  }

  if (Array.isArray(payload.errors) && payload.errors.length > 0) {
    throw new Error(`Monday GraphQL error: ${JSON.stringify(payload.errors)}`);
  }

  return payload.data as T;
}

export function resolveMondayColumnMapping(
  columns: MondayColumn[],
  existingMapping?: Record<string, MondayColumnMappingEntry> | null,
): Record<string, MondayColumnMappingEntry> {
  const resolved: Record<string, MondayColumnMappingEntry> = {
    name: {
      columnId: PSEUDO_ITEM_NAME,
      columnTitle: "Item name",
      columnType: "name",
      strategy: "item_name",
    },
  };
  const availableById = new Map(columns.map((column) => [column.id, column]));
  const usedColumns = new Set<string>();

  for (const field of FIELD_ORDER) {
    const existing = existingMapping?.[field];
    if (existing?.columnId && availableById.has(existing.columnId)) {
      const currentColumn = availableById.get(existing.columnId)!;
      resolved[field] = {
        columnId: currentColumn.id,
        columnTitle: currentColumn.title,
        columnType: currentColumn.type,
        strategy: existing.strategy,
      };
      usedColumns.add(currentColumn.id);
      continue;
    }

    const bestColumn = findBestColumn(field, columns, usedColumns);
    if (bestColumn) {
      resolved[field] = {
        columnId: bestColumn.id,
        columnTitle: bestColumn.title,
        columnType: bestColumn.type,
      };
      usedColumns.add(bestColumn.id);
      continue;
    }

    if (field === "notes") {
      resolved[field] = {
        columnId: PSEUDO_ITEM_UPDATE,
        columnTitle: "Item update",
        columnType: "update",
        strategy: "update_comment",
      };
    }
  }

  return resolved;
}

function findBestColumn(
  field: MondayFieldKey,
  columns: MondayColumn[],
  usedColumns: Set<string>,
): MondayColumn | null {
  let bestColumn: MondayColumn | null = null;
  let bestScore = 0;

  for (const column of columns) {
    if (usedColumns.has(column.id)) continue;
    const score = scoreColumn(field, column);
    if (score > bestScore) {
      bestScore = score;
      bestColumn = column;
    }
  }

  return bestScore > 0 ? bestColumn : null;
}

function scoreColumn(field: MondayFieldKey, column: MondayColumn): number {
  const normalizedTitle = normalize(column.title);
  const normalizedType = normalize(column.type);
  let score = 0;

  for (const expectedType of FIELD_TYPES[field]) {
    if (normalizedType === normalize(expectedType)) {
      score += 6;
    } else if (normalizedType.includes(normalize(expectedType))) {
      score += 3;
    }
  }

  for (const keyword of FIELD_KEYWORDS[field]) {
    const normalizedKeyword = normalize(keyword);
    if (normalizedTitle === normalizedKeyword) {
      score += 10;
    } else if (normalizedTitle.includes(normalizedKeyword)) {
      score += 7;
    }
  }

  if (field === "notes" && (normalizedType === "long_text" || normalizedType === "long-text")) {
    score += 4;
  }

  if ((field === "appointmentStart" || field === "appointmentEnd" || field === "followUpDate") && normalizedType === "date") {
    score += 2;
  }

  return score;
}

function normalize(value: string | null | undefined): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
