import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext, toAccessStatePayload } from "../_utils";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    return NextResponse.json(toAccessStatePayload(context));
  } catch (error) {
    console.error("[access/state]", error);
    return NextResponse.json(
      { error: "Failed to load access state." },
      { status: 500 }
    );
  }
}
