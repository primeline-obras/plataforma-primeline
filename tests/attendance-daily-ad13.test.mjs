import fs from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
const mode=process.env.AD13_STAGE||'after';if(!['before','after'].includes(mode))throw Error('AD13_STAGE');
let runner=fs.readFileSync('tests/attendance-daily-ad14.test.mjs','utf8');
const fixture=fs.readFileSync('tests/fixtures/attendance-daily-ad13-suite.txt','utf8').replace('MODE',JSON.stringify(mode));
const anchor="runner=runner.replace(anchor,insert+'\\n'+anchor);";if(runner.split(anchor).length!==2)throw Error('AD14 runner changed');
runner=runner.replace(anchor,'runner=runner.replace(anchor,insert+'+JSON.stringify(fixture)+'+"\\n"+anchor);');
const folder=fs.mkdtempSync(join(tmpdir(),'primeline-ad13-test-'));const path=join(folder,'runner.mjs');fs.writeFileSync(path,runner);
const env={...process.env,AD14_STAGE:'after'};const r=spawnSync(process.execPath,[path],{stdio:'inherit',env,windowsHide:true,timeout:360000});process.exit(r.status??1);
