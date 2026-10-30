-- Run against an isolated fixture database after the migration.
\set ON_ERROR_STOP on
INSERT INTO public.campaigns(id) VALUES ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
DO $$
DECLARE r jsonb; revision_before bigint;
BEGIN
  r := public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000100',0,
    '[{"kind":"building","id":"roof","value":{"hidden":true}},{"kind":"address","id":"home","value":{"buildingLinkSet":true,"parcelLinkSet":true,"parcelId":"lot"}}]');
  IF r->>'revision' <> '1' OR r#>>'{features,building:roof,hidden}' <> 'true' OR r#>>'{features,address:home,parcelId}' <> 'lot' THEN RAISE EXCEPTION 'Batch did not apply'; END IF;
  r := public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000100',0,
    '[{"kind":"building","id":"roof","value":{"hidden":true}},{"kind":"address","id":"home","value":{"buildingLinkSet":true,"parcelLinkSet":true,"parcelId":"lot"}}]');
  IF r->>'revision' <> '1' THEN RAISE EXCEPTION 'Retry was not idempotent'; END IF;
  BEGIN
    PERFORM public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000100',0,
      '[{"kind":"building","id":"roof","value":{"hidden":true}}]');
    RAISE EXCEPTION 'Identity reuse was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  r := public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000101',0,
    '[{"kind":"parcel","id":"lot","value":{"hidden":true}}]');
  IF r->>'conflict' <> 'true' OR r->>'revision' <> '1' THEN RAISE EXCEPTION 'Stale revision was not rejected'; END IF;
  IF EXISTS(SELECT FROM public.campaign_map_edit_mutations WHERE mutation_id='00000000-0000-0000-0000-000000000101') THEN RAISE EXCEPTION 'Conflict mutated audit'; END IF;
  BEGIN
    PERFORM public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000102',1,
      '[{"kind":"parcel","id":"lot","value":{"hidden":true}},{"kind":"invalid","id":"bad","value":{}}]');
    RAISE EXCEPTION 'Invalid batch accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF EXISTS(SELECT FROM public.campaign_map_edit_states WHERE campaign_id='00000000-0000-0000-0000-000000000001' AND features ? 'parcel:lot') THEN RAISE EXCEPTION 'Partial batch escaped transaction'; END IF;
  r := public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000103',1,
    '[{"kind":"building","id":"roof","value":null},{"kind":"address","id":"home","value":null}]');
  IF r->>'revision' <> '2' OR r->'features' <> '{}'::jsonb THEN RAISE EXCEPTION 'Undo did not restore empty overlay'; END IF;
  r := public.apply_campaign_map_edits('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000100',0,
    '[{"kind":"parcel","id":"lot","value":{"hidden":true}}]');
  IF r->>'revision' <> '1' THEN RAISE EXCEPTION 'Campaigns share revision'; END IF;
  IF has_function_privilege('authenticated','public.apply_campaign_map_edits(uuid,uuid,uuid,bigint,jsonb)','execute') THEN RAISE EXCEPTION 'Client can bypass API authorization'; END IF;
  IF has_table_privilege('authenticated','public.campaign_map_edit_states','select') THEN RAISE EXCEPTION 'Client can read other campaign states'; END IF;
END $$;
