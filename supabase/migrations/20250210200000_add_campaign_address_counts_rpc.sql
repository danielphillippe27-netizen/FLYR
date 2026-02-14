-- RPC to return address count per campaign (for list view house count)
-- Returns one row per campaign that has at least one address; campaigns with 0 addresses are omitted (app treats missing as 0).

CREATE OR REPLACE FUNCTION public.get_campaign_address_counts()
RETURNS TABLE (campaign_id uuid, address_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT ca.campaign_id, count(*)::bigint
  FROM public.campaign_addresses ca
  GROUP BY ca.campaign_id;
$$;

COMMENT ON FUNCTION public.get_campaign_address_counts() IS 'Returns campaign_id and address count for each campaign. Used by iOS app to show house count in campaign list.';

GRANT EXECUTE ON FUNCTION public.get_campaign_address_counts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_campaign_address_counts() TO service_role;
