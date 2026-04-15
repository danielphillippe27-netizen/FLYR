-- Allow challenge cover uploads in the existing profile_images bucket.
-- The iOS app stores optional challenge covers at:
--   <auth.uid()>/challenge_<uuid>.jpg
-- Existing storage RLS only allowed:
--   profile_<auth.uid()>.jpg
-- which caused 403 "new row violates row-level security policy" on upload.

DROP POLICY IF EXISTS "profile_images_insert_own" ON storage.objects;
CREATE POLICY "profile_images_insert_own"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile_images'
  AND (
    lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
    OR lower(name) LIKE lower(auth.uid()::text) || '/challenge_%'
  )
);

DROP POLICY IF EXISTS "profile_images_select_own" ON storage.objects;
CREATE POLICY "profile_images_select_own"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (
    lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
    OR owner_id = auth.uid()::text
    OR EXISTS (
      SELECT 1
      FROM public.challenges c
      WHERE COALESCE(to_jsonb(c) ->> 'cover_image_path', '') = storage.objects.name
        AND (
          c.creator_id = auth.uid()
          OR c.participant_id = auth.uid()
          OR (
            COALESCE(to_jsonb(c) ->> 'visibility', 'private') = 'searchable'
            AND c.participant_id IS NULL
          )
        )
    )
  )
);

DROP POLICY IF EXISTS "profile_images_update_own" ON storage.objects;
CREATE POLICY "profile_images_update_own"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (
    lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
    OR lower(name) LIKE lower(auth.uid()::text) || '/challenge_%'
    OR owner_id = auth.uid()::text
  )
)
WITH CHECK (
  bucket_id = 'profile_images'
  AND (
    lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
    OR lower(name) LIKE lower(auth.uid()::text) || '/challenge_%'
    OR owner_id = auth.uid()::text
  )
);

DROP POLICY IF EXISTS "profile_images_delete_own" ON storage.objects;
CREATE POLICY "profile_images_delete_own"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (
    lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
    OR lower(name) LIKE lower(auth.uid()::text) || '/challenge_%'
    OR owner_id = auth.uid()::text
  )
);
