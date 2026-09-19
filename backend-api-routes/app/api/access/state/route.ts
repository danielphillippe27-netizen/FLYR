import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "../_utils";
import { createAdminClient } from "@/lib/supabase/server";
import { resolveDashboardAccessLevel } from "@/app/api/_utils/workspace";
import { resolveSalespersonForUser } from "@/lib/dialer/salesperson-settings";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const admin = createAdminClient();
    const access = await resolveDashboardAccessLevel(admin, context.user.id, context.workspace?.id);
    const salesperson =
      !access.isFounder && access.role !== "owner" && access.role !== "admin"
        ? await resolveSalespersonForUser(admin, {
            userId: context.user.id,
            email: context.user.email,
            workspaceId: access.workspaceId,
          })
        : null;
    const isSalesperson = !!salesperson;

    return NextResponse.json({
      user_id: context.user.id,
      userId: context.user.id,
      role: access.role,
      name: context.workspace?.name ?? null,
      workspaceName: context.workspace?.name ?? null,
      industry: context.workspace?.industry ?? null,
      workspace_id: access.workspaceId,
      workspaceId: access.workspaceId,
      accessLevel: isSalesperson ? "salesperson" : access.level,
      dashboardMode: isSalesperson ? "salesperson" : null,
      salespersonId: salesperson?.id ?? null,
      salesperson,
      isSalesperson,
      canUseSalespersonDashboard: isSalesperson,
      isFounder: access.isFounder,
      memberCount: access.memberCount,
      has_access: context.hasAccess && isSalesperson,
      hasAccess: context.hasAccess && isSalesperson,
      reason: isSalesperson ? null : "salesperson-required",
      onboardingComplete: true,
    });
  } catch (error) {
    console.error("[access/state]", error);
    return NextResponse.json(
      { error: "Failed to load access state." },
      { status: 500 }
    );
  }
}
