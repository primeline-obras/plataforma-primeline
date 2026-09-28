import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(process.env.QUADRO_PGLITE ? pathToFileURL(process.env.QUADRO_PGLITE).href : './quadro-runtime/node_modules/@electric-sql/pglite/dist/index.js');
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const dir='../supabase/quadro_pessoal_20260925/';
const manifest=JSON.parse(await read(dir+'manifesto_95.json'));
const company='73fb13c8-d29f-4192-a506-4ca243343add';
const joao='81a195a3-d75f-4504-87a7-4060078b9f9e';
const wand='ae4df908-5847-4fcd-bf14-f0fbb441cb74';
test('SQLs da semana: 95 posições, backup, João, férias, flags e reexecução',async()=>{
 const db=new PGlite(); await db.exec(await read('./fixtures/quadro-v3-base.sql'));
 assert.equal((await db.query(await read(dir+'00_precheck_leitura.sql'))).rows[0].resultado,'PRE_REQUISITOS_OK_REVER_MIGRACAO');
 await db.exec(await read(dir+'00_regras_movimentacoes.sql'));
 await db.query('INSERT INTO empresas VALUES($1)',[company]);
 for(const row of new Map(manifest.map(r=>[r.colaborador_id,r])).values())
 await db.query("INSERT INTO colaboradores VALUES($1,$2,$3,$4,'2020-01-01',NULL,false)",[row.colaborador_id,company,row.nome,row.funcao_atual]);
 for(const row of new Map(manifest.map(r=>[r.obra_id,r])).values())
 await db.query("INSERT INTO obras VALUES($1,$2,$3,$3,'em_curso')",[row.obra_id,company,String(row.obra)]);
 await db.query("INSERT INTO colaboradores VALUES($1,$2,'Wanderson Oliveira','Enc. Obra','2020-01-01',NULL,false)",[wand,company]);
 await db.query("INSERT INTO ausencias(colaborador_id,data,tipo,estado) SELECT $1,d::date,'ferias','confirmada' FROM generate_series('2026-09-28'::date,'2026-10-02'::date,'1 day') d",[wand]);
 const works=[...new Set(manifest.map(r=>r.obra_id))];
 await db.query("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,semana_inicio,periodo,tipo_alocacao) VALUES($1,$2,'2026-09-21','2026-09-21','dia_inteiro','obra')",[joao,works[0]]);
 const historical=(await db.query('SELECT * FROM quadro_pessoal_alocacao')).rows[0];
 const sql1=await read(dir+'01_prevalidacao.sql'),sql2=await read(dir+'02_backup_gravacao.sql'),sql3=await read(dir+'03_conferencia.sql');
 const pre=(await db.query(sql1)).rows[0]; assert.equal(Number(pre.posicoes_previstas),95); assert.equal(Number(pre.bloqueios),0); assert.equal(pre.estado,'PRONTO');
 // Uma ausência adicional sinaliza apenas a data; não as 5 posições da pessoa.
 await db.query("INSERT INTO ausencias(colaborador_id,data,tipo,estado) VALUES($1,'2026-09-30','ferias','confirmada')",[joao]);
 assert.equal(Number((await db.query(sql1)).rows[0].bloqueios),1);
 await db.query('DELETE FROM ausencias WHERE colaborador_id=$1',[joao]);
 await db.exec(sql2);
 const post=(await db.query(sql3)).rows[0]; assert.equal(post.resultado,'CONCLUIDO'); assert.equal(post.joao_pedreiro,true); assert.equal(post.flags_preservadas,true);
 assert.equal(post.ferias_preservadas,true); assert.equal(post.wanderson_fora_manifesto,true); assert.equal(post.alocacoes_anteriores_preservadas,true);
 assert.deepEqual((await db.query('SELECT * FROM quadro_pessoal_alocacao WHERE id=$1',[historical.id])).rows[0],historical);
 assert.equal(Number((await db.query('SELECT count(*) n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[wand])).rows[0].n),0);
 assert.equal(Number((await db.query('SELECT count(*) n FROM ausencias WHERE colaborador_id=$1',[wand])).rows[0].n),5);
 await db.exec(sql2); assert.equal((await db.query(sql3)).rows[0].resultado,'CONCLUIDO');
 assert.equal(Number((await db.query('SELECT count(*) n FROM quadro_pessoal_alocacao')).rows[0].n),96);
 await db.close();
});
