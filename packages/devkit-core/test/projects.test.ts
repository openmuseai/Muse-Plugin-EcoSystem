import test from 'node:test'
import assert from 'node:assert/strict'
import {promises as fs} from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {DevkitCore,digest,validateDependencies} from '../src/index.js'
const deps=[{alias:'slides',provider:{id:'test/slides',version:'1.0.0',sha256:'a'.repeat(64)},contract:{id:'https://example.com/slides',version:'1.0.0',tools:['read'],operations:{readSnapshot:'read'}}},{alias:'pdf',provider:{id:'test/pdf',version:'1.0.0',sha256:'b'.repeat(64)},contract:{id:'https://example.com/pdf',version:'1.0.0',tools:['read'],operations:{readSnapshot:'read'}}}]
const host={implementation:{version:'1.0.0',buildSha256:'c'.repeat(64)}}
test('independent multi-provider project, CAS edits, deterministic build and stale report rejection',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'devkit-core-'))
 try {
  const core=new DevkitCore(root,path.resolve('plugins/developer-kit/dist/template'))
  await core.initialize('test-project',deps,host)
  await assert.rejects(core.initialize('test-project',deps,host),/EEXIST/)
  const file=await core.read('test-project','main.js')
  const edited=file.text.replace('多资料讲解助手','验收讲解助手')
  await core.write('test-project','main.js',edited,file.sha256)
  await assert.rejects(core.write('test-project','main.js','x',file.sha256),/REVISION_CONFLICT/)
  await assert.rejects(core.read('test-project','../outside'),/PATH_DENIED/)
  const first=await core.pack('test-project'),second=await core.pack('test-project')
  assert.equal(first.sha256,second.sha256);assert.ok(first.bytes.length>100000)
  const report={status:'passed',codeSha256:digest(edited),providers:deps.map(d=>({...d.provider,pageCount:2,source:'test-fixture'}))}
  await core.record('test-project',report)
  await core.write('test-project','main.js',edited+'\n//changed',digest(edited))
  await assert.rejects(core.record('test-project',report),/STALE/)
  await fs.unlink(path.join(root,'test-project','main.js'));await fs.symlink('/etc/hosts',path.join(root,'test-project','main.js'))
  await assert.rejects(core.read('test-project','main.js'),/SYMLINK_DENIED/)
 }finally{await fs.rm(root,{recursive:true,force:true})}
})
test('rejects conflicting provider versions and duplicate aliases',()=>{
 assert.throws(()=>validateDependencies([deps[0],{...deps[1],alias:'slides'}]),/INVALID_DEPENDENCY/)
 assert.throws(()=>validateDependencies([deps[0],{...deps[1],provider:{...deps[0].provider,sha256:'d'.repeat(64)}}]),/VERSION_CONFLICT/)
})
test('Workspace initialization preserves existing files and rolls back conflicts; reports reject symlinks',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'devkit workspace '))
 try{
  const core=new DevkitCore(root,path.resolve('plugins/developer-kit/dist/template'),'io.openmuse',true)
  await fs.writeFile(path.join(root,'notes.txt'),'existing notes')
  await fs.writeFile(path.join(root,'README.md'),'existing readme')
  await assert.rejects(core.initialize('workspace-plugin',deps,host),/EEXIST/)
  assert.equal(await fs.readFile(path.join(root,'README.md'),'utf8'),'existing readme')
  await assert.rejects(fs.stat(path.join(root,'main.js')),/ENOENT/)
  await fs.unlink(path.join(root,'README.md'))
  await core.initialize('workspace-plugin',deps,host)
  assert.equal(await fs.readFile(path.join(root,'notes.txt'),'utf8'),'existing notes')
  const packed=await core.pack('workspace-plugin'),outside=path.join(root,'outside.txt')
  await fs.writeFile(outside,'do not overwrite')
  await fs.symlink(outside,path.join(root,'test-report.json'))
  await assert.rejects(core.record('workspace-plugin',{status:'passed',codeSha256:packed.codeSha256,providers:deps.map(d=>({...d.provider,pageCount:2,source:'fixture'}))}),/SYMLINK/)
  assert.equal(await fs.readFile(outside,'utf8'),'do not overwrite')
 }finally{await fs.rm(root,{recursive:true,force:true})}
})
