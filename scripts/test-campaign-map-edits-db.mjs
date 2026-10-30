import { readFile } from "node:fs/promises";
const { PGlite } = await import(process.env.WOLFGRID_TEST_PGLITE ?? "@electric-sql/pglite");
const root = new URL("../", import.meta.url);
const db = new PGlite();
try {
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    CREATE TABLE public.campaigns(id uuid PRIMARY KEY);
    CREATE TABLE public.campaign_addresses(id text PRIMARY KEY, campaign_id uuid, postal_code text);
    CREATE TABLE public.contacts(id text PRIMARY KEY, address_id text REFERENCES public.campaign_addresses(id));
    CREATE TABLE public.visits(id text PRIMARY KEY, address_id text REFERENCES public.campaign_addresses(id));
    INSERT INTO public.campaign_addresses VALUES('home','00000000-0000-0000-0000-000000000001','L1A 1A1');
    INSERT INTO public.contacts VALUES('contact','home'); INSERT INTO public.visits VALUES('visit','home');`);
  await db.exec(await readFile(new URL("supabase/migrations/20261028180000_campaign_map_edit_overlays.sql", root), "utf8"));
  const tests = (await readFile(new URL("supabase/tests/campaign_map_edit_overlays.sql", root), "utf8")).replace(/^\\set .*$/gm, "");
  await db.exec(tests);
  const { rows } = await db.query(`SELECT
    (SELECT count(*) FROM campaign_addresses) AS addresses,
    (SELECT count(*) FROM contacts) AS contacts,
    (SELECT count(*) FROM visits) AS visits,
    (SELECT postal_code FROM campaign_addresses WHERE id='home') AS postal_code`);
  if (Number(rows[0].addresses) !== 1 || Number(rows[0].contacts) !== 1 || Number(rows[0].visits) !== 1 || rows[0].postal_code !== "L1A 1A1") throw new Error("Source data was changed");
  console.log("PASS: transactional batches, rollback, idempotent retry, undo, revision conflicts, campaign isolation, permissions, address/contact/visit preservation.");
} finally { await db.close(); }
