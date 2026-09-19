type DatabaseError = { code?: string; details?: string };

/** Return only the safe shared history fields, never raw database diagnostics. */
export function duplicateCallConflict(error: DatabaseError | null, currentUserId: string) {
  if (error?.code !== 'PDC01') return null;
  let detail: Record<string, unknown> = {};
  try { detail = JSON.parse(error.details ?? '{}') ?? {}; } catch { /* Use generic message. */ }
  const by = detail.last_called_by_user_id === currentUserId ? 'You'
    : typeof detail.last_called_by === 'string' ? detail.last_called_by.slice(0, 100) : 'A teammate';
  const at = typeof detail.last_called_at === 'string' && Number.isFinite(Date.parse(detail.last_called_at))
    ? detail.last_called_at : null;
  return {
    code: 'duplicate_call',
    error: `${by} already attempted this number${at ? ` at ${new Date(at).toLocaleString('en-CA', { timeZone: 'UTC' })} UTC` : ' recently'}. Wait 24 hours before calling again.`,
    last_called_at: at,
    last_called_by: by,
    retry_after: typeof detail.retry_after === 'string' ? detail.retry_after : null,
  };
}
