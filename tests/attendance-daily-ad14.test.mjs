// Reuse AD-15 and the original synthetic bootstrap unchanged; emit an isolated runner.
import fs from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
const mode=process.env.AD14_STAGE||'after';if(!['before','after'].includes(mode))throw Error('AD14_STAGE must be before or after');
let runner=fs.readFileSync('tests/attendance-daily-he-tenant.test.mjs','utf8');
const insert=fs.readFileSync('tests/fixtures/attendance-daily-ad14-suite.txt','utf8').replace('MODE',JSON.stringify(mode));
const anchor='const folder=fs.mkdtempSync';if(runner.split(anchor).length!==2)throw Error('AD15 runner anchor changed');
runner=runner.replace(anchor,insert+'\n'+anchor);
const folder=fs.mkdtempSync(join(tmpdir(),'primeline-ad14-test-'));const path=join(folder,'runner.mjs');fs.writeFileSync(path,runner);
const result=spawnSync(process.execPath,[path],{stdio:'inherit',env:process.env,windowsHide:true,timeout:360000});process.exit(result.status??1);
