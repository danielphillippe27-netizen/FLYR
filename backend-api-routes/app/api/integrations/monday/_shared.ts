import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  mondayGraphQLRequest,
  resolveMondayColumnMapping,
  type MondayBoard,
} from "../../../lib/monday";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

export type MondayIntegrationRow = {
  id: string;
  access_token: string | null;
  refresh_token?: string | null;
  expires_at?: number | null;
  account_id: string | null;
  account_name: string | null;
  selected_board_id: string | number | null;
  selected_board_name: string | null;
  provider_config: Record<string, any> | null;
  updated_at: string | null;
};

export function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

export async function resolveMondayUser(request: Request): Promise<
  | { user: { id: string }; supabaseAdmin: any }
  | { response: NextResponse }
> {
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;
  if (!token) {
    return { response: jsonError("Missing or invalid authorization", 401) };
  }

  const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const {
    data: { user },
    error: userError,
  } = await supabaseAnon.auth.getUser(token);

  if (userError || !user) {
    return { response: jsonError("Invalid or expired token", 401) };
  }

  return {
    user: { id: user.id },
    supabaseAdmin: createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY),
  };
}

export async function loadMondayIntegration(
  supabaseAdmin: any,
  userId: string
): Promise<{ row: MondayIntegrationRow | null; response?: NextResponse }> {
  const { data, error } = await supabaseAdmin
    .from("user_integrations")
    .select("id, access_token, refresh_token, expires_at, account_id, account_name, selected_board_id, selected_board_name, provider_config, updated_at")
    .eq("user_id", userId)
    .eq("provider", "monday")
    .maybeSingle();

  if (error) {
    console.error("[monday] integration fetch failed", error);
    return { row: null, response: jsonError("Failed to load Monday.com integration", 500) };
  }

  return { row: (data as MondayIntegrationRow | null) ?? null };
}

export async function fetchMondayBoards(accessToken: string): Promise<MondayBoard[]> {
  const data = await mondayGraphQLRequest<{
    boards: Array<{
      id: string | number;
      name: string;
      state?: string | null;
      workspace?: { id?: string | number | null; name?: string | null } | null;
      columns: Array<{ id: string; title: string; type: string }>;
    }>;
  }>(
    accessToken,
    `
      query {
        boards(limit: 100) {
          id
          name
          state
          workspace {
            id
            name
          }
          columns {
            id
            title
            type
          }
        }
      }
    `
  );

  return (data.boards ?? [])
    .filter((board) => board.state !== "archived" && board.state !== "deleted")
    .map((board) => ({
      id: String(board.id),
      name: board.name,
      state: board.state ?? null,
      workspace: board.workspace
        ? {
            id: board.workspace.id != null ? String(board.workspace.id) : null,
            name: board.workspace.name ?? null,
          }
        : null,
      columns: (board.columns ?? []).map((column) => ({
        id: column.id,
        title: column.title,
        type: column.type,
      })),
    }));
}

export function buildMondayProviderConfig(
  board: MondayBoard,
  body: Record<string, unknown>,
  existingConfig?: Record<string, any> | null
) {
  return {
    ...(existingConfig ?? {}),
    workspaceId: stringValue(body.workspaceId) ?? stringValue(body.workspace_id) ?? board.workspace?.id ?? null,
    workspaceName:
      stringValue(body.workspaceName) ?? stringValue(body.workspace_name) ?? board.workspace?.name ?? null,
    columnMapping: resolveMondayColumnMapping(board.columns, existingConfig?.columnMapping ?? null),
  };
}

export function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed || null;
}
