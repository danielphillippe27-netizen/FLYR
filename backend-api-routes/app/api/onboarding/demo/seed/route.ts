import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "@/app/api/access/_utils";
import { seedDemo } from "@/lib/onboarding-demo/service";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    if (context.role !== "owner" && context.role !== "admin") {
      return NextResponse.json({ error: "Only workspace owners and admins can seed demo data." }, { status: 403 });
    }
    return NextResponse.json(await seedDemo(context));
  } catch (error) {
    console.error("[onboarding/demo/seed]", error);
    return NextResponse.json({ error: "Failed to seed onboarding demo." }, { status: 500 });
  }
}
