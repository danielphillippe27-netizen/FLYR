BEGIN;
ALTER TABLE public.dialer_voicemail_drops ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_voicemail_drop_owner ON public.dialer_voicemail_drops
AS RESTRICTIVE FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (
  user_id = auth.uid() AND storage_bucket = 'dialer-voicemail-drops'
  AND storage_path LIKE workspace_id::text || '/' || auth.uid()::text || '/%'
);

-- Old public URLs must stop granting unauthenticated access. The API signs
-- playback only after checking row ownership and the workspace/user object path.
UPDATE storage.buckets SET public = false WHERE id = 'dialer-voicemail-drops';
DROP POLICY IF EXISTS "Public read dialer voicemail drops" ON storage.objects;
CREATE POLICY personal_voicemail_storage_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'dialer-voicemail-drops'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (SELECT 1 FROM public.workspace_members wm
    WHERE wm.workspace_id::text = (storage.foldername(name))[1] AND wm.user_id = auth.uid()));
CREATE POLICY personal_voicemail_storage_boundary ON storage.objects
AS RESTRICTIVE FOR ALL TO public
USING (bucket_id <> 'dialer-voicemail-drops' OR (
  (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (SELECT 1 FROM public.workspace_members wm
    WHERE wm.workspace_id::text = (storage.foldername(name))[1] AND wm.user_id = auth.uid())))
WITH CHECK (bucket_id <> 'dialer-voicemail-drops' OR (
  (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (SELECT 1 FROM public.workspace_members wm
    WHERE wm.workspace_id::text = (storage.foldername(name))[1] AND wm.user_id = auth.uid())));
COMMIT;
