// Disposable embedded PostgreSQL only. Install @electric-sql/pglite outside the
// repository and pass its absolute entry point in HIRING_TEST_PGLITE_MODULE.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const { PGlite } = await import(pathToFileURL(process.env.HIRING_TEST_PGLITE_MODULE).href);
const db = new PGlite();
try {
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
    CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
    INSERT INTO auth.users VALUES ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');`);
  await db.exec(await readFile(new URL('../migrations/20260915110000_hiring_leads.sql', import.meta.url), 'utf8'));
  const scalar = async (query, params = []) => Object.values((await db.query(query, params)).rows[0])[0];
  const user1 = '00000000-0000-0000-0000-000000000001';
  const user2 = '00000000-0000-0000-0000-000000000002';
  const posting = { fingerprint: 'a', provider: 'adzuna', external_id: '1', country: 'CA',
    company: 'Example', title: 'Sales', location: 'Toronto', category: 'Sales',
    url: 'https://example.com/jobs/1', posted_at: '2026-09-14T10:00:00Z' };
  const ingest = async rows => scalar('SELECT ingest_hiring_postings($1::jsonb)', [JSON.stringify(rows)]);
  const feed = async (user = user1, country = 'all', status = 'all', search = '', days = 7, offset = 0) =>
    scalar('SELECT list_hiring_leads($1::uuid,$2,$3,$4,$5,$6)', [user, country, status, search, days, offset]);

  assert.equal(await ingest([posting]), 1);
  const initial = (await feed()).leads[0];
  await ingest([posting]);
  await ingest([{ ...posting, provider: 'approved-second-source', external_id: '2', url: 'https://example.org/jobs/2' }]);
  assert.equal(await scalar('SELECT count(*)::int FROM hiring_leads'), 1);
  assert.equal(await scalar('SELECT count(*)::int FROM hiring_postings'), 2);
  assert.equal((await feed()).leads[0].first_seen_at, initial.first_seen_at);
  assert.equal((await feed()).leads[0].postings.length, 2);
  assert.equal((await feed(user1, 'US')).leads.length, 0);
  assert.equal((await feed(user1, 'CA', 'all', 'Toronto')).leads.length, 1);
  assert.equal((await feed(user1, 'CA', 'all', '%')).leads.length, 0); // Search is literal.

  await db.query('INSERT INTO hiring_lead_reviews(user_id,lead_id,status) VALUES($1,$2,$3)', [user1, initial.id, 'saved']);
  assert.equal((await feed(user1, 'all', 'saved')).leads.length, 1);
  assert.equal((await feed(user2, 'all', 'saved')).leads.length, 0);
  assert.equal((await feed(user2, 'all', 'new')).leads.length, 1);
  if (process.env.HIRING_TEST_FEED_OUTPUT) {
    await writeFile(process.env.HIRING_TEST_FEED_OUTPUT, JSON.stringify({ ...(await feed()),
      source: { name: 'Adzuna', configured: false, coverage: 'Synthetic contract test only.' }, runs: [] }));
  }

  // A failed batch is atomic; neither a partial lead nor posting can leak through.
  await assert.rejects(ingest([{ ...posting, fingerprint: 'rollback', external_id: 'bad1' },
    { ...posting, fingerprint: 'rollback2', external_id: 'bad2', country: 'GB' }]));
  assert.equal(await scalar("SELECT count(*)::int FROM hiring_leads WHERE fingerprint LIKE 'rollback%'"), 0);

  const run = await scalar("SELECT claim_hiring_collection('CA')");
  assert.ok(run);
  assert.equal(await scalar("SELECT claim_hiring_collection('CA')"), null);
  assert.ok(await scalar("SELECT claim_hiring_collection('US')"));
  await db.query("UPDATE hiring_collection_runs SET status='failed' WHERE id=$1", [run]);
  const retry = await scalar("SELECT claim_hiring_collection('CA')");
  assert.ok(retry && retry !== run); // Stale worker cannot finish the replacement run.
  await db.query("UPDATE hiring_collection_runs SET status='complete' WHERE id=$1", [retry]);
  assert.equal(await scalar("SELECT claim_hiring_collection('CA')"), null);

  for (const role of ['anon', 'authenticated']) {
    assert.equal(await scalar(`SELECT has_function_privilege('${role}', 'list_hiring_leads(uuid,text,text,text,integer,integer)', 'EXECUTE')`), false);
    assert.equal(await scalar(`SELECT has_function_privilege('${role}', 'ingest_hiring_postings(jsonb)', 'EXECUTE')`), false);
    assert.equal(await scalar(`SELECT has_table_privilege('${role}', 'hiring_lead_reviews', 'SELECT')`), false);
  }
  await db.exec('SET ROLE service_role');
  assert.equal((await feed()).leads.length, 1);
  await db.exec('RESET ROLE');

  await ingest(Array.from({ length: 60 }, (_, index) => ({ ...posting,
    fingerprint: `bulk-${index}`, external_id: `bulk-${index}`, country: 'US', company: `Company ${index}` })));
  const page1 = await feed(user1, 'US');
  const page2 = await feed(user1, 'US', 'all', '', 7, 50);
  assert.equal(page1.leads.length, 50);
  assert.equal(page1.hasMore, true);
  assert.equal(page2.leads.length, 10);
  assert.equal(page2.hasMore, false);
  assert.equal(new Set([...page1.leads, ...page2.leads].map(l => l.id)).size, 60);
  await db.exec("UPDATE hiring_leads SET first_seen_at=now()-interval '10 days', latest_posting_seen_at=now()-interval '10 days' WHERE country='US'");
  assert.equal((await feed(user1, 'US')).leads.length, 0);
  assert.equal((await feed(user1, 'US', 'all', '', 30)).leads.length, 50);
  // Re-reading the same posting never makes it new. A new source posting for an
  // existing signal brings it back into the discovery window without losing review.
  await db.exec("UPDATE hiring_leads SET latest_posting_seen_at=now()-interval '10 days' WHERE country='CA'");
  await ingest([posting]);
  assert.equal((await feed(user1, 'CA')).leads.length, 0);
  await ingest([{ ...posting, external_id: 'new-requisition' }]);
  const refreshed = (await feed(user1, 'CA')).leads[0];
  assert.equal(refreshed.first_seen_at, initial.first_seen_at);
  assert.equal(refreshed.status, 'saved');
  assert.equal(refreshed.postings.length, 3);
  const enriched = { ...posting, fingerprint: 'enriched', provider: 'theirstack', external_id: '123',
    hiring_team: [{name:'Example Recruiter',role:'Recruiter',profile_url:'https://example.com/team'}] };
  await db.query('SELECT close_hiring_posting($1,$2)', ['123','2026-09-15T10:00:00Z']);
  await ingest([enriched]);
  await ingest([enriched]);
  const saved = (await db.query("SELECT closed_at, hiring_team FROM hiring_postings WHERE provider='theirstack'")).rows[0];
  assert.ok(saved.closed_at);
  assert.equal(saved.hiring_team[0].name, 'Example Recruiter');
  await db.query('SELECT close_hiring_posting($1,$2)', ['123','2026-09-14T10:00:00Z']);
  assert.deepEqual(await scalar("SELECT closed_at FROM hiring_postings WHERE provider='theirstack'"),saved.closed_at);
  assert.equal((await scalar('SELECT hiring_delivery_summary()')).receivedLast24h,1);
  for (const role of ['anon','authenticated']) {
    assert.equal(await scalar(`SELECT has_function_privilege('${role}', 'close_hiring_posting(text,timestamp with time zone)', 'EXECUTE')`), false);
  }
  if (process.env.HIRING_TEST_ENRICHED_OUTPUT) {
    await writeFile(process.env.HIRING_TEST_ENRICHED_OUTPUT, JSON.stringify({ ...(await feed()),
      source: {name:'TheirStack',configured:true,coverage:'Contract fixture only',mode:'webhook',
        attributionURL:'https://theirstack.com',receivedLast24h:1,lastReceivedAt:'2026-09-15T10:00:00Z'},runs:[] }));
  }
  console.log('PASS: migration, idempotent ingestion, source preservation, discovery dates, country/search/date filters, private reviews, pagination, atomic rollback, run claims/retries, and service-role permissions');
} finally { await db.close(); }
