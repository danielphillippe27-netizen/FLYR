import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

export type CampaignVoiceAccess = {
  campaignId: string;
  workspaceId: string | null;
  userId: string;
  displayName: string;
};

type CampaignRow = {
  id: string;
  owner_id: string;
  workspace_id: string | null;
};

type WorkspaceRow = {
  id: string;
  owner_id: string;
};

type ProfileRow = {
  id: string;
  full_name?: string | null;
  display_name?: string | null;
  email?: string | null;
};

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

function normalizeDisplayName(profile: ProfileRow | null, fallbackUserId: string): string {
  const candidate = profile?.display_name?.trim()
    || profile?.full_name?.trim()
    || profile?.email?.trim();

  if (candidate) return candidate;
  return `Rep ${fallbackUserId.slice(0, 4).toUpperCase()}`;
}

export async function validateCampaignVoiceAccess(
  campaignId: string,
  userId: string
): Promise<CampaignVoiceAccess | null> {
  const admin = adminClient();

  const { data: campaignData, error: campaignError } = await admin
    .from("campaigns")
    .select("id,owner_id,workspace_id")
    .eq("id", campaignId)
    .maybeSingle();

  if (campaignError) {
    throw campaignError;
  }

  const campaign = campaignData as CampaignRow | null;
  if (!campaign) {
    return null;
  }

  let hasAccess = campaign.owner_id === userId;

  if (!hasAccess && campaign.workspace_id) {
    const { data: workspaceData, error: workspaceError } = await admin
      .from("workspaces")
      .select("id,owner_id")
      .eq("id", campaign.workspace_id)
      .maybeSingle();

    if (workspaceError) {
      throw workspaceError;
    }

    const workspace = workspaceData as WorkspaceRow | null;
    hasAccess = workspace?.owner_id === userId;

    if (!hasAccess) {
      const { data: workspaceMember, error: workspaceMemberError } = await admin
        .from("workspace_members")
        .select("workspace_id")
        .eq("workspace_id", campaign.workspace_id)
        .eq("user_id", userId)
        .maybeSingle();

      if (workspaceMemberError) {
        throw workspaceMemberError;
      }

      hasAccess = !!workspaceMember?.workspace_id;
    }
  }

  if (!hasAccess) {
    const { data: campaignMember, error: campaignMemberError } = await admin
      .from("campaign_members")
      .select("campaign_id")
      .eq("campaign_id", campaign.id)
      .eq("user_id", userId)
      .maybeSingle();

    if (campaignMemberError) {
      throw campaignMemberError;
    }

    hasAccess = !!campaignMember?.campaign_id;
  }

  if (!hasAccess) {
    return null;
  }

  let profile: ProfileRow | null = null;
  const { data: profileData, error: profileError } = await admin
    .from("profiles")
    .select("id,full_name,display_name,email")
    .eq("id", userId)
    .maybeSingle();

  if (profileError) {
    const message = [profileError.message, profileError.details, profileError.hint]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

    if (!message.includes("profiles")) {
      throw profileError;
    }
  } else {
    profile = (profileData as ProfileRow | null) ?? null;
  }

  return {
    campaignId: campaign.id,
    workspaceId: campaign.workspace_id ?? null,
    userId,
    displayName: normalizeDisplayName(profile, userId),
  };
}
