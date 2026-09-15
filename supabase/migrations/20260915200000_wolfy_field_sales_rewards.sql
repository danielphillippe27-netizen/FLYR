-- Apply after Wolfy character and field_sales_v1. Keep each module's migration independent.
BEGIN;
CREATE TABLE public.wolfy_verified_sale_claims (
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
 contact_id uuid NOT NULL,
 sale_id uuid NOT NULL,
 rewarded_user_id uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(workspace_id,contact_id)
);
ALTER TABLE public.wolfy_verified_sale_claims ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.wolfy_verified_sale_reward() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE claimed uuid;
BEGIN
 IF NEW.status<>'verified' OR NEW.verified_by IS NULL OR NEW.verified_at IS NULL THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.status='verified' THEN RETURN NEW; END IF;
 INSERT INTO wolfy_verified_sale_claims(workspace_id,contact_id,sale_id,rewarded_user_id)
 VALUES(NEW.workspace_id,NEW.contact_id,NEW.id,NEW.rep_id)
 ON CONFLICT DO NOTHING RETURNING sale_id INTO claimed;
 IF claimed IS NOT NULL THEN PERFORM wolfy_award(NEW.workspace_id,NEW.rep_id,'verified_sale',NEW.contact_id::text); END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_verified_sale_reward AFTER INSERT OR UPDATE ON public.field_sales
FOR EACH ROW EXECUTE FUNCTION public.wolfy_verified_sale_reward();
COMMIT;
