-- Private contact photos for the WolfGrid Sales app.
-- Objects are stored as: <auth.uid()>/<sales_lead_id>.jpg

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'contact-photos',
  'contact-photos',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "users upload their contact photos" ON storage.objects;
CREATE POLICY "users upload their contact photos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'contact-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "users read their contact photos" ON storage.objects;
CREATE POLICY "users read their contact photos"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'contact-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "users update their contact photos" ON storage.objects;
CREATE POLICY "users update their contact photos"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'contact-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'contact-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "users delete their contact photos" ON storage.objects;
CREATE POLICY "users delete their contact photos"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'contact-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
