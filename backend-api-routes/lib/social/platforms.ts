export const SOCIAL_PLATFORMS = ['facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'] as const;
export type SocialPlatform = (typeof SOCIAL_PLATFORMS)[number];

export function isSocialPlatform(value: string): value is SocialPlatform {
  return SOCIAL_PLATFORMS.includes(value as SocialPlatform);
}

export function metaApiVersion(): string {
  const value = process.env.META_API_VERSION || 'v25.0';
  return /^v\d+\.\d+$/.test(value) ? value : 'v25.0';
}

export const PLATFORM_SCOPES: Record<SocialPlatform, string[]> = {
  facebook: [
    'pages_show_list',
    'pages_read_engagement',
    'pages_manage_posts',
    'pages_manage_engagement',
    'pages_manage_metadata',
    'pages_messaging',
  ],
  instagram: [
    'instagram_business_basic',
    'instagram_business_content_publish',
    'instagram_business_manage_comments',
    'instagram_business_manage_messages',
  ],
  tiktok: ['user.info.basic', 'video.publish'],
  youtube: [
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/youtube.upload',
    'https://www.googleapis.com/auth/youtube.force-ssl',
  ],
  linkedin: ['openid', 'profile', 'email', 'w_member_social'],
};

export const LINKEDIN_ORGANIZATION_SCOPES = [
  'rw_organization_admin',
  'r_organization_social',
  'w_organization_social',
] as const;

export const LINKEDIN_PAGE_POSTING_ROLES = ['ADMINISTRATOR', 'CONTENT_ADMIN'] as const;

export function linkedinOrganizationScopesEnabled(): boolean {
  return process.env.LINKEDIN_ORGANIZATION_SCOPES?.trim().toLowerCase() === 'true';
}

export function linkedinOAuthScopes(): string[] {
  return linkedinOrganizationScopesEnabled()
    ? [...PLATFORM_SCOPES.linkedin, ...LINKEDIN_ORGANIZATION_SCOPES]
    : [...PLATFORM_SCOPES.linkedin];
}

export function isLinkedInPagePostingRole(value: unknown): value is (typeof LINKEDIN_PAGE_POSTING_ROLES)[number] {
  return typeof value === 'string' && LINKEDIN_PAGE_POSTING_ROLES.includes(value as (typeof LINKEDIN_PAGE_POSTING_ROLES)[number]);
}

export function platformCredentials(platform: SocialPlatform) {
  if (platform === 'facebook') {
    return { clientId: process.env.META_APP_ID, clientSecret: process.env.META_APP_SECRET };
  }
  if (platform === 'instagram') {
    return { clientId: process.env.INSTAGRAM_CLIENT_ID || process.env.META_APP_ID, clientSecret: process.env.INSTAGRAM_CLIENT_SECRET || process.env.META_APP_SECRET };
  }
  if (platform === 'tiktok') {
    return { clientId: process.env.TIKTOK_CLIENT_KEY, clientSecret: process.env.TIKTOK_CLIENT_SECRET };
  }
  if (platform === 'linkedin') {
    return { clientId: process.env.LINKEDIN_CLIENT_ID, clientSecret: process.env.LINKEDIN_CLIENT_SECRET };
  }
  return { clientId: process.env.YOUTUBE_CLIENT_ID || process.env.GOOGLE_CLIENT_ID, clientSecret: process.env.YOUTUBE_CLIENT_SECRET || process.env.GOOGLE_CLIENT_SECRET };
}

export function socialOrigin(requestUrl: string): string {
  if (process.env.NEXT_PUBLIC_SOCIAL_APP_URL) return process.env.NEXT_PUBLIC_SOCIAL_APP_URL.replace(/\/$/, '');
  if (process.env.NEXT_PUBLIC_SALES_APP_URL) return process.env.NEXT_PUBLIC_SALES_APP_URL.replace(/\/$/, '');
  return new URL(requestUrl).origin;
}

export function oauthCallbackUrl(platform: SocialPlatform, requestUrl: string): string {
  return `${socialOrigin(requestUrl)}/api/social/oauth/${platform}/callback`;
}
