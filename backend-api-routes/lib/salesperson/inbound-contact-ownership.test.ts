import assert from 'node:assert/strict';
import test from 'node:test';
import { findContactForInbound, getContactForWorkspace } from '../dialer/telnyx-messaging';

test('same caller number matches only the receiving user’s contact; unknown owners remain unmatched', async () => {
  const rows = [
    {id:'other',workspace_id:'w',user_id:'phillippe',phone:'+14165550100'},
    {id:'mine',workspace_id:'w',user_id:'hughes',phone:'+14165550100'},
  ];
  const admin = {from() {
    const filters: Array<[string,unknown]> = [];
    const execute=()=>({data:rows.filter(row=>filters.every(([key,value])=>(row as any)[key]===value)),error:null});
    const q:any={select:()=>q,order:()=>q,limit:()=>q,or:()=>q,
      eq:(key:string,value:unknown)=>{filters.push([key,value]);return q;},
      maybeSingle:async()=>({...execute(),data:execute().data[0]??null}),
      then:(resolve:any,reject:any)=>Promise.resolve(execute()).then(resolve,reject)};
    return q;
  }};
  assert.equal((await findContactForInbound(admin as any,'w','+14165550100','hughes'))?.id,'mine');
  assert.equal(await findContactForInbound(admin as any,'w','+14165550100','new-user'),null);
  assert.equal(await findContactForInbound(admin as any,'w','+14165550100',null),null);
  assert.equal(await getContactForWorkspace(admin as any,'other','w','hughes'),null);
  assert.equal(await getContactForWorkspace(admin as any,'mine','elsewhere','hughes'),null);
});
