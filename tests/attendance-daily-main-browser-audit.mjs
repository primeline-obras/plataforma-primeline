import fs from 'node:fs/promises';import path from 'node:path';import {spawn} from 'node:child_process';import crypto from 'node:crypto';import {fileURLToPath} from 'node:url';
const candidate=fileURLToPath(new URL('../',import.meta.url)),main=process.env.DAILY_MAIN_AUDIT_ROOT;if(!main)throw Error('DAILY_MAIN_AUDIT_ROOT required');
const canonical=p=>fs.readFile(p,'utf8').then(s=>s.replace(/\r\n/g,'\n'));
async function walk(dir){const result=[];for(const d of await fs.readdir(dir,{withFileTypes:true})){const p=path.join(dir,d.name);if(d.isDirectory())result.push(...await walk(p));else result.push(p);}return result;}
let compared=0;for(const p of await walk(path.join(candidate,'src'))){const relative=path.relative(candidate,p);if(!/\.(js|css)$/.test(p))continue;const a=await canonical(p),b=await canonical(path.join(main,relative));if(a!==b)throw Error('SOURCE_DIFF '+relative);compared++;}
const jobs=['attendance-security-visibility','folha-equipa-operacional'];
const results=await Promise.all(jobs.map(async name=>{
 for(const root of [candidate,main]){
  const code=await canonical(path.join(root,'tests',name+'-browser.mjs'));const other=await canonical(path.join(root===candidate?main:candidate,'tests',name+'-browser.mjs'));if(code!==other)throw Error('BROWSER_DIFF '+name);
 }
 return new Promise(resolve=>{const child=spawn(process.execPath,[path.join(main,'tests',name+'-browser.mjs')],{cwd:main,env:process.env,windowsHide:true});let out='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>out+=b);child.on('close',exit=>resolve({name,main_sha:'1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0',exit,source_and_test_identical:true,error:out.slice(-1800)}));});
}));
console.log(JSON.stringify({compared_source_files:compared,results},null,2));
if(results.some(r=>r.exit===0))throw Error('Unexpected baseline PASS: re-investigate');