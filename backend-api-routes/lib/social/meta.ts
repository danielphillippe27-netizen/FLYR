export const FACEBOOK_PAGE_WEBHOOK_FIELDS = [
  'feed',
  'messages',
  'messaging_postbacks',
] as const;

export const INSTAGRAM_WEBHOOK_FIELDS = ['comments', 'messages'] as const;

const FACEBOOK_POSTING_TASKS = new Set([
  'CREATE_CONTENT',
  'MANAGE',
  'PROFILE_PLUS_CREATE_CONTENT',
  'PROFILE_PLUS_MANAGE',
  'PROFILE_PLUS_FULL_CONTROL',
]);

export function facebookPageHasPostingAccess(page: Record<string, unknown>): boolean {
  if (!page.id || !page.access_token || !Array.isArray(page.tasks)) return false;
  return page.tasks.some((task) => typeof task === 'string' && FACEBOOK_POSTING_TASKS.has(task));
}

export function isExpiredProviderAuthorization(error: unknown): boolean {
  if (error && typeof error === 'object') {
    const payload = error as { code?: unknown; error?: { code?: unknown; error_subcode?: unknown; message?: unknown }; message?: unknown };
    const code = Number(payload.error?.code ?? payload.code);
    if (code === 102 || code === 190) return true;
    const subcode = Number(payload.error?.error_subcode);
    if ([458, 459, 460, 463, 464, 467, 490].includes(subcode)) return true;
    if (typeof payload.error?.message === 'string') error = payload.error.message;
    else if (typeof payload.message === 'string') error = payload.message;
  }
  const message = error instanceof Error ? error.message : String(error || '');
  return /authorization expired|access token.*(?:expired|invalid)|error validating access token|session has expired|oauth access token/i.test(message);
}
