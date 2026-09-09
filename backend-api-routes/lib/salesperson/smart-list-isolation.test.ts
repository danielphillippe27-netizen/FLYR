import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import vm from 'node:vm';
import ts from 'typescript';

test('local lists remain private across account switches and foreign deletes',async()=>{
 let userId='a';const storage=new Map<string,string>();
 storage.set('flyr:crm:local-smart-lists:w',JSON.stringify([{id:'old-unknown',workspace_id:'w',created_by_user_id:'local',name:'Unknown owner',criteria:{},created_at:'2026-01-01',updated_at:'2026-01-01'}]));
 const client={auth:{getSession:async()=>({data:{session:{user:{id:userId}}},error:null})},from:()=>{
  const q:any={select:()=>q,eq:()=>q,order:()=>q,then:(resolve:any)=>Promise.resolve({data:[],error:null}).then(resolve)};return q;
 }};
 const module={exports:{} as any};
 const source=readFileSync(new URL('../services/SmartListsService.ts',import.meta.url),'utf8');
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,{
  exports:module.exports,require:()=>({createClient:()=>client}),crypto:{randomUUID},window:{localStorage:{getItem:(key:string)=>storage.get(key)??null,setItem:(key:string,value:string)=>storage.set(key,value)}},Date,
 });
 const service=module.exports.SmartListsService;
 const own=await service.createLocalWorkspaceSmartList({workspaceId:'w',name:'A private',createdByUserId:'b',criteria:{}});
 assert.equal(own.created_by_user_id,'a');
 assert.deepEqual(Array.from(await service.fetchWorkspaceSmartLists('w'),(row:any)=>row.name),['A private']);
 userId='b';
 assert.equal((await service.fetchWorkspaceSmartLists('w')).length,0);
 await assert.rejects(service.fetchUserWorkspaceSmartLists('w','a'),/owner does not match/);
 await service.deleteWorkspaceSmartList(own.id,'w');
 const other=await service.createLocalWorkspaceSmartList({workspaceId:'w',name:'B private',criteria:{}});
 assert.equal(other.created_by_user_id,'b');
 userId='a';
 assert.deepEqual(Array.from(await service.fetchWorkspaceSmartLists('w'),(row:any)=>row.name),['A private']);
});
