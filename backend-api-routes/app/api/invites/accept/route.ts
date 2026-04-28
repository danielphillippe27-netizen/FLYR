import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { hashInviteToken } from "../../../lib/invite-tokens";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type AcceptInviteBody = {
  token?: string;
};

type InviteRow = {
  id: string;
  workspace_id: string;
  campaign_id: string | null;
  session_id?: string | null;
  email: string | null;
  role: string;
  accepted_by: string | null;
  accepted_at: string | null;
  expires_at: string | null;
};

type WorkspaceRow = {
  id: string;
  owner_id: string;
};

type CampaignRow = {
  id: string;
  owner_id: string;
};

type SessionStatusRow = {
  id: string;
  end_time: string | null;
};

function normalizeInviteEmail(value: string | null | undefined): string | null {
  const cleaned = value?.replace(/[\u200B-\u200D\uFEFF]/g, "").trim().toLowerCase();
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

function normalizeInviteRole(role: string | null | undefined): "admin" | "member" {
  return role === "admin" ? "admin" : "member";
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
    .select("id,workspace_id,campaign_id,session_id,email,role,accepted_by,accepted_at,expires_at")
    .eq(columnName, candidateToken)
    .maybeSingle();

  if (error && isMissingSessionIdColumnError(error)) {
    ({ data, error } = await admin
      .from("workspace_invites")
      .select("id,workspace_id,campaign_id,email,role,accepted_by,accepted_at,expires_at")
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
    console.error("[invites/accept] session lookup error:", sessionError);
    return null;
  }

  const session = sessionData as SessionStatusRow | null;
  if (!session || session.end_time) {
    return null;
  }

  return session.id;
}

async function buildAcceptSuccessResponse(
  admin: ReturnType<typeof adminClient>,
  invite: InviteRow,
  alreadyAccepted: boolean
) {
  const liveSessionId = await resolveLiveSessionId(admin, invite.session_id);
  const accessScope = invite.campaign_id ? "campaign" : "workspace";

  return NextResponse.json({
    success: true,
    workspace_id: invite.workspace_id,
    workspaceId: invite.workspace_id,
    campaign_id: invite.campaign_id,
    campaignId: invite.campaign_id,
    session_id: liveSessionId,
    sessionId: liveSessionId,
    access_scope: accessScope,
    accessScope: accessScope,
    redirect: "dashboard",
    already_accepted: alreadyAccepted,
    alreadyAccepted: alreadyAccepted,
  });
}

export async function POST(request: Request) {
  try {
    const token = getBearerToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const {
      data: { user },
      error: userError,
    } = await anonClient().auth.getUser(token);

    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    let body: AcceptInviteBody;
    try {
      body = (await request.json()) as AcceptInviteBody;
    } catch {
      return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const inviteToken = body.token?.trim();
    if (!inviteToken) {
      return NextResponse.json({ error: "Token required." }, { status: 400 });
    }

    const admin = adminClient();
    const { invite, error: inviteError } = await findInviteByToken(admin, inviteToken);

    if (inviteError) {
      console.error("[invites/accept] invite lookup error:", inviteError);
      return NextResponse.json({ error: "Unable to accept invite." }, { status: 500 });
    }

    if (!invite) {
      return NextResponse.json({ error: "Invalid or expired invite." }, { status: 404 });
    }

    if (invite.expires_at && new Date(invite.expires_at) <= new Date()) {
      return NextResponse.json(
        { error: "This invite has already been used or has expired." },
        { status: 400 }
      );
    }

    const userEmail = normalizeInviteEmail(user.email) ?? "";
    const inviteEmail = normalizeInviteEmail(invite.email);
    if (inviteEmail && inviteEmail !== userEmail) {
      return NextResponse.json(
        { error: "This invite was sent to a different email address." },
        { status: 403 }
      );
    }

    if (invite.accepted_at) {
      if (invite.accepted_by === user.id) {
        return buildAcceptSuccessResponse(admin, invite, true);
      }

      return NextResponse.json(
        { error: "This invite has already been used or has expired." },
        { status: 400 }
      );
    }

    const [{ data: workspaceData }, { data: campaignData }] = await Promise.all([
      admin
        .from("workspaces")
        .select("id,owner_id")
        .eq("id", invite.workspace_id)
        .maybeSingle(),
      invite.campaign_id
        ? admin
            .from("campaigns")
            .select("id,owner_id")
            .eq("id", invite.campaign_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    const workspace = workspaceData as WorkspaceRow | null;
    const campaign = campaignData as CampaignRow | null;

    if (!workspace) {
      return NextResponse.json({ error: "Workspace not found." }, { status: 404 });
    }

    const normalizedRole = normalizeInviteRole(invite.role);
    const acceptedAt = new Date().toISOString();
    const { data: claimedRows, error: claimError } = await admin
      .from("workspace_invites")
      .update({
        accepted_at: acceptedAt,
        accepted_by: user.id,
      })
      .eq("id", invite.id)
      .is("accepted_at", null)
      .select("id")
      .limit(1);

    if (claimError) {
      console.error("[invites/accept] invite claim error:", claimError);
      return NextResponse.json({ error: "Unable to accept invite." }, { status: 500 });
    }

    if (!claimedRows || claimedRows.length === 0) {
      const { data: latestInviteData, error: latestInviteError } = await admin
        .from("workspace_invites")
        .select("accepted_by,accepted_at")
        .eq("id", invite.id)
        .maybeSingle();

      if (latestInviteError) {
        console.error("[invites/accept] latest invite lookup error:", latestInviteError);
        return NextResponse.json({ error: "Unable to accept invite." }, { status: 500 });
      }

      const latestInvite = latestInviteData as Pick<InviteRow, "accepted_by" | "accepted_at"> | null;
      if (latestInvite?.accepted_at && latestInvite.accepted_by === user.id) {
        return buildAcceptSuccessResponse(admin, invite, true);
      }

      return NextResponse.json(
        { error: "This invite has already been used or has expired." },
        { status: 400 }
      );
    }

    const grantsWorkspaceMembership = !invite.campaign_id;
    const alreadyWorkspaceOwner = grantsWorkspaceMembership && workspace.owner_id === user.id;
    let alreadyWorkspaceMember = false;

    if (grantsWorkspaceMembership) {
      const { data: existingWorkspaceMembership } = await admin
        .from("workspace_members")
        .select("workspace_id")
        .eq("workspace_id", invite.workspace_id)
        .eq("user_id", user.id)
        .maybeSingle();

      alreadyWorkspaceMember = !!existingWorkspaceMembership?.workspace_id;

      if (!alreadyWorkspaceOwner && !alreadyWorkspaceMember) {
        const { error: workspaceInsertError } = await admin.from("workspace_members").upsert(
          {
            workspace_id: invite.workspace_id,
            user_id: user.id,
            role: normalizedRole,
          },
          {
            onConflict: "workspace_id,user_id",
            ignoreDuplicates: true,
          }
        );

        if (workspaceInsertError) {
          console.error("[invites/accept] workspace member upsert error:", workspaceInsertError);
          return NextResponse.json({ error: "Unable to accept invite." }, { status: 500 });
        }
      }
    }

    let alreadyCampaignMember = false;
    if (invite.campaign_id && campaign && campaign.owner_id !== user.id) {
      const { data: existingCampaignMembership } = await admin
        .from("campaign_members")
        .select("campaign_id")
        .eq("campaign_id", invite.campaign_id)
        .eq("user_id", user.id)
        .maybeSingle();

      alreadyCampaignMember = !!existingCampaignMembership?.campaign_id;

      if (!alreadyCampaignMember) {
        const { error: campaignInsertError } = await admin.from("campaign_members").upsert(
          {
            campaign_id: invite.campaign_id,
            user_id: user.id,
            role: normalizedRole,
          },
          {
            onConflict: "campaign_id,user_id",
            ignoreDuplicates: true,
          }
        );

        if (campaignInsertError) {
          console.error("[invites/accept] campaign member upsert error:", campaignInsertError);
          return NextResponse.json({ error: "Unable to accept invite." }, { status: 500 });
        }
      }
    }

    return buildAcceptSuccessResponse(
      admin,
      invite,
      alreadyWorkspaceOwner || alreadyWorkspaceMember || alreadyCampaignMember
    );
  } catch (error) {
    console.error("[invites/accept]", error);
    return NextResponse.json({ error: "Unable to accept invite." }, { status: 500 });
  }
}
