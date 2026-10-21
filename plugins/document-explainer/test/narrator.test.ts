import test from 'node:test'
import assert from 'node:assert/strict'
import {Narrator,type NarrationServices} from '../src/narrator.js'
function fixture(){const navigated:number[]=[],prompts:string[]=[],cancelled:string[]=[],conversations:any[]=[];let current=1,count=0
 const api:NarrationServices={state:async()=>({name:'Real deck',pageCount:3,index:current}),goTo:async index=>{navigated.push(index);current=index},read:async index=>({index,text:'Actual page '+index}),generate:async(text,ref)=>{prompts.push(text);conversations.push(ref);return {taskRef:'task-'+(++count),conversationRef:'conversation'}},status:async()=>({status:'completed',text:'Model output'}),cancel:async task=>{cancelled.push(task)},delay:async()=>{}}
 return {api,navigated,prompts,cancelled,conversations}}
test('first and current page start, preserve one conversation and wait per page',async()=>{
 const f=fixture(),n=new Narrator(f.api,()=>{});await n.start();assert.deepEqual(f.navigated,[0,1,2]);assert.equal(n.state,'completed');assert.deepEqual(f.conversations,[undefined,'conversation','conversation']);assert.match(f.prompts[0],/第 1\/3 页/)
 const g=fixture(),m=new Narrator(g.api,()=>{});await m.start('current');assert.deepEqual(g.navigated,[1,2])
})
test('pause cancels the current task; late completion cannot navigate; continue retries incomplete page',async()=>{
 const f=fixture();let release!:()=>void
 f.api.delay=async()=>new Promise<void>(resolve=>{release=resolve})
 const n=new Narrator(f.api,()=>{}),run=n.start();while(!release)await new Promise(resolve=>setImmediate(resolve));await n.pause();release();await run
 assert.equal(n.state,'paused');assert.deepEqual(f.cancelled,['task-1']);assert.deepEqual(f.navigated,[0]);f.api.delay=async()=>{};await n.start();assert.deepEqual(f.navigated,[0,0,1,2])
})
test('inactive documents and no text cannot generate invented explanations',async()=>{
 const f=fixture(),n=new Narrator(f.api,()=>{});n.setActive(false);await n.start();assert.equal(f.prompts.length,0)
 n.setActive(true);f.api.read=async index=>({index,text:'',status:'no-text-layer'});await n.start();assert.equal(n.state,'error');assert.equal(f.prompts.length,0)
})
