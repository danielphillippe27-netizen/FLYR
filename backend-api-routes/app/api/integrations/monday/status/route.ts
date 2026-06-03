import { NextResponse } from "next/server";

import {
  loadMondayIntegration,
  resolveMondayUser,
} from "../_shared";

export async function GET(request: Request) {
  try {
    const resolved = await resolveMondayUser(request);
    if ("response" in resolved) return resolved.response;

    const { row, response } = await loadMondayIntegration(resolved.supabaseAdmin, resolved.user.id);
    if (response) return response;

    const connected = !!row?.access_token?.trim();
    return NextResponse.json({
      connected,
      status: connected ? "connected" : "disconnected",
      createdAt: null,
      updatedAt: row?.updated_at ?? null,
      selectedBoardId: row?.selected_board_id != null ? String(row.selected_board_id) : null,
      selectedBoardName: row?.selected_board_name ?? null,
      accountId: row?.account_id ?? null,
      accountName: row?.account_name ?? null,
      lastError: null,
      providerConfig: row?.provider_config ?? null,
    });
  } catch (error) {
    console.error("[monday/status]", error);
    return NextResponse.json({ connected: false, error: "Something went wrong" }, { status: 500 });
  }
}
