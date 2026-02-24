-- Make campaign type optional so iOS can create campaigns without selecting a type.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'campaigns'
          AND column_name = 'type'
    ) THEN
        ALTER TABLE public.campaigns
            ALTER COLUMN type DROP NOT NULL;
    END IF;
END $$;

COMMENT ON COLUMN public.campaigns.type IS 'Optional campaign type (flyer, door_knock, etc.). Nullable for simplified campaign creation.';
