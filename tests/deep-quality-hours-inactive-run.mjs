import fs from 'node:fs';import {tmpdir}from'node:os';import{join}from'node:path';import{spawnSync}from'node:child_process';
const out='docs/auditorias/validacao-profunda-20261014/';
let runner=fs.readFileSync('tests/attendance-hours-backend.test.mjs','utf8');const anchor="fs.readFileSync('tests/fixtures/attendance-operational-readers-suite.txt','utf8')";
if(runner.split(anchor).length!==2)throw Error('Hours runner drift');runner=runner.replace(anchor,anchor+"+fs.readFileSync('tests/deep-quality-hours-inactive-cases.txt','utf8')");
const dir=fs.mkdtempSync(join(tmpdir(),'deep-203-hours-')),file=join(dir,'runner.mjs');fs.writeFileSync(file,runner);
const r=spawnSync(process.execPath,[file],{env:process.env,encoding:'utf8',windowsHide:true,timeout:420000,maxBuffer:8*1024*1024});
const log=(r.stdout||'')+(r.stderr||'');fs.writeFileSync(out+'RESULTADO-HORAS-INATIVOS.txt',log);console.log(log);if(r.error)console.error(r.error.message);process.exitCode=r.status??1;
