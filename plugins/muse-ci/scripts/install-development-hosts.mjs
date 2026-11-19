// Installs a reviewed UI into explicit debug Host profiles. No credentials in
// the App, WebView, URLs, manifest, command line or console output.
import {readFile,mkdir,writeFile,chmod,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const plugin=fileURLToPath(new URL('../',import.meta.url)),root=path.resolve(plugin,'../../..');
const args=process.argv.slice(2),option=k=>args[args.indexOf(k)+1];
const target=option('--target');
if(!['desktop','android'].includes(target))throw Error('--target desktop|android required');
const env=Object.fromEntries((await readFile(path.join(root,'Muse-CI/.data/development.env'),'utf8')).trim().split('\n').map(l=>{const n=l.indexOf('=');return[l.slice(0,n),l.slice(n+1)];}));
if(!env.CI_MCP_TOKEN)throw Error('CI_MCP_TOKEN required');
const ui=await readFile(path.join(plugin,'dist/index.html'));
const definition={id:'io.openmuse.muse-ci',title:'Muse-CI',version:JSON.parse(await readFile(path.join(plugin,'package.json'),'utf8')).version,endpoint:'http://127.0.0.1:4180/mcp',uiResourceUri:'ui://muse-ci/main',uiFile:'muse-ci.html',uiSha256:createHash('sha256').update(ui).digest('hex')};
if(target==='desktop'){
 const dir=option('--directory');if(!path.isAbsolute(dir))throw Error('Explicit absolute --directory required');
 await mkdir(dir,{recursive:true,mode:0o700});await chmod(dir,0o700);
 let list=[];try{list=JSON.parse(await readFile(path.join(dir,'apps.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
 const previous=list.find(d=>d.id===definition.id);
 if(previous?.owner)definition.owner=previous.owner;
 await writeFile(path.join(dir,'muse-ci.html'),ui);
 await writeFile(path.join(dir,'apps.json'),JSON.stringify([...list.filter(d=>d.id!==definition.id),definition],null,2),{mode:0o600});
 // Do not overwrite an existing owner's credential on repeated installs.
 if(!previous?.owner)await writeFile(path.join(dir,definition.id+'.token'),env.CI_MCP_TOKEN,{mode:0o600});
 console.log('Reviewed Muse-CI UI installed into Desktop developer profile.');
}else{
 const pkg=option('--package')||'com.openmuseai.mobile.acceptance';
 if(!/^com\.openmuseai\.mobile\.[a-z]+$/.test(pkg))throw Error('Use an isolated debug package');
 const adb=(argv,input)=>{const r=spawnSync('adb',argv,{input,encoding:'utf8'});if(r.status!==0)throw Error('ADB operation failed: '+r.stderr);return r.stdout;};
 const dir='files/remote-mcp-apps';
 adb(['shell','run-as',pkg,'mkdir','-p',dir]);
 let list=[];try{list=JSON.parse(adb(['shell','run-as',pkg,'cat',dir+'/apps.json']));}catch{}
 const previous=list.find(d=>d.id===definition.id);if(previous?.owner)definition.owner=previous.owner;
 const put=(name,data)=>adb(['shell','run-as',pkg,'sh','-c',`'cat > ${dir}/${name} && chmod 600 ${dir}/${name}'`],data);
 put('muse-ci.html',ui);put('apps.json',JSON.stringify([...list.filter(d=>d.id!==definition.id),definition],null,2));
 if(!previous?.owner)put(definition.id+'.token',env.CI_MCP_TOKEN);
 adb(['reverse','tcp:4180','tcp:4180']);
 console.log('Reviewed Muse-CI UI installed into Android QA developer profile; USB backend tunnel active.');
}
