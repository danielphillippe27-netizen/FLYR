-- Create qr_sets table for organizing QR codes into printable sets
CREATE TABLE IF NOT EXISTS public.qr_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_addresses INTEGER DEFAULT 0,
    variant_count INTEGER DEFAULT 0,
    qr_code_ids UUID[] DEFAULT '{}'::UUID[],
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL
);

-- Indexes for qr_sets
CREATE INDEX IF NOT EXISTS idx_qr_sets_user_id ON public.qr_sets(user_id);
CREATE INDEX IF NOT EXISTS idx_qr_sets_campaign_id ON public.qr_sets(campaign_id);
CREATE INDEX IF NOT EXISTS idx_qr_sets_created_at ON public.qr_sets(created_at DESC);

-- Trigger for updated_at
CREATE TRIGGER update_qr_sets_updated_at
    BEFORE UPDATE ON public.qr_sets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS
ALTER TABLE public.qr_sets ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can only read/write their own QR sets
CREATE POLICY "Users can view their own QR sets"
    ON public.qr_sets
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own QR sets"
    ON public.qr_sets
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own QR sets"
    ON public.qr_sets
    FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own QR sets"
    ON public.qr_sets
    FOR DELETE
    USING (auth.uid() = user_id);

