CREATE TABLE IF NOT EXISTS public.salesperson_revenue_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    salesperson_id UUID NOT NULL REFERENCES public.salespeople(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    captured_at TIMESTAMPTZ NOT NULL,
    paid_teams INTEGER NOT NULL DEFAULT 0 CHECK (paid_teams >= 0),
    mrr_by_currency JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (salesperson_id, captured_at)
);

CREATE INDEX IF NOT EXISTS idx_salesperson_revenue_snapshots_lookup
    ON public.salesperson_revenue_snapshots (salesperson_id, captured_at DESC);

ALTER TABLE public.salesperson_revenue_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "salespeople read their revenue snapshots"
    ON public.salesperson_revenue_snapshots;
CREATE POLICY "salespeople read their revenue snapshots"
    ON public.salesperson_revenue_snapshots
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());
