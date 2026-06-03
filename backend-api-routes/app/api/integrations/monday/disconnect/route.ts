import { NextResponse } from "next/server";

import {
  resolveMondayUser,
} from "../_shared";

async function handleDisconnect(request: Request) {
  try {
    const resolved = await resolveMondayUser(request);
    if ("response" in resolved) return resolved.response;

    const { error } = await resolved.supabaseAdmin
      .from("user_integrations")
      .delete()
      .eq("user_id", resolved.user.id)
      .eq("provider", "monday");

    if (error) {
      console.error("[monday/disconnect]", error);
      return NextResponse.json({ error: "Failed to disconnect Monday.com" }, { status: 500 });
    }

    return NextResponse.json({ success: true, disconnected: true });
  } catch (error) {
    console.error("[monday/disconnect]", error);
    return NextResponse.json({ error: "Something went wrong" }, { status: 500 });
  }
}

export async function POST(request: Request) {
  return handleDisconnect(request);
}

export async function DELETE(request: Request) {
  return handleDisconnect(request);
}
