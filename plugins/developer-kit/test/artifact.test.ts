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
 assert.ok(script.includes('new EditorView'))
})
