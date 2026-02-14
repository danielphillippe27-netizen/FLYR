-- =====================================================
-- Add address_id FK to contacts table
-- 
-- Adds foreign key to campaign_addresses for better
-- contact-to-address linking. Keeps existing address
-- text field for backward compatibility.
-- =====================================================

-- Add address_id column if it doesn't exist
ALTER TABLE public.contacts 
ADD COLUMN IF NOT EXISTS address_id UUID REFERENCES public.campaign_addresses(id) ON DELETE SET NULL;

-- Create index for fast FK lookups
CREATE INDEX IF NOT EXISTS idx_contacts_address_id 
    ON public.contacts(address_id) 
    WHERE address_id IS NOT NULL;

-- Add comment
COMMENT ON COLUMN public.contacts.address_id IS 'FK to campaign_addresses.id - preferred linking method. NULL for legacy contacts that use text address field.';
COMMENT ON COLUMN public.contacts.address IS 'Text address field - fallback for legacy data. New contacts should use address_id FK.';

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
