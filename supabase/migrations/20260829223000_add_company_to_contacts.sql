ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS company text;

COMMENT ON COLUMN public.contacts.company IS
  'Optional company or organization name for the contact.';
