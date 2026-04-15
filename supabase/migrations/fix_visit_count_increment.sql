-- Fix visit_count race condition in address_statuses
-- Replaces client-side read-modify-write with atomic server-side increment

CREATE OR REPLACE FUNCTION upsert_address_status(
  p_address_id UUID,
  p_campaign_id UUID,
  p_status TEXT,
  p_notes TEXT,
  p_last_visited_at TIMESTAMPTZ
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO address_statuses (
    address_id,
    campaign_id,
    status,
    notes,
    last_visited_at,
    visit_count
  ) VALUES (
    p_address_id,
    p_campaign_id,
    p_status,
    p_notes,
    p_last_visited_at,
    1
  )
  ON CONFLICT (address_id, campaign_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    notes = EXCLUDED.notes,
    last_visited_at = EXCLUDED.last_visited_at,
    visit_count = address_statuses.visit_count + 1;
END;
$$;
