import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest } from 'next/server';

function resolver(validBearer: boolean) {
  let cookieReads=0;
  const source=readFileSync(new URL('../../app/api/_utils/request-user.ts',import.meta.url),'utf8');
  const module={exports:{} as any};
  const dependencies:Record<string,unknown>={
    'next/headers':{cookies:async()=>{cookieReads++;return {getAll:()=>[],set:()=>{}};}},
    '@supabase/supabase-js':{createClient:()=>({auth:{getUser:async()=>validBearer?{data:{user:{id:'bearer-user'}},error:null}:{data:{user:null},error:{message:'Invalid token'}}}})},
    '@supabase/ssr':{createServerClient:()=>({auth:{getUser:async()=>({data:{user:{id:'cookie-user'}},error:null})}})},
    '@/lib/supabase/env':{getSupabaseUrl:()=>'',getSupabaseAnonKey:()=>'',getSupabaseServiceRoleKey:()=>''},
  };
  vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports:module.exports,require:(id:string)=>dependencies[id]});
  return {resolve:module.exports.resolveUserFromRequest,cookieReads:()=>cookieReads};
}

test('invalid or malformed explicit authorization cannot select a different cookie account',async()=>{
  for(const authorization of ['Bearer rejected-token','Bearer ','Basic invalid']) {
    const auth=resolver(false);
    assert.equal(await auth.resolve(new NextRequest('http://localhost/api/inbox',{headers:{authorization}})),null);
    assert.equal(auth.cookieReads(),0);
  }
});

test('valid bearer selects its own identity; cookie-only web authentication still works',async()=>{
  const bearer=resolver(true);
  assert.equal((await bearer.resolve(new NextRequest('http://localhost/api/inbox',{headers:{authorization:'Bearer valid'}}))).id,'bearer-user');
  assert.equal(bearer.cookieReads(),0);
  const web=resolver(false);
  assert.equal((await web.resolve(new NextRequest('http://localhost/api/inbox'))).id,'cookie-user');
  assert.equal(web.cookieReads(),1);
});
