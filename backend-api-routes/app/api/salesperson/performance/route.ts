import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { resolveAccessContext } from "../../access/_utils";
import {
  getSupabaseServiceRoleKey,
  getSupabaseUrl,
} from "@/lib/supabase/env";

export const dynamic = "force-dynamic";

type Period = "daily" | "weekly" | "monthly" | "yearly";

type ProfileRow = {
  full_name?: string | null;
  email?: string | null;
};

function adminClient() {
  return createClient(getSupabaseUrl(), getSupabaseServiceRoleKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function cleanText(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function periodFromRequest(request: NextRequest): Period {
  const raw = request.nextUrl.searchParams.get("period")?.toLowerCase();
  if (raw === "weekly" || raw === "monthly" || raw === "yearly") {
    return raw;
  }
  return "daily";
}

function rangeForPeriod(period: Period): { start: Date; end: Date } {
  const now = new Date();
  const start = new Date(now);

  switch (period) {
    case "weekly": {
      const day = start.getDay();
      const daysSinceMonday = (day + 6) % 7;
      start.setDate(start.getDate() - daysSinceMonday);
      start.setHours(0, 0, 0, 0);
      break;
    }
    case "monthly":
      start.setDate(1);
      start.setHours(0, 0, 0, 0);
      break;
    case "yearly":
      start.setMonth(0, 1);
      start.setHours(0, 0, 0, 0);
      break;
    case "daily":
    default:
      start.setHours(0, 0, 0, 0);
      break;
  }

  return { start, end: now };
}

async function profileForUser(userId: string): Promise<ProfileRow | null> {
  const { data, error } = await adminClient()
    .from("profiles")
    .select("full_name,email")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    console.warn("[salesperson/performance] profile lookup failed", {
      userId,
      message: error.message,
    });
    return null;
  }

  return (data as ProfileRow | null) ?? null;
}

export async function GET(request: NextRequest) {
  try {
    const context = await resolveAccessContext(request);
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    if (!context.workspace?.id || !context.hasAccess) {
      return NextResponse.json(
        { error: "Salesperson workspace is not available." },
        { status: 403 }
      );
    }

    const requestedWorkspaceId = cleanText(
      request.nextUrl.searchParams.get("workspaceId")
    );
    if (requestedWorkspaceId && requestedWorkspaceId !== context.workspace.id) {
      return NextResponse.json(
        { error: "Salesperson workspace is not available." },
        { status: 403 }
      );
    }

    const period = periodFromRequest(request);
    const range = rangeForPeriod(period);
    const profile = await profileForUser(context.user.id);
    const email = cleanText(profile?.email) ?? context.user.email ?? "";
    const fullName =
      cleanText(profile?.full_name) ??
      cleanText(context.user.email?.split("@")[0]) ??
      "Salesperson";

    return NextResponse.json({
      period,
      range: {
        start: range.start.toISOString(),
        end: range.end.toISOString(),
      },
      salesperson: {
        id: context.user.id,
        fullName,
        email,
        referralCode: null,
        workspaceId: context.workspace.id,
        trackedLink: null,
      },
      outreach: {
        calls: 0,
        answers: 0,
        messages: 0,
        outboundMessages: 0,
        inboundMessages: 0,
        emails: 0,
        demosSent: 0,
      },
      links: {
        opens: 0,
        signups: 0,
      },
      revenue: {
        payingUsers: 0,
      },
      demoVideo: {
        sessions: 0,
        pageViews: 0,
        videoStarts: 0,
        playWithSound: 0,
        progress25: 0,
        progress50: 0,
        progress75: 0,
        completions: 0,
        ctaShown: 0,
        startTrialClicks: 0,
        founderCallClicks: 0,
        exits: 0,
        averageWatchSeconds: 0,
        maxWatchSeconds: 0,
      },
    });
  } catch (error) {
    console.error("[salesperson/performance]", error);
    return NextResponse.json(
      { error: "Failed to load salesperson performance." },
      { status: 500 }
    );
  }
}
