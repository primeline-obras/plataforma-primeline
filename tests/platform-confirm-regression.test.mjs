import test from 'node:test';
import assert from 'node:assert/strict';
import {runInNewContext} from 'node:vm';
import {definitions,confirmationContext} from './platform-confirm-handlers.mjs';
for(const [name,code] of definitions) test(name+': full handler pending/cancel/retry/confirm',async()=>{
 let answer,calls=0,writes=0;
 const context=confirmationContext(()=>{calls++;return new Promise(r=>{answer=r;});},()=>writes++);
 runInNewContext(code,context);
 const first=context.invoke();assert.equal(calls,1);assert.equal(writes,0);
 answer(false);await first;assert.equal(writes,0);
 const second=context.invoke();assert.equal(calls,2);answer(true);await second;assert.equal(writes,1);
});