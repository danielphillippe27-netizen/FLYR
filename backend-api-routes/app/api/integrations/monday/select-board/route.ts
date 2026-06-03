import { NextResponse } from "next/server";

import {
  buildMondayProviderConfig,
  fetchMondayBoards,
  loadMondayIntegration,
  resolveMondayUser,
  stringValue,
} from "../_shared";

export async function POST(request: Request) {
  try {
    const resolved = await resolveMondayUser(request);
    if ("response" in resolved) return resolved.response;

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const selectedBoardId = stringValue(body.boardId) ?? stringValue(body.board_id);
    if (!selectedBoardId) {
      return NextResponse.json({ error: "Board ID is required" }, { status: 400 });
    }

    const { row, response } = await loadMondayIntegration(resolved.supabaseAdmin, resolved.user.id);
    if (response) return response;
    if (!row?.access_token?.trim()) {
      return NextResponse.json({ error: "Monday.com is not connected" }, { status: 400 });
    }

    const boards = await fetchMondayBoards(row.access_token.trim());
    const board = boards.find((candidate) => candidate.id === selectedBoardId);
    if (!board) {
      return NextResponse.json({ error: "Selected board not found" }, { status: 404 });
    }

    const providerConfig = buildMondayProviderConfig(board, body, row.provider_config);
    const { error: updateError } = await resolved.supabaseAdmin
      .from("user_integrations")
      .update({
        selected_board_id: board.id,
        selected_board_name: stringValue(body.boardName) ?? stringValue(body.board_name) ?? board.name,
        provider_config: providerConfig,
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id);

    if (updateError) {
      console.error("[monday/select-board] update", updateError);
      return NextResponse.json({ error: "Failed to save monday board selection" }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      selectedBoardId: board.id,
      selectedBoardName: stringValue(body.boardName) ?? stringValue(body.board_name) ?? board.name,
    });
  } catch (error) {
    console.error("[monday/select-board]", error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to save Monday board" },
      { status: 500 }
    );
  }
}
