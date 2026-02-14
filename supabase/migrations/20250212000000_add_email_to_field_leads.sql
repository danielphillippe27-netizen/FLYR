-- Add email column to field_leads (used by iOS location card and LeadCaptureSheet)
ALTER TABLE public.field_leads
ADD COLUMN IF NOT EXISTS email TEXT;

COMMENT ON COLUMN public.field_leads.email IS 'Contact email captured at the door';

NOTIFY pgrst, 'reload schema';
