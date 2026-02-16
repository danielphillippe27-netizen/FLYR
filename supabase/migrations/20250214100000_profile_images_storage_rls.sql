-- Profile images storage bucket and RLS
-- Fixes 403 "new row violates row-level security policy" when uploading profile photos.
-- App uploads to path: profile_<user_id>.jpg in bucket profile_images.

-- ============================================================================
-- 1. Create profile_images bucket (if not exists)
-- ============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'profile_images',
  'profile_images',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 2. RLS policies on storage.objects for profile_images
-- Users may only upload/read/update/delete their own file: profile_<auth.uid()>.jpg
-- Use lower() so iOS uuidString (uppercase) matches Postgres auth.uid()::text (lowercase).
-- ============================================================================

-- Allow authenticated users to INSERT only their own profile image path
DROP POLICY IF EXISTS "profile_images_insert_own" ON storage.objects;
CREATE POLICY "profile_images_insert_own"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile_images'
  AND lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
);

-- Allow users to SELECT (read) their own profile image
DROP POLICY IF EXISTS "profile_images_select_own" ON storage.objects;
CREATE POLICY "profile_images_select_own"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg' OR owner_id = auth.uid()::text)
);

-- Allow users to UPDATE their own profile image (required for upsert)
DROP POLICY IF EXISTS "profile_images_update_own" ON storage.objects;
CREATE POLICY "profile_images_update_own"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg' OR owner_id = auth.uid()::text)
)
WITH CHECK (
  bucket_id = 'profile_images'
  AND (lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg' OR owner_id = auth.uid()::text)
);

-- Allow users to DELETE their own profile image
DROP POLICY IF EXISTS "profile_images_delete_own" ON storage.objects;
CREATE POLICY "profile_images_delete_own"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg' OR owner_id = auth.uid()::text)
);
