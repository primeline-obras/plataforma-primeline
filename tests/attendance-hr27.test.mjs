import fs from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
let runner=fs.readFileSync('tests/attendance-jornada-ad03.test.mjs','utf8');
const original='tests/fixtures/attendance-jornada-ad03-suite.txt';
const fixture=fs.readFileSync(original,'utf8').replace(/\r\n/g,'\n'),anchor='}\n`;';if(fixture.split(anchor).length!==2)throw Error('AD03 fixture changed');
const enriched=fixture.replace(anchor,()=>fs.readFileSync('tests/fixtures/attendance-hr27-suite.txt','utf8')+'\n'+anchor);
const folder=fs.mkdtempSync(join(tmpdir(),'primeline-hr27-test-')),fixturePath=join(folder,'enriched.txt'),file=join(folder,'runner.mjs');fs.writeFileSync(fixturePath,enriched);
if(runner.split(original).length!==2)throw Error('AD03 runner changed');runner=runner.replace(original,fixturePath.replaceAll('\\','/'));fs.writeFileSync(file,runner);
const r=spawnSync(process.execPath,[file],{stdio:'inherit',env:process.env,windowsHide:true,timeout:360000});process.exit(r.status??1);