import fs from 'node:fs';import http from 'node:http';import path from 'node:path';
const root=process.cwd();
const server=http.createServer((req,res)=>{
 const url=decodeURIComponent(req.url.split('?')[0]);const allowed=url.startsWith('/docs/prototipos/')||['/src/styles.css','/src/visual-identity-final.css'].includes(url);
 const target=path.resolve(root,'.'+url);if(!allowed||!target.startsWith(root+path.sep)||!fs.existsSync(target)){res.writeHead(404);return res.end();}
 res.setHeader('Content-Type',target.endsWith('.html')?'text/html; charset=utf-8':target.endsWith('.css')?'text/css':target.endsWith('.png')?'image/png':'application/json');res.end(fs.readFileSync(target));
});
server.listen(0,'127.0.0.1',()=>console.log('AD03_PREVIEW=http://127.0.0.1:'+server.address().port+'/docs/prototipos/folha-jornada-ad03.html'));
