import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "@/app/api/access/_utils";
import { loadDemoState, patchDemoState } from "@/lib/onboarding-demo/service";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    return NextResponse.json(await loadDemoState(context));
  } catch (error) {
    console.error("[onboarding/demo/state] GET", error);
    return NextResponse.json({ error: "Failed to load onboarding demo state." }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    const body = await request.json().catch(() => ({}));
    return NextResponse.json(await patchDemoState(context, body));
  } catch (error) {
    console.error("[onboarding/demo/state] PATCH", error);
    return NextResponse.json({ error: "Failed to update onboarding demo state." }, { status: 500 });
  }
}
