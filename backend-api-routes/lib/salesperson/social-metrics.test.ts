import assert from 'node:assert/strict';
import test from 'node:test';
import { countPersonalDirectMessages } from './social-metrics';
test('personal DMs include message replies, exclude comment replies and never query a sales workspace column', async()=>{
 const rows=[{user_id:'a',kind:'message',direction:'outbound',occurred_at:'2026-09-08'},
 {user_id:'a',kind:'reply','social_threads.kind':'message',direction:'outbound',occurred_at:'2026-09-08'},
 {user_id:'a',kind:'reply','social_threads.kind':'comment',direction:'outbound',occurred_at:'2026-09-08'},
 {user_id:'b',kind:'message',direction:'outbound',occurred_at:'2026-09-08'},
 {user_id:'a',kind:'message',direction:'inbound',occurred_at:'2026-09-08'}];
 const admin={from(){const filters:Array<(r:any)=>boolean>=[];const q:any={select:()=>q,
 eq:(key:string,value:any)=>{assert.notEqual(key,'workspace_id');filters.push(r=>r[key]===value);return q;},
 gte:(key:string,value:string)=>{filters.push(r=>r[key]>=value);return q;},lt:(key:string,value:string)=>{filters.push(r=>r[key]<value);return q;},
 then:(resolve:any,reject:any)=>Promise.resolve({count:rows.filter(r=>filters.every(f=>f(r))).length,error:null}).then(resolve,reject)};return q;}};
 assert.equal((await countPersonalDirectMessages(admin as any,'a','2026-09-08','2026-09-09')).count,2);
});
