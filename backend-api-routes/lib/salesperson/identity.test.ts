import assert from 'node:assert/strict';
import test from 'node:test';
import { resolveSalespersonForUser } from '../dialer/salesperson-settings';

function database(rows: any[], error: any = null) {
  const queries: Array<Array<[string,unknown]>> = [];
  return { queries, from() {
    const filters: Array<[string,unknown]> = []; queries.push(filters);
    const q = {
      select: () => q,
      eq: (key: string,value: unknown) => { filters.push([key,value]); return q; },
      maybeSingle: async () => {
        const matching = rows.filter(row=>filters.every(([key,value])=>row[key]===value));
        return { data: matching.length === 1 ? matching[0] : null, error: error ?? (matching.length > 1 ? new Error('Ambiguous account') : null) };
      },
    };
    return q;
  } };
}

test('two Daniels and matching email aliases never select another auth user’s account', async () => {
  const admin=database([{id:'phillippe',user_id:'a',status:'active',workspace_id:'w',email:'shared@example.com',full_name:'Daniel Phillippe'},
    {id:'hughes',user_id:'b',status:'active',workspace_id:'w',email:'shared@example.com',full_name:'Daniel Hughes'}]);
  assert.equal((await resolveSalespersonForUser(admin as any,{userId:'b',email:'shared@example.com',workspaceId:'w'}))?.id,'hughes');
  assert.equal(await resolveSalespersonForUser(admin as any,{userId:'new-user',email:'shared@example.com',workspaceId:'w'}),null);
  assert.equal(admin.queries.some(filters=>filters.some(([key])=>key==='email')),false);
});

test('workspace selection applies before identity resolution; ambiguous or unavailable mappings fail closed', async () => {
  const rows=[{id:'a',user_id:'u',status:'active',workspace_id:'w1'},{id:'b',user_id:'u',status:'active',workspace_id:'w2'}];
  assert.equal((await resolveSalespersonForUser(database(rows) as any,{userId:'u',workspaceId:'w2'}))?.id,'b');
  await assert.rejects(resolveSalespersonForUser(database(rows) as any,{userId:'u'}),/Ambiguous/);
  await assert.rejects(resolveSalespersonForUser(database([],new Error('missing user_id')) as any,{userId:'u',email:'someone@example.com'}),/missing/);
});
