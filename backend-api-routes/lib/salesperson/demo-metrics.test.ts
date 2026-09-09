import assert from 'node:assert/strict';
import test from 'node:test';
import { loadPersonalDemoMetrics, summarizeDemoEvents } from './demo-metrics';

test('demo watch time counts each session once instead of adding progress snapshots',()=>{
  const metrics=summarizeDemoEvents([
    {session_id:'a',event_type:'page_view',watch_seconds:0},
    {session_id:'a',event_type:'video_started',watch_seconds:10},
    {session_id:'a',event_type:'progress_50',watch_seconds:50},
    {session_id:'b',event_type:'page_exit',max_watch_seconds:30},
  ]);
  assert.equal(metrics.sessions,2); assert.equal(metrics.averageWatchSeconds,40);
  assert.equal(metrics.maxWatchSeconds,50); assert.equal(metrics.progress50,1);
});

test('demo counts are personally scoped, date bounded, and paginate beyond 1000 events',async()=>{
  const rows = [...Array.from({length:1001},(_,id)=>({id, salesperson_id:'hughes',created_at:'2026-09-08',session_id:String(id),event_type:'page_view'})),
    {id:2000,salesperson_id:'other',created_at:'2026-09-08',session_id:'foreign',event_type:'page_view'},
    {id:2001,salesperson_id:'hughes',created_at:'2026-09-09',session_id:'future',event_type:'page_view'}];
  const admin={from(){
    const filters:Array<(r:any)=>boolean>=[];let start=0,end=99999;
    const q:any={select:()=>q,order:()=>q,eq:(k:string,v:unknown)=>{filters.push(r=>r[k]===v);return q;},
      gte:(k:string,v:string)=>{filters.push(r=>r[k]>=v);return q;},lt:(k:string,v:string)=>{filters.push(r=>r[k]<v);return q;},
      range:(a:number,b:number)=>{start=a;end=b;return q;},then:(resolve:any,reject:any)=>{
        const selected=rows.filter(r=>filters.every(f=>f(r)));
        return Promise.resolve({data:selected.slice(start,end+1),count:selected.length,error:null}).then(resolve,reject);
      }};return q;
  }};
  const metrics=await loadPersonalDemoMetrics(admin as any,'hughes','2026-09-08','2026-09-09');
  assert.equal(metrics.opens,1001);assert.equal(metrics.demoVideo.pageViews,1001);assert.equal(metrics.demoVideo.sessions,1001);
  assert.equal((await loadPersonalDemoMetrics(admin as any,null,'2026-09-08','2026-09-09')).opens,0);
});
