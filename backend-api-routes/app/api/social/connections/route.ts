import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { platformCredentials, SOCIAL_PLATFORMS } from '@/lib/social/platforms';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await context.admin
    .from('social_connections')
    .select('id,platform,external_account_id,account_name,account_avatar_url,status,scopes,token_expires_at,last_error,created_at,metadata')
    .eq('social_workspace_id', context.socialWorkspaceId)
    .order('created_at', { ascending: true });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const providerAvailability = Object.fromEntries(SOCIAL_PLATFORMS.map((platform) => {
    const credentials = platformCredentials(platform);
    const configured = Boolean(credentials.clientId && credentials.clientSecret);
    return [platform, {
      configured,
      message: configured ? null : `${platform === 'youtube' ? 'YouTube' : platform === 'linkedin' ? 'LinkedIn' : platform[0].toUpperCase() + platform.slice(1)} OAuth setup is not configured yet.`,
    }];
  }));
  const connections = (data ?? []).map(({ metadata, ...connection }) => ({
    ...connection,
    account_type: typeof metadata?.accountType === 'string' ? metadata.accountType : null,
    page_role: typeof metadata?.pageRole === 'string' ? metadata.pageRole : null,
  }));
  return NextResponse.json({ connections, socialWorkspace: context.socialWorkspace, providerAvailability });
}
