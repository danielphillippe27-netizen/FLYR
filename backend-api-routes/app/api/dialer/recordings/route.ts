import { NextResponse, type NextRequest } from "next/server";
import { resolveDialerWorkspace } from "../_utils";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const { response } = await resolveDialerWorkspace(request);
    if (response) return response;

    return NextResponse.json({ groups: [] });
  } catch (error) {
    console.error("[dialer/recordings]", error);
    return NextResponse.json(
      { error: "Failed to load recordings." },
      { status: 500 }
    );
  }
}
