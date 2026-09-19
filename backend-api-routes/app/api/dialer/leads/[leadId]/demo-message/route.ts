import { createAdminClient } from '@/lib/supabase/server';
import { resolveSalespersonForUser } from '@/lib/dialer/salesperson-settings';
import { NextRequest, NextResponse } from "next/server";
import { SALES_DEMO_URL } from "@/lib/email/demo";
import { resolveDialerWorkspace } from "../../../_utils";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{ leadId: string }>;
};

function cleanString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

export async function POST(request: NextRequest, _routeContext: RouteContext) {
  try {
    const payload = await request.json().catch(() => ({}));
    const requestedWorkspaceId = cleanString(payload.workspaceId);
    const url = new URL(request.url);
    if (requestedWorkspaceId) {
      url.searchParams.set("workspaceId", requestedWorkspaceId);
    }

    const { response, context } = await resolveDialerWorkspace(
      new NextRequest(url, {
        headers: request.headers,
        method: request.method,
      })
    );
    if (response) return response;

    const salesperson = await resolveSalespersonForUser(createAdminClient(), {
      userId: context!.user.id, workspaceId: context!.workspace!.id,
    });
    const senderName = salesperson?.full_name?.trim() || 'WolfGrid Sales';
    const link = SALES_DEMO_URL;

    return NextResponse.json({
      demoUrl: link,
      demoLinkToken: null,
      textBody: `Hey, ${senderName} with WolfGrid. Here is the demo: ${link}`,
      emailSubject: `Quick WolfGrid demo`,
      emailBody: `Hey,\n\n${senderName} with WolfGrid here. Here is the demo video: ${link}\n\nBest,\n${senderName}`,
      tracked: false,

    });
  } catch (error) {
    console.error("[dialer/leads/demo-message] POST", error);
    return NextResponse.json(
      { error: "Failed to prepare demo message." },
      { status: 500 }
    );
  }
}
