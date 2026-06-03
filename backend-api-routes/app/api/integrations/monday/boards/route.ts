import { NextResponse } from "next/server";

import {
  fetchMondayBoards,
  loadMondayIntegration,
  resolveMondayUser,
} from "../_shared";

export async function GET(request: Request) {
  try {
    const resolved = await resolveMondayUser(request);
    if ("response" in resolved) return resolved.response;

    const { row, response } = await loadMondayIntegration(resolved.supabaseAdmin, resolved.user.id);
    if (response) return response;
    if (!row?.access_token?.trim()) {
      return NextResponse.json({ error: "Monday.com is not connected" }, { status: 400 });
    }

    const boards = await fetchMondayBoards(row.access_token.trim());

    return NextResponse.json({
      boards: boards.map((board) => ({
        id: board.id,
        name: board.name,
        workspaceId: board.workspace?.id ?? null,
        workspaceName: board.workspace?.name ?? null,
        state: board.state ?? null,
        columns: board.columns,
      })),
      selectedBoardId: row.selected_board_id != null ? String(row.selected_board_id) : null,
      selectedBoardName: row.selected_board_name ?? null,
      accountId: row.account_id ?? null,
      accountName: row.account_name ?? null,
    });
  } catch (error) {
    console.error("[monday/boards]", error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to load Monday boards" },
      { status: 500 }
    );
  }
}
