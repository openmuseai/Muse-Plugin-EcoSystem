import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=fileURLToPath(new URL('../web/',import.meta.url));
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8'};
const server=createServer(async(req,res)=>{try{const requested=new URL(req.url,'http://localhost');if(requested.pathname==='/'&&!requested.searchParams.has('demo')){try{const health=await fetch('http://127.0.0.1:4180/health',{signal:AbortSignal.timeout(500)});if(health.ok){res.writeHead(302,{location:'http://127.0.0.1:4180/'});return res.end();}}catch{}}const pathname=decodeURIComponent(requested.pathname);const file=path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname));if(!file.startsWith(root)){res.writeHead(403);return res.end();}const bytes=await readFile(file);res.writeHead(200,{'content-type':mime[path.extname(file)]||'application/octet-stream','cache-control':'no-store'});res.end(bytes);}catch{res.writeHead(404);res.end('Not found');}});
server.listen(Number(process.env.PORT||4178),'127.0.0.1',()=>process.stdout.write(`Muse CI preview: http://127.0.0.1:${server.address().port}\n`));
