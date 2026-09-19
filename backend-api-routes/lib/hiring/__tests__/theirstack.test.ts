import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { NextRequest } from 'next/server';
import { POST } from '../../../app/api/webhooks/hiring/theirstack/route';
import { parseTheirStackJob, validTheirStackSignature, sourceDate } from '../theirstack';

const secret = "It's a Secret to Everybody";
const job = { id: 123, job_title: 'Canvasser', date_posted: '2026-09-15',
  company_object: {name: 'Example', domain: 'example.com', industry: 'Construction'},
  url: 'https://example.com/jobs/123', source_url: 'https://example.org/jobs/123',
  locations: [{country_code:'CA',display_name:'Toronto'}, {country_code:'US',display_name:'Buffalo'}],
  discovered_at:'2026-09-15T12:00:00',
  hiring_team:[{full_name:'Example Person',role:'Recruiter',linkedin_url:'https://linkedin.com/in/example'}] };

test('normalizes country-specific leads and preserves attributed hiring contacts', () => {
  const rows = parseTheirStackJob(job);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(r=>r.location), ['Toronto','Buffalo']);
  assert.equal(rows[0].company_url, 'https://example.com');
  assert.equal(rows[0].source_discovered_at, '2026-09-15T12:00:00.000Z');
  assert.equal(rows[0].hiring_team?.[0].name,'Example Person');
  assert.equal(rows[0].contact_email,null);
  assert.equal(rows[0].contact_phone,null);
  assert.equal(parseTheirStackJob({...job,locations:[{country_code:'GB'}]}).length,0);
  assert.throws(()=>parseTheirStackJob({...job,has_blurred_data:true}));
  assert.equal(sourceDate('yesterday'),null);
});

test('checks official signature fixture and rejects changed bytes and malformed headers', () => {
  const sig='sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17';
  assert.equal(validTheirStackSignature('Hello, World!',sig,secret),true);
  assert.equal(validTheirStackSignature('Hello, World?',sig,secret),false);
  assert.equal(validTheirStackSignature('Hello, World!', 'sha256=aa',secret),false);
  assert.equal(validTheirStackSignature('Hello, World!',null,secret),false);
});

test('webhook rejects unsigned requests and validates signed events without writing fixtures', async () => {
  const previous=process.env.THEIRSTACK_WEBHOOK_SECRET;
  process.env.THEIRSTACK_WEBHOOK_SECRET=secret;
  try {
    const body=JSON.stringify({id:1,type:'job.new',payload:job});
    const signature='sha256='+createHmac('sha256',secret).update(body).digest('hex');
    const request=(sig:string, value=body)=>new NextRequest('https://example.com/api/webhooks/hiring/theirstack?validate_only=1',{
      method:'POST',body:value,headers:{'x-theirstack-signature-256':sig}});
    assert.equal((await POST(request('wrong'))).status,403);
    const response=await POST(request(signature));
    assert.equal(response.status,200);
    assert.deepEqual(await response.json(),{validated:true,countries:['CA','US']});
    const invalid='not json';
    assert.equal((await POST(request('sha256='+createHmac('sha256',secret).update(invalid).digest('hex'),invalid))).status,422);
  } finally {
    if(previous===undefined) delete process.env.THEIRSTACK_WEBHOOK_SECRET;
    else process.env.THEIRSTACK_WEBHOOK_SECRET=previous;
  }
});
