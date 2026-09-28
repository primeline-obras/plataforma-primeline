import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

// Instalar PGlite apenas no ambiente de testes. Nenhum URL/chave de produção.
const { PGlite } = await import(process.env.QUADRO_PGLITE ? pathToFileURL(process.env.QUADRO_PGLITE).href : './quadro-runtime/node_modules/@electric-sql/pglite/dist/index.js');
const base = await readFile(new URL('./fixtures/quadro-v3-base.sql', import.meta.url),'utf8');
const migration = await readFile(new URL('../supabase/quadro_pessoal_20260925/00_regras_movimentacoes.sql',import.meta.url),'utf8');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
let db;
const query = (sql,args=[]) => db.query(sql,args);
async function login(n) { await db.exec('RESET ROLE'); await query("SELECT set_config('test.uid',$1,false)",[n ? id(n) : '']); if(n) await db.exec('SET ROLE authenticated'); }
async function call(action,data,confirm=false,version=null) {
 return (await query('SELECT public.fn_quadro_operar($1,$2::jsonb,$3,$4) AS r',[action,JSON.stringify(data),confirm,version])).rows[0].r;
}
async function commit(action,data) { const p=await call(action,data); return call(action,data,true,p.versao); }
const payload = (day,work=11,person=20,period='dia_inteiro') => ({colaborador_id:id(person),obra_id:id(work),data:`2026-10-${String(day).padStart(2,'0')}`,periodo:period});

test('PostgreSQL isolado: segurança, transação e histórico',async t=>{
 db=new PGlite(); await db.exec(base); await db.exec(migration);
 await query('INSERT INTO empresas VALUES ($1),($2)',[id(1),id(2)]);
 for(const [n,role] of [[3,'gestao_plataforma'],[4,'administrativo'],[5,'encarregado'],[6,'diretor_obra'],[7,'adjunto'],[8,'preparador'],[9,'gerencia'],[10,'desenhador']]) {
 await query('INSERT INTO utilizadores VALUES($1,$2,$3,$4,true,$1)',[id(n),id(1),role,role]); }
 for(const n of [11,12,13]) await query("INSERT INTO obras VALUES($1,$2,$3,$3,'em_curso')",[id(n),id(1),String(n)]);
 await query("INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,'encarregado')",[id(12),id(5)]);
 await query("INSERT INTO colaboradores VALUES($1,$2,'Pessoa teste','Servente','2020-01-01',NULL,false)",[id(20),id(1)]);
 await t.test('Gestão/ADM adicionam várias obras, flag false, sem substituição',async()=>{
   await login(3); await commit('adicionar',payload(1)); await login(4); await commit('adicionar',payload(1,13));
   assert.equal((await query('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,2);
 });
 await t.test('DO e restantes perfis não escrevem via RPC ou diretamente',async()=>{
   for(const n of [6,7,8,9,10]) { await login(n);
    await assert.rejects(()=>call('adicionar',payload(2)),/Sem autorização/);
    await assert.rejects(()=>query("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,semana_inicio,periodo,tipo_alocacao,criado_por) VALUES($1,$2,'2026-10-02','2026-09-28','dia_inteiro','obra',$3)",[id(20),id(11),id(n)]),/Sem autorização|row-level security/);
    const r=await query("DELETE FROM quadro_pessoal_alocacao RETURNING id"); assert.equal(r.rows.length,0);
   }
 });
 await t.test('Encarregado não gere quadro nem escolhe destino livre',async()=>{
   await login(5); await assert.rejects(()=>call('adicionar',payload(2,12)),/Sem autorização/);
   await assert.rejects(()=>call('minha_obra',payload(2,11)),/Só pode adicionar/);
   const r=await query('SELECT * FROM fn_quadro_obras_destino()'); assert.deepEqual(r.rows.map(w=>w.id),[id(12)]);
   await assert.rejects(()=>query("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,semana_inicio,periodo,tipo_alocacao,criado_por) VALUES($1,$2,'2026-10-02','2026-09-28','dia_inteiro','obra',$3)",[id(20),id(12),id(5)]),/Sem autorização|row-level security/);
 });
 await t.test('Encarregado sem origem cria apenas destino; repetição não duplica',async()=>{
   await commit('minha_obra',payload(2,12)); await assert.rejects(()=>commit('minha_obra',payload(2,12)),/Destino já existente/);
 });
 await t.test('múltiplas origens e períodos parciais não removem nada',async()=>{
   const before=(await query('SELECT * FROM quadro_pessoal_alocacao ORDER BY id')).rows;
   await assert.rejects(()=>commit('minha_obra',payload(1,12)),/Várias origens/);
   assert.deepEqual((await query('SELECT * FROM quadro_pessoal_alocacao ORDER BY id')).rows,before);
   await login(4); await commit('adicionar',payload(3)); await login(5);
   await assert.rejects(()=>commit('minha_obra',payload(3,12,20,'tarde')),/Sobreposição parcial/);
 });
 await t.test('movimento de uma origem preserva ID, autor original, histórico e outras datas',async()=>{
   await login(4); const original=await commit('adicionar',payload(4)); await login(5);
   const moved=await commit('minha_obra',payload(4,12)); assert.equal(moved.alocacao_id,original.alocacao_id);
   const row=(await query('SELECT * FROM quadro_pessoal_alocacao WHERE id=$1',[moved.alocacao_id])).rows[0];
   assert.equal(row.obra_id,id(12)); assert.equal(row.criado_por,id(4));
   const h=(await query("SELECT * FROM quadro_pessoal_movimentos WHERE alocacao_id=$1 AND tipo_acao='mover'",[row.id])).rows[0];
   assert.equal(h.alterado_por,id(5)); assert.equal(h.perfil_autor,'encarregado'); assert.equal(h.antes.obra_id,id(11)); assert.equal(h.depois.obra_id,id(12));
 });
 await t.test('falha no histórico anula a movimentação',async()=>{
   await login(4); const original=await commit('adicionar',payload(5));
   await login(null); await db.exec("CREATE FUNCTION teste_falha_historico() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'falha simulada no histórico'; END $$; CREATE TRIGGER teste_falha BEFORE INSERT ON quadro_pessoal_movimentos FOR EACH ROW EXECUTE FUNCTION teste_falha_historico();");
   await login(5); await assert.rejects(()=>commit('minha_obra',payload(5,12)),/falha simulada/);
   assert.equal((await query('SELECT obra_id FROM quadro_pessoal_alocacao WHERE id=$1',[original.alocacao_id])).rows[0].obra_id,id(11));
   await login(null); await db.exec('DROP TRIGGER teste_falha ON quadro_pessoal_movimentos');
 });
 await t.test('ausência bloqueia apenas aquela data; destino diferente não ignora ausência',async()=>{
   await query("INSERT INTO ausencias(colaborador_id,data,tipo,estado) VALUES($1,'2026-10-06','ferias','confirmada')",[id(20)]);
   await login(5); await assert.rejects(()=>commit('minha_obra',payload(6,12)),/ausente/); await commit('minha_obra',payload(7,12));
 });
 await t.test('duplicação administrativa rejeitada e pré-visualização obsoleta rejeitada',async()=>{
   await login(4); await assert.rejects(()=>commit('adicionar',payload(1)),/idêntica/);
   const data=payload(8,12), p=await call('adicionar',data); await commit('adicionar',payload(8,13));
   await assert.rejects(()=>call('adicionar',data,true,p.versao),/desatualizada/);
 });
 await t.test('histórico limitado à obra do Encarregado e sem escrita',async()=>{
   await login(5); const h=(await query('SELECT * FROM quadro_pessoal_movimentos')).rows;
   assert(h.length>0); assert(h.every(r=>r.obra_origem_id===id(12)||r.obra_destino_id===id(12)));
   await assert.rejects(()=>query('DELETE FROM quadro_pessoal_movimentos'),/permission denied/);
   await login(4); assert((await query('SELECT * FROM quadro_pessoal_movimentos')).rows.length>h.length);
   await assert.rejects(()=>query("UPDATE quadro_pessoal_movimentos SET perfil_autor='x'"),/permission denied/);
 });
 await t.test('função SECURITY DEFINER legada não contorna a proteção',async()=>{
   await login(null); await db.exec(`CREATE FUNCTION teste_atalho() RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,semana_inicio,periodo,tipo_alocacao) VALUES('${id(20)}','${id(11)}','2026-10-09','2026-10-05','dia_inteiro','obra') $$; GRANT EXECUTE ON FUNCTION teste_atalho() TO authenticated;`);
   await login(6); await assert.rejects(()=>query('SELECT teste_atalho()'),/Sem autorização/);
 });
 await t.test('remover por ID conserva outras obras e histórico',async()=>{
   await login(4); const row=(await query("SELECT id FROM quadro_pessoal_alocacao WHERE data='2026-10-01' AND obra_id=$1",[id(11)])).rows[0];
   await commit('remover',{id:row.id});
   assert.equal((await query("SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE data='2026-10-01'")).rows[0].n,1);
   assert.equal((await query("SELECT count(*)::int n FROM quadro_pessoal_movimentos WHERE alocacao_id=$1 AND tipo_acao='remover'",[row.id])).rows[0].n,1);
 });
 await t.test('ADM move por ID e preserva as outras alocações da mesma pessoa',async()=>{
   await login(4); const a=await commit('adicionar',payload(10)); const b=await commit('adicionar',payload(10,13));
   await commit('mover',{id:a.alocacao_id,obra_id:id(12),data:'2026-10-10',periodo:'dia_inteiro'});
   assert.equal((await query('SELECT obra_id FROM quadro_pessoal_alocacao WHERE id=$1',[b.alocacao_id])).rows[0].obra_id,id(13));
   assert.equal((await query('SELECT obra_id FROM quadro_pessoal_alocacao WHERE id=$1',[a.alocacao_id])).rows[0].obra_id,id(12));
 });
 await t.test('destino e colaborador de outra empresa são rejeitados',async()=>{
   await login(null); await query("INSERT INTO obras VALUES($1,$2,'999','Outra empresa','em_curso')",[id(99),id(2)]);
   await login(4); await assert.rejects(()=>commit('adicionar',payload(11,99)),/outra empresa/);
 });
 await db.close();
});
