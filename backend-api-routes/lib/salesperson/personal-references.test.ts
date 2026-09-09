import assert from 'node:assert/strict';
import test from 'node:test';
import { requirePersonalReferences } from '../sales-pro/personal-references';

test('linked records require both user and workspace; foreign IDs and lookup errors fail closed', async () => {
  const rows: Record<string, any[]> = {
    sales_contacts: [{id:'own',workspace_id:'w',owner_user_id:'hughes'}, {id:'foreign',workspace_id:'w',owner_user_id:'phillippe'}, {id:'other-workspace',workspace_id:'elsewhere',owner_user_id:'hughes'}],
    sales_leads: [{id:'own',workspace_id:'w',assigned_user_id:'hughes'}, {id:'foreign',workspace_id:'w',assigned_user_id:'phillippe'}],
  };
  let failure = false;
  const admin = { from(table: string) {
    const filters: Array<[string,unknown]> = [];
    const q = { select:()=>q, eq:(key:string,value:unknown)=>{filters.push([key,value]);return q;},
      maybeSingle: async()=>({data: rows[table].find(row=>filters.every(([key,value])=>row[key]===value)),error:failure ? new Error('Database unavailable') : null}) };
    return q;
  } };
  await requirePersonalReferences(admin as any,'w','hughes',{contactId:'own',leadId:'own'});
  await requirePersonalReferences(admin as any,'w','hughes',{});
  for(const refs of [{contactId:'foreign'},{leadId:'foreign'},{contactId:'other-workspace'},{leadId:'missing'}])
    await assert.rejects(requirePersonalReferences(admin as any,'w','hughes',refs),/not found/);
  failure = true;
  await assert.rejects(requirePersonalReferences(admin as any,'w','hughes',{contactId:'own'}),/Database unavailable/);
});
