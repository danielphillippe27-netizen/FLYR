-- Restore the conflict target used by Telnyx SMS/MMS webhook upserts.
-- Some existing environments have the table without the indexes from the
-- original dialer_messages migration.

CREATE UNIQUE INDEX IF NOT EXISTS idx_dialer_messages_provider_message_id
  ON public.dialer_messages(provider, provider_message_id);

NOTIFY pgrst, 'reload schema';
