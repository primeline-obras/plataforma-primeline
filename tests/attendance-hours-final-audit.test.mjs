import fs from 'node:fs';import {tmpdir}from 'node:os';import{join}from 'node:path';import{spawnSync}from 'node:child_process';
let runner=fs.readFileSync('tests/attendance-hours-backend.test.mjs','utf8');
const anchor="fs.readFileSync('tests/fixtures/attendance-operational-readers-suite.txt','utf8')";
if(runner.split(anchor).length!==2)throw Error('Checkpoint runner drift');
runner=runner.replace(anchor,anchor+"+fs.readFileSync('tests/fixtures/attendance-hours-final-audit-suite.txt','utf8')");
const dir=fs.mkdtempSync(join(tmpdir(),'hours-final-audit-')),file=join(dir,'runner.mjs');fs.writeFileSync(file,runner);
const out=spawnSync(process.execPath,[file],{env:process.env,stdio:'inherit',windowsHide:true,timeout:480000});process.exit(out.status??1);
