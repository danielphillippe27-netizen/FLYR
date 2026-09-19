ALTER TABLE public.email_connections
  ADD COLUMN IF NOT EXISTS authentication_email_address text;

UPDATE public.email_connections
SET authentication_email_address = CASE
  WHEN lower(email_address) = 'daniel@wolfgrid.app' THEN 'daniel_phillippe@icloud.com'
  ELSE email_address
END
WHERE authentication_email_address IS NULL;

ALTER TABLE public.email_connections
  ALTER COLUMN authentication_email_address SET NOT NULL;
