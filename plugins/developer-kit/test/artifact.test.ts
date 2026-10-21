import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {parse} from 'acorn'
test('exact packaged HTML contains one intact executable browser script',async()=>{
 const html=await readFile('plugins/developer-kit/dist/web/index.html','utf8')
 assert.equal((html.match(/<script>/g)??[]).length,1)
 assert.equal((html.match(/<\/script>/g)??[]).length,1)
 assert.ok(!html.includes('<!--SCRIPT-->'))
 const script=html.slice(html.indexOf('<script>')+8,html.lastIndexOf('</script>'))
 assert.doesNotThrow(()=>parse(script,{ecmaVersion:'latest'}))
 assert.ok(script.includes('workspace_describe'))
 assert.ok(html.includes('muse init'))
 assert.ok(!html.includes('id="editor"'))
})

test('live narration template packs independent UI and public extension profile',async()=>{
 const {DevkitCore}=await import('../../../packages/devkit-core/src/index.js')
 const {mkdtemp,rm}=await import('node:fs/promises'),os=await import('node:os'),path=await import('node:path'),{default:JSZip}=await import('jszip')
 const root=await mkdtemp(path.join(os.tmpdir(),'devkit-live-template-'))
 try{
  const core=new DevkitCore(root,path.resolve('plugins/developer-kit/dist/template'))
  const dependency={alias:'slides',provider:{id:'io.openmuse/genoffice-pptx',version:'0.7.0',sha256:'a'.repeat(64)},contract:{id:'https://plugins.openmuseai.com/contracts/genoffice/slides-read/v1',version:'1.0.1',mediaType:'application/vnd.openxmlformats-officedocument.presentationml.presentation',operations:{readSnapshot:'slides_read_snapshot'},tools:['slides_read_snapshot']}}
  await core.initialize('live-explainer',[dependency],{implementation:{buildSha256:'b'.repeat(64)}},'document-explainer')
  const packed=await core.pack('live-explainer'),zip=await JSZip.loadAsync(packed.bytes)
  const html=await zip.file('index.html')!.async('text')
  assert.ok(html.includes('开始讲解'));assert.ok(!html.includes('<!--SCRIPT-->'))
  assert.ok(html.includes('call_resource_tool'));assert.ok(html.includes('onPageCompleted'))
  for(const match of html.matchAll(/<script(?: type="module")?>([\s\S]*?)<\/script>/g))assert.doesNotThrow(()=>parse(match[1],{ecmaVersion:'latest',sourceType:'module'}))
  assert.equal(JSON.parse(await zip.file('devkit/project.json')!.async('text')).template,'document-explainer')
 }finally{await rm(root,{recursive:true,force:true})}
})
