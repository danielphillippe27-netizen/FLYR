import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { hashInviteToken } from "../../../lib/invite-tokens";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type InviteRow = {
  workspace_id: string;
  campaign_id: string | null;
  session_id?: string | null;
  created_by: string;
  email: string | null;
  role: string;
  accepted_by: string | null;
  accepted_at: string | null;
  expires_at: string | null;
};

type WorkspaceRow = {
  name: string | null;
};

type CampaignRow = {
  title: string | null;
};

type SessionStatusRow = {
  id: string;
  end_time: string | null;
};

function cleanInviteEmail(value: string | null | undefined): string | null {
  const cleaned = value?.replace(/[\u200B-\u200D\uFEFF]/g, "").trim();
  return cleaned ? cleaned : null;
}

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

async function selectInviteByTokenColumn(
  admin: ReturnType<typeof adminClient>,
  columnName: "invite_token_hash" | "invite_token" | "token",
  candidateToken: string
): Promise<{ invite: InviteRow | null; error: unknown | null }> {
  let { data, error } = await admin
    .from("workspace_invites")
    .select("workspace_id,campaign_id,session_id,created_by,email,role,accepted_by,accepted_at,expires_at")
    .eq(columnName, candidateToken)
    .maybeSingle();

  if (error && isMissingSessionIdColumnError(error)) {
    ({ data, error } = await admin
      .from("workspace_invites")
      .select("workspace_id,campaign_id,created_by,email,role,accepted_by,accepted_at,expires_at")
      .eq(columnName, candidateToken)
      .maybeSingle());
  }

  return {
    invite: (data as InviteRow | null) ?? null,
    error: error ?? null,
  };
}

async function findInviteByToken(
  admin: ReturnType<typeof adminClient>,
  inviteToken: string
): Promise<{ invite: InviteRow | null; error: unknown | null }> {
  const hashedToken = hashInviteToken(inviteToken);
  const attempts: Array<{
    columnName: "invite_token_hash" | "invite_token" | "token";
    candidateToken: string;
  }> = [
    { columnName: "invite_token_hash", candidateToken: hashedToken },
    { columnName: "invite_token", candidateToken: hashedToken },
    { columnName: "token", candidateToken: hashedToken },
    { columnName: "invite_token", candidateToken: inviteToken },
    { columnName: "token", candidateToken: inviteToken },
  ];

  let firstRecoverableError: unknown | null = null;

  for (const attempt of attempts) {
    const result = await selectInviteByTokenColumn(
      admin,
      attempt.columnName,
      attempt.candidateToken
    );
    if (result.invite) {
      return result;
    }
    if (result.error) {
      if (
        !isMissingColumnError(
          result.error as { message?: string | null; details?: string | null; hint?: string | null },
          attempt.columnName
        )
      ) {
        return result;
      }
      firstRecoverableError ??= result.error;
    }
  }

  return {
    invite: null,
    error: firstRecoverableError,
  };
}

async function resolveLiveSessionId(
  admin: ReturnType<typeof adminClient>,
  sessionId: string | null | undefined
): Promise<string | null> {
  if (!sessionId) return null;

  const { data: sessionData, error: sessionError } = await admin
    .from("sessions")
    .select("id,end_time")
    .eq("id", sessionId)
    .maybeSingle();

  if (sessionError) {
    console.error("[invites/validate] session lookup error:", sessionError);
    return null;
  }

  const session = sessionData as SessionStatusRow | null;
  if (!session || session.end_time) {
    return null;
  }

  return session.id;
}

function inviteInvalidResponse() {
  return NextResponse.json({ error: "Invalid or expired invite." }, { status: 404 });
}

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const token = url.searchParams.get("token")?.trim();
    if (!token) {
      return NextResponse.json({ error: "Token required." }, { status: 400 });
    }

    const bearerToken = getBearerToken(request);
    let currentUserId: string | null = null;
    if (bearerToken) {
      const {
        data: { user },
      } = await anonClient().auth.getUser(bearerToken);
      currentUserId = user?.id ?? null;
    }

    const admin = adminClient();
    const { invite, error: inviteError } = await findInviteByToken(admin, token);

    if (inviteError) {
      console.error("[invites/validate] invite lookup error:", inviteError);
      return NextResponse.json({ error: "Unable to validate invite." }, { status: 500 });
    }

    if (!invite) {
      return inviteInvalidResponse();
    }

    if (invite.accepted_at) {
      if (currentUserId && invite.accepted_by === currentUserId) {
        const [{ data: workspace }, { data: campaign }] = await Promise.all([
          admin.from("workspaces").select("name").eq("id", invite.workspace_id).maybeSingle(),
          invite.campaign_id
            ? admin
                .from("campaigns")
                .select("title")
                .eq("id", invite.campaign_id)
                .maybeSingle()
            : Promise.resolve({ data: null }),
        ]);

        const typedWorkspace = workspace as WorkspaceRow | null;
        const typedCampaign = campaign as CampaignRow | null;
        const liveSessionId = await resolveLiveSessionId(admin, invite.session_id);

        return NextResponse.json({
          valid: true,
          workspace_name: typedWorkspace?.name ?? null,
          workspaceName: typedWorkspace?.name ?? null,
          campaign_id: invite.campaign_id,
          campaignId: invite.campaign_id,
          campaign_title: typedCampaign?.title ?? null,
          campaignTitle: typedCampaign?.title ?? null,
          session_id: liveSessionId,
          sessionId: liveSessionId,
          access_scope: invite.campaign_id ? "campaign" : "workspace",
          accessScope: invite.campaign_id ? "campaign" : "workspace",
          email: cleanInviteEmail(invite.email),
          role: invite.role,
          already_accepted: true,
          alreadyAccepted: true,
        });
      }

      return NextResponse.json(
        { error: "This invite has already been used or has expired." },
        { status: 400 }
      );
    }

    if (invite.expires_at && new Date(invite.expires_at) <= new Date()) {
      return NextResponse.json(
        { error: "This invite has already been used or has expired." },
        { status: 400 }
      );
    }

    const [{ data: workspace }, { data: campaign }] = await Promise.all([
      admin.from("workspaces").select("name").eq("id", invite.workspace_id).maybeSingle(),
      invite.campaign_id
        ? admin
            .from("campaigns")
            .select("title")
            .eq("id", invite.campaign_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    const typedWorkspace = workspace as WorkspaceRow | null;
    const typedCampaign = campaign as CampaignRow | null;
    const liveSessionId = await resolveLiveSessionId(admin, invite.session_id);

    return NextResponse.json({
      valid: true,
      workspace_name: typedWorkspace?.name ?? null,
      workspaceName: typedWorkspace?.name ?? null,
      campaign_id: invite.campaign_id,
      campaignId: invite.campaign_id,
      campaign_title: typedCampaign?.title ?? null,
      campaignTitle: typedCampaign?.title ?? null,
      session_id: liveSessionId,
      sessionId: liveSessionId,
      access_scope: invite.campaign_id ? "campaign" : "workspace",
      accessScope: invite.campaign_id ? "campaign" : "workspace",
      email: cleanInviteEmail(invite.email),
      role: invite.role,
    });
  } catch (error) {
    console.error("[invites/validate]", error);
    return NextResponse.json({ error: "Unable to validate invite." }, { status: 500 });
  }
}
