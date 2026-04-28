import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  CAMPAIGN_INVITE_TTL_DAYS,
  hashInviteToken,
  makeInviteToken,
} from "../../../lib/invite-tokens";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const DEFAULT_PUBLIC_JOIN_ORIGIN = "https://www.flyrpro.app";
type CreateInviteBody = {
  campaignId?: string | null;
  sessionId?: string | null;
};

type CampaignRow = {
  id: string;
  title: string | null;
  workspace_id: string | null;
  owner_id: string;
};

type WorkspaceRow = {
  id: string;
  name: string | null;
  owner_id: string;
};

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

function anonClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

function isMissingSessionIdColumnError(
  error:
    | {
        message?: string | null;
        details?: string | null;
        hint?: string | null;
      }
    | null
    | undefined
): boolean {
  const haystack = [error?.message, error?.details, error?.hint]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return (
    haystack.includes("session_id") &&
    (haystack.includes("column") || haystack.includes("schema cache") || haystack.includes("schema"))
  );
}

function isMissingColumnError(
  error:
    | {
        message?: string | null;
        details?: string | null;
        hint?: string | null;
      }
    | null
    | undefined,
  columnName: string
): boolean {
  const haystack = [error?.message, error?.details, error?.hint]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  const column = columnName.toLowerCase();
  return (
    haystack.includes(column) &&
    (haystack.includes("column") || haystack.includes("schema cache") || haystack.includes("schema"))
  );
}

function normalizedOrigin(value?: string | null): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;

  try {
    return new URL(trimmed).origin;
  } catch {
    return null;
  }
}

function isMainFlyrJoinOrigin(origin: string | null): boolean {
  return origin === "https://flyrpro.app" || origin === "https://www.flyrpro.app";
}

function buildInviteURL(request: Request, token: string): string {
  const requestURL = new URL(request.url);
  const requestHost = requestURL.host.toLowerCase();
  const fallbackOrigin =
    requestHost === "backend-api-routes.vercel.app"
      ? requestURL.origin
      : DEFAULT_PUBLIC_JOIN_ORIGIN;
  const legacyInviteOrigin = normalizedOrigin(process.env.FLYR_PUBLIC_INVITE_ORIGIN);
  const publicInviteOrigin =
    normalizedOrigin(process.env.FLYR_PUBLIC_JOIN_ORIGIN) ??
    legacyInviteOrigin ??
    fallbackOrigin;
  const url = new URL("/join", publicInviteOrigin);
  url.searchParams.set("token", token);
  return url.toString();
}

function buildShareMessage(inviteURL: string, campaignTitle?: string | null): string {
  const trimmedTitle = campaignTitle?.trim();
  if (trimmedTitle) {
    return [
      "I'm live in FLYR right now.",
      `Open this link to join my live session in ${trimmedTitle}.`,
      inviteURL,
    ].join("\n\n");
  }

  return [
    "I'm live in FLYR right now.",
    "Open this link to join my live session.",
    inviteURL,
  ].join("\n\n");
}

async function currentUserForRequest(request: Request) {
  const token = getBearerToken(request);
  if (!token) return null;

  const {
    data: { user },
    error,
  } = await anonClient().auth.getUser(token);

  if (error || !user) return null;
  return user;
}

async function canUserAccessCampaign(
  admin: ReturnType<typeof adminClient>,
  campaign: CampaignRow,
  userId: string
): Promise<boolean> {
  if (campaign.owner_id === userId) {
    return true;
  }

  if (campaign.workspace_id) {
    const { data: workspace } = await admin
      .from("workspaces")
      .select("id,owner_id")
      .eq("id", campaign.workspace_id)
      .maybeSingle();

    if ((workspace as Pick<WorkspaceRow, "id" | "owner_id"> | null)?.owner_id === userId) {
      return true;
    }

    const { data: workspaceMember } = await admin
      .from("workspace_members")
      .select("workspace_id")
      .eq("workspace_id", campaign.workspace_id)
      .eq("user_id", userId)
      .maybeSingle();

    if (workspaceMember?.workspace_id) {
      return true;
    }
  }

  const { data: campaignMember } = await admin
    .from("campaign_members")
    .select("campaign_id")
    .eq("campaign_id", campaign.id)
    .eq("user_id", userId)
    .maybeSingle();

  return !!campaignMember?.campaign_id;
}

export async function POST(request: Request) {
  try {
    const user = await currentUserForRequest(request);
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    let body: CreateInviteBody = {};
    try {
      body = (await request.json()) as CreateInviteBody;
    } catch {
      return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const campaignId = body.campaignId?.trim() || null;
    if (body.sessionId?.trim()) {
      return NextResponse.json(
        { error: "Live session links are no longer supported. Share the team code from the session instead." },
        { status: 400 }
      );
    }

    if (!campaignId) {
      return NextResponse.json({ error: "campaignId is required" }, { status: 400 });
    }

    const admin = adminClient();
    const { data: campaignData, error: campaignError } = await admin
      .from("campaigns")
      .select("id,title,workspace_id,owner_id")
      .eq("id", campaignId)
      .maybeSingle();

    const campaign = campaignData as CampaignRow | null;

    if (campaignError) {
      console.error("[invites/create] campaign lookup error:", campaignError);
      return NextResponse.json({ error: "Unable to load campaign" }, { status: 500 });
    }

    if (!campaign) {
      return NextResponse.json(
        { error: "Campaign not found." },
        { status: 404 }
      );
    }

    const hasAccess = await canUserAccessCampaign(admin, campaign, user.id);
    if (!hasAccess) {
      return NextResponse.json({ error: "You do not have access to invite people to this campaign." }, { status: 403 });
    }

    const workspaceId = campaign.workspace_id ?? null;

    if (!workspaceId) {
      return NextResponse.json(
        { error: "Campaign invites require a workspace-backed campaign." },
        { status: 400 }
      );
    }

    const { data: workspaceData, error: workspaceError } = await admin
      .from("workspaces")
      .select("id,name,owner_id")
      .eq("id", workspaceId)
      .maybeSingle();

    const workspace = workspaceData as WorkspaceRow | null;

    if (workspaceError) {
      console.error("[invites/create] workspace lookup error:", workspaceError);
      return NextResponse.json({ error: "Unable to load workspace" }, { status: 500 });
    }

    if (!workspace) {
      return NextResponse.json({ error: "Workspace not found" }, { status: 404 });
    }

    const inviteToken = makeInviteToken();
    const inviteTokenHash = hashInviteToken(inviteToken);
    const inviteTTLMilliseconds = CAMPAIGN_INVITE_TTL_DAYS * 24 * 60 * 60 * 1000;
    const expiresAt = new Date(Date.now() + inviteTTLMilliseconds).toISOString();

    const inviteInsert = {
      workspace_id: workspace.id,
      campaign_id: campaign.id,
      session_id: null,
      created_by: user.id,
      email: "",
      role: "member",
      token: inviteTokenHash,
      invite_token: inviteTokenHash,
      invite_token_hash: inviteTokenHash,
      expires_at: expiresAt,
    };

    let storedSessionId = null;
    let { error: insertError } = await admin.from("workspace_invites").insert(inviteInsert);

    if (insertError && isMissingSessionIdColumnError(insertError)) {
      storedSessionId = null;
      const { session_id: _ignoredSessionId, ...legacyInviteInsert } = inviteInsert;
      const legacyInsert = await admin.from("workspace_invites").insert(legacyInviteInsert);
      insertError = legacyInsert.error;
    }

    if (insertError && isMissingColumnError(insertError, "token")) {
      const { token: _ignoredToken, ...tokenlessInviteInsert } = inviteInsert;
      const retryInsert = await admin.from("workspace_invites").insert(tokenlessInviteInsert);
      insertError = retryInsert.error;
    }

    if (insertError && isMissingColumnError(insertError, "invite_token")) {
      const { invite_token: _ignoredInviteToken, ...legacyTokenInviteInsert } = inviteInsert;
      const retryInsert = await admin.from("workspace_invites").insert(legacyTokenInviteInsert);
      insertError = retryInsert.error;
    }

    if (insertError && isMissingColumnError(insertError, "invite_token_hash")) {
      const { invite_token_hash: _ignoredInviteTokenHash, ...legacyHashlessInviteInsert } = inviteInsert;
      const retryInsert = await admin.from("workspace_invites").insert(legacyHashlessInviteInsert);
      insertError = retryInsert.error;
    }

    if (insertError) {
      console.error("[invites/create] insert error:", insertError);
      const dbMessage =
        [insertError.message, insertError.details, insertError.hint]
          .filter(Boolean)
          .join(" - ") || "Unable to create invite link";
      return NextResponse.json({ error: dbMessage }, { status: 500 });
    }

    const inviteURL = buildInviteURL(request, inviteToken);

    return NextResponse.json({
      success: true,
      invite_url: inviteURL,
      share_message: buildShareMessage(inviteURL, campaign.title),
      workspace_id: workspace.id,
      workspace_name: workspace.name,
      campaign_id: campaign.id,
      campaign_title: campaign.title,
      session_id: storedSessionId,
      role: "member",
      expires_at: expiresAt,
    });
  } catch (error) {
    console.error("[invites/create]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
