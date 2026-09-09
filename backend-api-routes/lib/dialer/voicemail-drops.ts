import type { DialerVoicemailDrop } from '@/types/database';
import type { createAdminClient } from '@/lib/supabase/server';

/** Authorize both the row and object path before minting a short-lived playback URL. */
export async function signPersonalVoicemailDrop(
  admin: ReturnType<typeof createAdminClient>,
  recording: DialerVoicemailDrop,
  workspaceId: string,
  userId: string
): Promise<DialerVoicemailDrop> {
  if (recording.workspace_id !== workspaceId || recording.user_id !== userId ||
      recording.storage_bucket !== 'dialer-voicemail-drops' ||
      !recording.storage_path.startsWith(`${workspaceId}/${userId}/`)) {
    throw new Error('Voicemail recording ownership could not be verified.');
  }
  const { data, error } = await admin.storage.from(recording.storage_bucket)
    .createSignedUrl(recording.storage_path, 900);
  if (error || !data?.signedUrl) throw new Error('Unable to authorize voicemail playback.');
  return { ...recording, public_url: data.signedUrl };
}
