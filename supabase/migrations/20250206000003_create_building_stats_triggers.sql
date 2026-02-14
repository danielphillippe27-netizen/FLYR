-- =====================================================
-- Building Stats Triggers
-- 
-- Creates triggers to automatically update building_stats
-- when QR codes are scanned or visits are logged.
-- =====================================================

-- =====================================================
-- 1. Trigger function for QR code scans
-- =====================================================

CREATE OR REPLACE FUNCTION update_building_stats_on_scan()
RETURNS TRIGGER AS $$
BEGIN
    -- Update building_stats when a QR code scan is recorded
    -- Find the building via building_address_links and update its stats
    INSERT INTO public.building_stats (building_id, campaign_id, gers_id, status, scans_total, scans_today, last_scan_at)
    SELECT 
        b.id, 
        NEW.campaign_id, 
        b.gers_id,
        'visited',
        1,
        1,
        NEW.scanned_at
    FROM public.buildings b
    JOIN public.building_address_links l ON b.id = l.building_id
    WHERE l.address_id = NEW.address_id
        AND l.campaign_id = NEW.campaign_id
        AND l.is_primary = true
    ON CONFLICT (building_id) DO UPDATE SET
        scans_total = public.building_stats.scans_total + 1,
        scans_today = CASE 
            WHEN DATE(public.building_stats.last_scan_at) = CURRENT_DATE 
            THEN public.building_stats.scans_today + 1 
            ELSE 1 
        END,
        last_scan_at = NEW.scanned_at,
        status = 'visited',
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on qr_code_scans table
-- Only create if qr_code_scans table exists
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'qr_code_scans') THEN
        DROP TRIGGER IF EXISTS trg_update_building_stats_on_scan ON public.qr_code_scans;
        
        CREATE TRIGGER trg_update_building_stats_on_scan
        AFTER INSERT ON public.qr_code_scans
        FOR EACH ROW
        EXECUTE FUNCTION update_building_stats_on_scan();
    END IF;
END $$;

-- =====================================================
-- 2. Trigger function for visit logs (building touches)
-- =====================================================

CREATE OR REPLACE FUNCTION update_building_stats_on_touch()
RETURNS TRIGGER AS $$
BEGIN
    -- Update building_stats when a building touch/visit is logged
    INSERT INTO public.building_stats (building_id, campaign_id, gers_id, status, scans_total, scans_today, last_scan_at)
    SELECT 
        NEW.building_id,
        NEW.campaign_id,
        b.gers_id,
        'visited',
        0,
        0,
        NULL
    FROM public.buildings b
    WHERE b.id = NEW.building_id
    ON CONFLICT (building_id) DO UPDATE SET
        status = CASE 
            WHEN public.building_stats.status = 'not_visited' THEN 'visited'
            ELSE public.building_stats.status
        END,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on building_touches table if it exists
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'building_touches') THEN
        DROP TRIGGER IF EXISTS trg_update_building_stats_on_touch ON public.building_touches;
        
        CREATE TRIGGER trg_update_building_stats_on_touch
        AFTER INSERT ON public.building_touches
        FOR EACH ROW
        EXECUTE FUNCTION update_building_stats_on_touch();
    END IF;
END $$;

-- =====================================================
-- 3. Function to reset daily scan counts
-- =====================================================

CREATE OR REPLACE FUNCTION reset_daily_building_scan_counts()
RETURNS void AS $$
BEGIN
    -- Reset scans_today to 0 for all buildings
    UPDATE public.building_stats
    SET scans_today = 0,
        updated_at = NOW()
    WHERE scans_today > 0;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION reset_daily_building_scan_counts IS 'Resets scans_today counter for all buildings. Should be run daily via cron.';

-- =====================================================
-- 4. Function to manually update building status
-- =====================================================

CREATE OR REPLACE FUNCTION set_building_status(
    p_building_id UUID,
    p_status TEXT
)
RETURNS void AS $$
BEGIN
    -- Validate status
    IF p_status NOT IN ('not_visited', 'visited', 'hot') THEN
        RAISE EXCEPTION 'Invalid status: %. Must be one of: not_visited, visited, hot', p_status;
    END IF;
    
    -- Update building stats
    INSERT INTO public.building_stats (building_id, status)
    VALUES (p_building_id, p_status)
    ON CONFLICT (building_id) DO UPDATE SET
        status = p_status,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION set_building_status(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION set_building_status IS 'Manually set the status of a building (not_visited, visited, hot)';

-- =====================================================
-- 5. Add comments
-- =====================================================

COMMENT ON FUNCTION update_building_stats_on_scan IS 'Automatically updates building_stats when a QR code is scanned. Increments scan counts and updates last_scan_at timestamp.';
COMMENT ON FUNCTION update_building_stats_on_touch IS 'Automatically updates building_stats when a building visit is logged. Updates status from not_visited to visited.';

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
