import { NextResponse, type NextRequest } from "next/server";
import { resolveDialerWorkspace } from "../_utils";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const { response } = await resolveDialerWorkspace(request);
    if (response) return response;

    return NextResponse.json({ lists: [] });
  } catch (error) {
    console.error("[dialer/smart-list-imports]", error);
    return NextResponse.json(
      { error: "Failed to load smart lists." },
      { status: 500 }
    );
  }
}
