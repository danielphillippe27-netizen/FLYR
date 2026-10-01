-- A campaign member can see the map appearance that another member chose.
CREATE TABLE IF NOT EXISTS public.wolfy_map_styles (
    workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    appearance jsonb NOT NULL DEFAULT '{"fur":"classic","eyes":"amber","nose":"black"}'::jsonb,
    equipment jsonb NOT NULL DEFAULT '{}'::jsonb,
    growth_stage integer NOT NULL DEFAULT 1 CHECK (growth_stage BETWEEN 1 AND 5),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, user_id)
);

ALTER TABLE public.wolfy_map_styles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wolfy_map_styles FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.wolfy_publish_map_style(
    p_workspace uuid, p_appearance jsonb, p_equipment jsonb, p_growth_stage integer
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.workspace_members
        WHERE workspace_id = p_workspace AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Not a workspace member' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_appearance) <> 'object'
       OR jsonb_typeof(p_equipment) <> 'object'
       OR length(p_appearance::text) > 1024
       OR length(p_equipment::text) > 4096
       OR p_growth_stage NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION 'Invalid Wolfy map style' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.wolfy_map_styles (workspace_id, user_id, appearance, equipment, growth_stage)
    VALUES (p_workspace, auth.uid(), p_appearance, p_equipment, p_growth_stage)
    ON CONFLICT (workspace_id, user_id) DO UPDATE SET
        appearance = EXCLUDED.appearance,
        equipment = EXCLUDED.equipment,
        growth_stage = EXCLUDED.growth_stage,
        updated_at = now();
END $$;

CREATE OR REPLACE FUNCTION public.wolfy_campaign_map_styles(p_campaign uuid)
RETURNS TABLE (user_id uuid, display_name text, appearance jsonb, equipment jsonb, growth_stage integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT cm.user_id,
           COALESCE(NULLIF(trim(p.nickname), ''), NULLIF(trim(p.full_name), ''),
                    NULLIF(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    NULLIF(trim(a.raw_user_meta_data->>'full_name'), ''),
                    NULLIF(trim(a.raw_user_meta_data->>'name'), ''),
                    NULLIF(split_part(coalesce(p.email, a.email), '@', 1), ''),
                    left(cm.user_id::text, 8)),
           s.appearance, s.equipment, s.growth_stage
    FROM public.campaign_members cm
    JOIN public.campaigns c ON c.id = cm.campaign_id
    LEFT JOIN public.profiles p ON p.id = cm.user_id
    LEFT JOIN auth.users a ON a.id = cm.user_id
    LEFT JOIN public.wolfy_map_styles s ON s.workspace_id = c.workspace_id AND s.user_id = cm.user_id
    WHERE cm.campaign_id = p_campaign AND public.is_campaign_member(p_campaign);
$$;

REVOKE ALL ON FUNCTION public.wolfy_publish_map_style(uuid,jsonb,jsonb,integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wolfy_campaign_map_styles(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wolfy_publish_map_style(uuid,jsonb,jsonb,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wolfy_campaign_map_styles(uuid) TO authenticated;
