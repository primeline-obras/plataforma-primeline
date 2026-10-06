import assert from 'node:assert/strict';

// Evidence of CURRENT candidate behavior. These assertions do not approve that
// behavior against the new readiness requirement "apenas Administrativo".
export async function readinessFindingsCases(t,{q,auxDo,id}) {
 await t.test('readiness evidence: Gestão/Gerência can persist payroll drafts',async()=>{
  for(const [actor,person,req] of [[11,33101,931101],[12,33102,931102]]) {
   await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Sintético readiness','Pedreiro','2020-01-01')",[id(person),id(1)]);
   const result=await auxDo(actor,'payroll_save',{version:2,request_id:id(req),expected_revision:0,person_id:id(person),month:'2026-09-01',manual:{km:0,allowance:0,note:'Evidência local de autorização'}});
   assert.equal(result.committed,true);
   const rows=(await q('SELECT estado,criado_por FROM folha_vencimentos WHERE colaborador_id=$1',[id(person)])).rows;
   assert.equal(rows.length,1);assert.equal(rows[0].estado,'draft');assert.equal(rows[0].criado_por,id(actor));
  }
 });
}
