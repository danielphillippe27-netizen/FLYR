import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "../_utils";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    if (!context.workspace) {
      return NextResponse.json({ redirect: "onboarding", path: "/onboarding" });
    }

    if (!context.hasAccess) {
      return NextResponse.json({
        redirect: "subscribe",
        path: `/subscribe?reason=${encodeURIComponent(context.reason ?? "member-inactive")}`,
      });
    }

    return NextResponse.json({ redirect: "dashboard", path: "/dashboard" });
  } catch (error) {
    console.error("[access/redirect]", error);
    return NextResponse.json(
      { error: "Failed to resolve access redirect." },
      { status: 500 }
    );
  }
}
