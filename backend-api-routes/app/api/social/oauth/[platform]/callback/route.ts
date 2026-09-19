import { createHash } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { encryptSocialToken } from '@/lib/social/crypto';
import { FACEBOOK_PAGE_WEBHOOK_FIELDS, facebookPageHasPostingAccess, INSTAGRAM_WEBHOOK_FIELDS } from '@/lib/social/meta';
import { isLinkedInPagePostingRole, isSocialPlatform, linkedinOAuthScopes, linkedinOrganizationScopesEnabled, LINKEDIN_PAGE_POSTING_ROLES, metaApiVersion, oauthCallbackUrl, platformCredentials, PLATFORM_SCOPES, socialOrigin, type SocialPlatform } from '@/lib/social/platforms';

type TokenResult = { accessToken: string; refreshToken?: string; expiresIn?: number; externalId?: string; grantedScopes?: string[] };
type AccountResult = { id: string; name: string; avatar?: string; accessToken?: string; metadata?: Record<string, unknown> };

function stateHash(value: string) {
  return createHash('sha256').update(value).digest('hex');
}

async function exchangeCode(platform: SocialPlatform, code: string, requestUrl: string): Promise<TokenResult> {
  const credentials = platformCredentials(platform);
  if (!credentials.clientId || !credentials.clientSecret) throw new Error(`${platform} is not configured`);
  const redirectUri = oauthCallbackUrl(platform, requestUrl);
  const body = new URLSearchParams({ code, redirect_uri: redirectUri, grant_type: 'authorization_code' });
  if (platform === 'facebook') {
    body.set('client_id', credentials.clientId); body.set('client_secret', credentials.clientSecret);
    const response = await fetch(`https://graph.facebook.com/${metaApiVersion()}/oauth/access_token?${body}`);
    const result = await response.json();
    if (!response.ok || !result.access_token) throw new Error(result.error?.message || 'Facebook token exchange failed');
    const longLived = new URL(`https://graph.facebook.com/${metaApiVersion()}/oauth/access_token`);
    longLived.searchParams.set('grant_type', 'fb_exchange_token');
    longLived.searchParams.set('client_id', credentials.clientId);
    longLived.searchParams.set('client_secret', credentials.clientSecret);
    longLived.searchParams.set('fb_exchange_token', result.access_token);
    const longResponse = await fetch(longLived);
    const longResult = await longResponse.json();
    if (!longResponse.ok || !longResult.access_token) throw new Error(longResult.error?.message || 'Facebook long-lived authorization failed');
    return { accessToken: longResult.access_token, expiresIn: longResult.expires_in };
  }
  if (platform === 'instagram') {
    body.set('client_id', credentials.clientId); body.set('client_secret', credentials.clientSecret);
    const response = await fetch('https://api.instagram.com/oauth/access_token', { method: 'POST', body });
    const result = await response.json();
    if (!response.ok || !result.access_token) throw new Error(result.error_message || 'Instagram token exchange failed');
    const longUrl = new URL('https://graph.instagram.com/access_token');
    longUrl.searchParams.set('grant_type', 'ig_exchange_token');
    longUrl.searchParams.set('client_secret', credentials.clientSecret);
    longUrl.searchParams.set('access_token', result.access_token);
    const longResponse = await fetch(longUrl); const longResult = await longResponse.json();
    return { accessToken: longResult.access_token || result.access_token, expiresIn: longResult.expires_in, externalId: String(result.user_id || '') };
  }
  if (platform === 'tiktok') {
    body.set('client_key', credentials.clientId); body.set('client_secret', credentials.clientSecret);
    const response = await fetch('https://open.tiktokapis.com/v2/oauth/token/', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
    const result = await response.json();
    if (!response.ok || !result.access_token) throw new Error(result.error_description || 'TikTok token exchange failed');
    return { accessToken: result.access_token, refreshToken: result.refresh_token, expiresIn: result.expires_in, externalId: result.open_id };
  }
  if (platform === 'linkedin') {
    body.set('client_id', credentials.clientId); body.set('client_secret', credentials.clientSecret);
    const response = await fetch('https://www.linkedin.com/oauth/v2/accessToken', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
    const result = await response.json();
    if (!response.ok || !result.access_token) throw new Error(result.error_description || 'LinkedIn token exchange failed');
    return {
      accessToken: result.access_token,
      refreshToken: result.refresh_token,
      expiresIn: result.expires_in,
      grantedScopes: typeof result.scope === 'string' ? result.scope.split(/[\s,]+/).filter(Boolean) : undefined,
    };
  }
  body.set('client_id', credentials.clientId); body.set('client_secret', credentials.clientSecret);
  const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  const result = await response.json();
  if (!response.ok || !result.access_token) throw new Error(result.error_description || 'YouTube token exchange failed');
  return { accessToken: result.access_token, refreshToken: result.refresh_token, expiresIn: result.expires_in };
}

async function fetchAccounts(platform: SocialPlatform, token: TokenResult): Promise<AccountResult[]> {
  if (platform === 'facebook') {
    const response = await fetch(`https://graph.facebook.com/${metaApiVersion()}/me/accounts?fields=id,name,picture,access_token,tasks&limit=100`, { headers: { Authorization: `Bearer ${token.accessToken}` } });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error?.message || 'Unable to load Facebook Pages');
    const pages = (data.data || []).filter(facebookPageHasPostingAccess).map((page: any) => ({ id: String(page.id), name: page.name || 'Facebook Page', avatar: page.picture?.data?.url, accessToken: page.access_token, metadata: { tasks: page.tasks || [] } }));
    if (!pages.length) throw new Error('No Facebook Pages with posting access are available for this account');
    return pages;
  }
  if (platform === 'instagram') {
    const url = new URL('https://graph.instagram.com/me');
    url.searchParams.set('fields', 'id,username,account_type,profile_picture_url'); url.searchParams.set('access_token', token.accessToken);
    const response = await fetch(url); const data = await response.json();
    if (!response.ok || !data.id) throw new Error(data.error?.message || 'Unable to load Instagram account');
    return [{ id: String(data.id), name: data.username || 'Instagram', avatar: data.profile_picture_url, metadata: { accountType: data.account_type } }];
  }
  if (platform === 'tiktok') {
    const response = await fetch('https://open.tiktokapis.com/v2/user/info/?fields=open_id,union_id,avatar_url,display_name', { headers: { Authorization: `Bearer ${token.accessToken}` } });
    const data = await response.json(); const user = data.data?.user;
    if (!response.ok || !user?.open_id) throw new Error(data.error?.message || 'Unable to load TikTok account');
    return [{ id: user.open_id, name: user.display_name || 'TikTok', avatar: user.avatar_url, metadata: { unionId: user.union_id } }];
  }
  if (platform === 'linkedin') {
    const response = await fetch('https://api.linkedin.com/v2/userinfo', { headers: { Authorization: `Bearer ${token.accessToken}` } });
    const data = await response.json();
    if (!response.ok || !data.sub) throw new Error(data.message || 'Unable to load LinkedIn profile');
    const accounts: AccountResult[] = [{ id: String(data.sub), name: data.name || `${data.given_name || ''} ${data.family_name || ''}`.trim() || 'LinkedIn profile', avatar: data.picture, metadata: { accountType: 'person', authorUrn: `urn:li:person:${data.sub}`, email: data.email || null } }];
    if (linkedinOrganizationScopesEnabled()) {
      const headers = { Authorization: `Bearer ${token.accessToken}`, 'LinkedIn-Version': process.env.LINKEDIN_API_VERSION || '202601', 'X-Restli-Protocol-Version': '2.0.0' };
      const roleResponses = await Promise.all(LINKEDIN_PAGE_POSTING_ROLES.map(async (role) => {
        const url = new URL('https://api.linkedin.com/rest/organizationAcls');
        url.searchParams.set('q', 'roleAssignee');
        url.searchParams.set('role', role);
        url.searchParams.set('state', 'APPROVED');
        const response = await fetch(url, { headers });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.message || `Unable to confirm LinkedIn ${role} Page access`);
        return payload.elements || [];
      }));
      const pageRoles = new Map<string, string>();
      for (const acl of roleResponses.flat()) {
        if (isLinkedInPagePostingRole(acl.role)) pageRoles.set(String(acl.organization || ''), acl.role);
      }
      for (const [organizationUrn, pageRole] of pageRoles) {
        const organizationId = organizationUrn.split(':').at(-1);
        if (!organizationId) continue;
        const organizationResponse = await fetch(`https://api.linkedin.com/rest/organizations/${encodeURIComponent(organizationId)}`, { headers });
        const organization = await organizationResponse.json();
        if (!organizationResponse.ok) throw new Error(organization.message || 'Unable to load an approved LinkedIn Page');
        accounts.push({ id: organizationId, name: organization.localizedName || organization.vanityName || 'LinkedIn Page', avatar: undefined, metadata: { accountType: 'organization', authorUrn: organizationUrn, pageRole, pageRoleVerifiedAt: new Date().toISOString() } });
      }
    }
    return accounts;
  }
  const response = await fetch('https://www.googleapis.com/youtube/v3/channels?part=id,snippet&mine=true', { headers: { Authorization: `Bearer ${token.accessToken}` } });
  const data = await response.json(); const channel = data.items?.[0];
  if (!response.ok || !channel?.id) throw new Error(data.error?.message || 'No YouTube channel was found');
  return [{ id: channel.id, name: channel.snippet?.title || 'YouTube', avatar: channel.snippet?.thumbnails?.default?.url }];
}

async function subscribeMetaWebhooks(platform: SocialPlatform, account: AccountResult, token: TokenResult) {
  if (platform !== 'facebook' && platform !== 'instagram') return { subscribed: false, error: null as string | null };
  const accountToken = account.accessToken || token.accessToken;
  const host = platform === 'instagram' ? 'graph.instagram.com' : 'graph.facebook.com';
  const fields = (platform === 'instagram' ? INSTAGRAM_WEBHOOK_FIELDS : FACEBOOK_PAGE_WEBHOOK_FIELDS).join(',');
  const body = new URLSearchParams({ access_token: accountToken, subscribed_fields: fields });
  const response = await fetch(`https://${host}/${metaApiVersion()}/${encodeURIComponent(account.id)}/subscribed_apps`, { method: 'POST', body });
  const payload = await response.json();
  return response.ok && payload.success === true
    ? { subscribed: true, error: null as string | null }
    : { subscribed: false, error: payload.error?.message || 'Meta webhook subscription is unavailable' };
}

export async function GET(request: NextRequest, { params }: { params: Promise<{ platform: string }> }) {
  const { platform: rawPlatform } = await params;
  if (!isSocialPlatform(rawPlatform)) return NextResponse.json({ error: 'Unsupported platform' }, { status: 404 });
  const admin = createAdminClient();
  let returnTo = `${socialOrigin(request.url)}/app?section=connections`;
  let destination: URL;
  try {
    const state = request.nextUrl.searchParams.get('state');
    if (!state) throw new Error('OAuth session expired or was invalid');
    const { data: oauthState } = await admin.from('social_oauth_states').select('*').eq('state_hash', stateHash(state)).eq('platform', rawPlatform).is('consumed_at', null).gt('expires_at', new Date().toISOString()).maybeSingle();
    if (!oauthState) throw new Error('OAuth session expired, was replayed, or was invalid');
    returnTo = oauthState.return_to || returnTo;
    const providerError = request.nextUrl.searchParams.get('error_description') || request.nextUrl.searchParams.get('error');
    if (providerError) throw new Error(providerError);
    const code = request.nextUrl.searchParams.get('code');
    if (!code) throw new Error('Provider did not return an authorization code');
    const { data: consumed } = await admin.from('social_oauth_states').update({ consumed_at: new Date().toISOString() }).eq('state_hash', oauthState.state_hash).is('consumed_at', null).select('state_hash').maybeSingle();
    if (!consumed) throw new Error('OAuth session was already used');
    const token = await exchangeCode(rawPlatform, code, request.url);
    const accounts = await fetchAccounts(rawPlatform, token);
    for (const account of accounts) {
      const webhook = await subscribeMetaWebhooks(rawPlatform, account, token);
      const { error } = await admin.from('social_connections').upsert({
        social_workspace_id: oauthState.social_workspace_id,
        user_id: oauthState.user_id,
        salesperson_id: null,
        platform: rawPlatform,
        external_account_id: account.id,
        account_name: account.name,
        account_avatar_url: account.avatar || null,
        access_token_encrypted: encryptSocialToken(account.accessToken || token.accessToken),
        refresh_token_encrypted: token.refreshToken ? encryptSocialToken(token.refreshToken) : null,
        scopes: token.grantedScopes || (rawPlatform === 'linkedin' ? linkedinOAuthScopes() : PLATFORM_SCOPES[rawPlatform]),
        token_expires_at: rawPlatform === 'facebook' && account.accessToken ? null : token.expiresIn ? new Date(Date.now() + token.expiresIn * 1000).toISOString() : null,
        status: 'active', metadata: { ...(account.metadata || {}), webhookSubscribed: webhook.subscribed, webhookError: webhook.error }, last_error: webhook.error, updated_at: new Date().toISOString(),
      }, { onConflict: 'social_workspace_id,platform,external_account_id' });
      if (error) throw error;
    }
    destination = new URL(returnTo);
    destination.searchParams.set('connected', rawPlatform);
    destination.searchParams.set('accounts', String(accounts.length));
    destination.searchParams.set('status', 'success');
  } catch (error) {
    console.error(`[social/oauth/${rawPlatform}/callback]`, error);
    destination = new URL(returnTo);
    destination.searchParams.set('platform', rawPlatform);
    destination.searchParams.set('status', 'error');
    destination.searchParams.set('error', error instanceof Error ? error.message : 'Connection failed');
  }
  return NextResponse.redirect(destination);
}
