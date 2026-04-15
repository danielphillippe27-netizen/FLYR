import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  mondayGraphQLRequest,
  resolveMondayColumnMapping,
  type MondayBoard,
} from "../_shared/monday.ts";

type MondayBoardsRequest = {
  action?: "list" | "select_board";
  board_id?: string;
  board_name?: string;
  workspace_id?: string;
  workspace_name?: string;
};

serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceKey);

    const {
      data: { user },
      error: userError,
    } = await authClient.auth.getUser();
    if (userError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = (await req.json().catch(() => ({}))) as MondayBoardsRequest;
    const action = body.action ?? "list";

    const { data: integration, error: integrationError } = await adminClient
      .from("user_integrations")
      .select("id, access_token, account_id, account_name, selected_board_id, selected_board_name, provider_config")
      .eq("user_id", user.id)
      .eq("provider", "monday")
      .maybeSingle();

    if (integrationError) {
      console.error("[monday_boards] integration fetch failed", integrationError);
      return json({ error: "Failed to load monday integration" }, 500);
    }

    if (!integration?.access_token) {
      return json({ error: "Monday.com is not connected" }, 400);
    }

    const boards = await fetchBoards(integration.access_token);
    console.log("[monday_boards] fetched boards", {
      userId: user.id,
      boardCount: boards.length,
      selectedBoardId: integration.selected_board_id ?? null,
    });

    if (action === "select_board") {
      const board = boards.find((candidate) => candidate.id === String(body.board_id ?? ""));
      if (!board) {
        return json({ error: "Selected board not found" }, 404);
      }

      const providerConfig = {
        workspaceId: body.workspace_id ?? board.workspace?.id ?? null,
        workspaceName: body.workspace_name ?? board.workspace?.name ?? null,
        columnMapping: resolveMondayColumnMapping(board.columns, integration.provider_config?.columnMapping ?? null),
      };

      const { error: updateError } = await adminClient
        .from("user_integrations")
        .update({
          selected_board_id: board.id,
          selected_board_name: board.name,
          provider_config: providerConfig,
          updated_at: new Date().toISOString(),
        })
        .eq("id", integration.id);

      if (updateError) {
        console.error("[monday_boards] board selection update failed", updateError);
        return json({ error: "Failed to save monday board selection" }, 500);
      }

      console.log("[monday_boards] saved board selection", {
        userId: user.id,
        boardId: board.id,
        boardName: board.name,
      });

      return json({
        success: true,
        selectedBoardId: board.id,
        selectedBoardName: board.name,
      });
    }

    return json({
      boards: boards.map((board) => ({
        id: board.id,
        name: board.name,
        workspaceId: board.workspace?.id ?? null,
        workspaceName: board.workspace?.name ?? null,
        state: board.state ?? null,
        columns: board.columns,
      })),
      selectedBoardId: integration.selected_board_id ?? null,
      selectedBoardName: integration.selected_board_name ?? null,
      accountId: integration.account_id ?? null,
      accountName: integration.account_name ?? null,
    });
  } catch (error) {
    console.error("[monday_boards] unexpected error", error);
    return json({
      error: error instanceof Error ? error.message : "Unknown error",
    }, 500);
  }
});

async function fetchBoards(accessToken: string): Promise<MondayBoard[]> {
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
    `,
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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
