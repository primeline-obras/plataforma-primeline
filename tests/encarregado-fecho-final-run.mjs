// Offline package verification. SQL runs only in disposable local PostgreSQL clusters.
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdtempSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const folder=mkdtempSync(path.join(tmpdir(),'primeline-encarregado-final-results-'));
const units=[
 'encarregado-fecho-final','attendance-backend-v2','folha-equipa-operacional',
 'attendance-domain','encarregado-tablet-ux','foreman-action-plan','calendar-commitments',
 'planning-operational','planning-grid-collapsible','attendance-v2-static','attendance-rollout-consolidated',
 'session-isolation','session-boundary','medicine-client','collaborator-rh-conformity','rh-cadastro',
 'finance-operational-access','rnc-module','vehicle-assignment-client','vehicle-validity',
 'workforce-allocation-client','workforce-movements-permissions','workforce-foremen-multiple-works','workforce-controlled','workforce-admin-only'
];
const browsers=[
 'encarregado-fecho-final','encarregado-tablet-ux','attendance-sheet','attendance-visible-state',
 'attendance-adm-rules','attendance-consolidation','attendance-reconciliation-state',
 'session-boundary','planning-cost-access','workforce-controlled'
];
if(!process.env.QUADRO_PG_BIN||!process.env.QUADRO_TEST_DEPS||!process.env.PLANNING_PLAYWRIGHT)throw Error('Local PostgreSQL and existing synthetic test dependencies are required.');
const jobs=[{name:'unit-postgresql',args:['--test',...units.map(n=>'tests/'+n+'.test.mjs')]},...browsers.map(n=>({name:n,args:['tests/'+n+'-browser.mjs']}))];
const results=[];
for(const job of jobs){
 const r=spawnSync(process.execPath,job.args,{cwd:root,env:process.env,encoding:'utf8',windowsHide:true,timeout:480000});
 const output=(r.stdout||'')+(r.stderr||'');writeFileSync(path.join(folder,job.name+'.txt'),output);
 results.push({name:job.name,status:r.status,error:r.error?.message,summary:output.trim().split(/\r?\n/).slice(-9)});
 console.log(JSON.stringify(results.at(-1)));
 if(r.status!==0){writeFileSync(path.join(folder,'resultados.json'),JSON.stringify({results,pass:false},null,2));console.error('FAIL: '+folder);process.exit(1);}
}
writeFileSync(path.join(folder,'resultados.json'),JSON.stringify({results,pass:true},null,2));
console.log(JSON.stringify({pass:true,folder,jobs:results.length}));
