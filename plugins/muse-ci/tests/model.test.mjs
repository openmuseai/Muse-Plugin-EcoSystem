import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const context={};vm.runInNewContext(await readFile(new URL('../web/model.js',import.meta.url),'utf8'),context);const M=context.CIModel;
test('a run pins its plan and prevents concurrent or mutable execution',()=>{const s=M.initial();M.start(s);assert.equal(s.run.revision,s.revision);assert.throws(()=>M.start(s));assert.throws(()=>M.save(s,'New goal',20,'功能开发'));});
test('a disconnected preview cannot start, pause, resume or advance',()=>{const s=M.initial();s.connected=false;assert.throws(()=>M.start(s));s.connected=true;M.start(s);s.connected=false;assert.throws(()=>M.pause(s));assert.throws(()=>M.next(s));});
test('unresolved decisions block progression; resolving them permits explicit resume',()=>{const s=M.initial();M.start(s);M.next(s);assert.equal(s.run.status,'needs_decision');assert.throws(()=>M.resume(s));M.decide(s,'brand','New name pending verification');M.decide(s,'privacy','No sharing until consent');M.resume(s);M.next(s);assert.equal(s.tasks[2].status,'done');M.next(s);M.next(s);assert.equal(s.run.status,'completed');});
test('cancellation is terminal and keeps the plan',()=>{const s=M.initial();M.start(s);M.cancel(s);assert.equal(s.run.status,'canceled');assert.equal(s.revision,1);assert.throws(()=>M.resume(s));assert.throws(()=>M.next(s));});
test('a changed plan invalidates previous decisions and rejects invalid budget',()=>{const s=M.initial();M.decide(s,'brand','Old name');assert.throws(()=>M.save(s,'',20,'功能开发'));assert.throws(()=>M.save(s,'New goal',0,'功能开发'));M.save(s,'New goal',20,'功能开发');assert.equal(s.revision,2);assert.equal(M.pending(s).length,2);assert.equal(s.goal,'New goal');});

test('malformed persisted events and connection state are rejected',()=>{const s=M.initial();assert.equal(M.validate(s),true);s.events=[null];assert.equal(M.validate(s),false);s.events=[];s.connected='yes';assert.equal(M.validate(s),false);});
