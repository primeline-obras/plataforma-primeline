import fs from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
let runner=fs.readFileSync('tests/attendance-daily-ad13.test.mjs','utf8');
const anchor=".replace('MODE',JSON.stringify(mode));";
if(runner.split(anchor).length!==2)throw Error('AD13 runner drift');
runner=runner.replace(anchor,anchor.slice(0,-1)+"+fs.readFileSync('tests/fixtures/attendance-jornada-ad03-suite.txt','utf8');");
const folder=fs.mkdtempSync(join(tmpdir(),'primeline-ad03-test-')),file=join(folder,'runner.mjs');fs.writeFileSync(file,runner);
const r=spawnSync(process.execPath,[file],{stdio:'inherit',env:{...process.env,AD13_STAGE:'after'},windowsHide:true,timeout:360000});process.exit(r.status??1);
