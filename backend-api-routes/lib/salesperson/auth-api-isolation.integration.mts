// Actual local GoTrue sessions -> request-user -> workspace context -> CRM handler.
// Run with tsx. Never targets a deployed environment or sends email.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import vm from 'node:vm';
import ts from 'typescript';
import { createClient } from '@supabase/supabase-js';
import { NextRequest } from 'next/server';
const config=JSON.parse(readFileSync('/tmp/personal-isolation-stack-status.json','utf8'));
assert.equal(config.API_URL,'http://127.0.0.1:56321');
const admin=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const sql=(query:string)=>execFileSync('psql',['postgresql://postgres:postgres@127.0.0.1:56322/postgres','-X','-v','ON_ERROR_STOP=1','-At','-c',query],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const require=createRequire(import.meta.url);
const overrides:Record<string,any>={
 'next/headers':{cookies:async()=>({getAll:()=>[],set:()=>{}})},
 '@/lib/supabase/env':{getSupabaseUrl:()=>config.API_URL,getSupabaseAnonKey:()=>config.ANON_KEY,getSupabaseServiceRoleKey:()=>config.SERVICE_ROLE_KEY},
 '@/lib/supabase/server':{createAdminClient:()=>admin},
 '@/lib/sales-pro/personal-references':require('../sales-pro/personal-references.ts'),
};
function load(path:string) {
 const module={exports:{} as any};
 const source=readFileSync(new URL('../../'+path,import.meta.url),'utf8');
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,
 {exports:module.exports,require:(id:string)=>overrides[id]??require(id),console,process:{env:{SALES_PRO_ENFORCE_ROLLOUT:'false'}},Buffer,Date});
 return module.exports;
}
overrides['@/app/api/_utils/request-user']=load('app/api/_utils/request-user.ts');
overrides['@/app/api/_utils/workspace']=load('app/api/_utils/workspace.ts');
overrides['@/lib/sales-pro/context']=load('lib/sales-pro/context.ts');
const contacts=load('app/api/crm/contacts/route.ts');
const users:Array<{id:string;token:string}>=[];
const workspace=randomUUID(),contactA=randomUUID(),contactB=randomUUID();
try {
 for(let i=0;i<3;i++) {
  const email=`isolation-${randomUUID()}@example.test`,password=randomUUID()+randomUUID();
  const created=await admin.auth.admin.createUser({email,password,email_confirm:true});
  assert.equal(created.error,null); assert.ok(created.data.user);
  const fixture={id:created.data.user.id,token:''};users.push(fixture);
  const client=createClient(config.API_URL,config.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const login=await client.auth.signInWithPassword({email,password});
  assert.equal(login.error,null);assert.ok(login.data.session);fixture.token=login.data.session.access_token;
 }
 sql(`INSERT INTO workspaces(id,name,owner_id) VALUES ('${workspace}','Actual auth isolation','${users[0].id}');
 INSERT INTO workspace_members(workspace_id,user_id,role) VALUES ${users.map((u,i)=>`('${workspace}','${u.id}','${i===0?'owner':'member'}')`).join(',')} ON CONFLICT DO NOTHING;
 INSERT INTO sales_contacts(id,workspace_id,owner_user_id,name) VALUES ('${contactA}','${workspace}','${users[0].id}','A private'),('${contactB}','${workspace}','${users[1].id}','B private');
 INSERT INTO smart_lists(id,workspace_id,created_by_user_id,name) VALUES ('${contactA}','${workspace}','${users[0].id}','A list'),('${contactB}','${workspace}','${users[1].id}','B list');
 INSERT INTO calendar_events(id,workspace_id,user_id,title,start_at,end_at) VALUES
 ('${contactA}','${workspace}','${users[0].id}','A private meeting',now(),now()+interval '1 hour'),
 ('${contactB}','${workspace}','${users[1].id}','B private meeting',now(),now()+interval '1 hour');`);
 for(const [index,user] of users.entries()) {
  const request=new NextRequest(`http://localhost/api/crm/contacts?workspaceId=${workspace}`,{headers:{authorization:`Bearer ${user.token}`}});
  const resolved=await overrides['@/app/api/_utils/request-user'].resolveUserFromRequest(request);
  assert.equal(resolved.id,user.id);
  const response=await contacts.GET(request),body=await response.json();
  assert.equal(response.status,200,JSON.stringify(body));
  assert.deepEqual(body.contacts.map((c:any)=>c.id),index===0?[contactA]:index===1?[contactB]:[]);
  const personalClient=createClient(config.API_URL,config.ANON_KEY,{global:{headers:{Authorization:`Bearer ${user.token}`}},auth:{persistSession:false}});
  const lists=await personalClient.from('smart_lists').select('id');
  assert.equal(lists.error,null);assert.deepEqual(lists.data?.map(row=>row.id),index===0?[contactA]:index===1?[contactB]:[]);
  const deniedListDelete=await personalClient.from('smart_lists').delete().eq('id',index===1?contactA:contactB).select('id');
  assert.equal(deniedListDelete.error,null);assert.deepEqual(deniedListDelete.data,[]);
  const calendar=await personalClient.from('calendar_events').select('id');
  assert.equal(calendar.error,null);
  assert.deepEqual(calendar.data?.map(row=>row.id),index===0?[contactA]:index===1?[contactB]:[]);
  const foreignWrite=await personalClient.from('calendar_events').update({title:'Unauthorized change'}).eq('id',index===1?contactA:contactB).select('id');
  assert.equal(foreignWrite.error,null);assert.deepEqual(foreignWrite.data,[]);
  const foreign=await contacts.GET(new NextRequest(`http://localhost/api/crm/contacts?workspaceId=${randomUUID()}`,{headers:{authorization:`Bearer ${user.token}`}}));
  assert.equal(foreign.status,403);
 }
 const invalid=await contacts.GET(new NextRequest(`http://localhost/api/crm/contacts?workspaceId=${workspace}`,{headers:{authorization:'Bearer invalid'}}));
 assert.equal(invalid.status,401);
 console.log('PASS: actual GoTrue sign-in, bearer validation, workspace membership and CRM reads isolate two coworkers/new user; invalid auth and foreign workspace denied.');
} finally {
 sql(`DELETE FROM smart_lists WHERE workspace_id='${workspace}'; DELETE FROM calendar_events WHERE workspace_id='${workspace}'; DELETE FROM workspaces WHERE id='${workspace}';`);
 for(const user of users) {
  sql(`DELETE FROM salespeople WHERE user_id='${user.id}';`);
  const deleted=await admin.auth.admin.deleteUser(user.id);assert.equal(deleted.error,null);
 }
}
