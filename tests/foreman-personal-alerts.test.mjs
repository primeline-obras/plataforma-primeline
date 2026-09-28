import test from 'node:test';
import assert from 'node:assert/strict';
import {alertsForOverviewRole,workforceAlertDestination} from '../src/production-dashboard.js';
test('alertas pessoais são exclusivos do destinatário, mesmo para ADM',()=>{
 const alerts=['reserva_sala','compromisso_agenda','movimentacao_equipa'].flatMap(tipo=>['adm','enc','do'].map(user=>({id:`${tipo}-${user}`,tipo,destinatario_utilizador_id:user,obra_id:'120'})));
 for(const [role,user] of [['administrativo','adm'],['encarregado','enc'],['diretor_obra','do'],['gestao_plataforma','adm']]) {
   const rows=alertsForOverviewRole(alerts,role,new Set(['120']),user);
   assert.equal(rows.length,3);assert(rows.every(r=>r.destinatario_utilizador_id===user));
 }
 assert.equal(alertsForOverviewRole(alerts,'administrativo',new Set(), '').length,0);
});
test('destinatário prevalece mesmo num alerta financeiro ou de obra autorizada',()=>{
 const alert={id:'x',tipo:'debito_direto',obra_id:'120',destinatario_utilizador_id:'outro'};
 for(const role of ['financeiro','administrativo','gerencia','diretor_obra']) assert.equal(alertsForOverviewRole([alert],role,new Set(['120']),'eu').length,0);
 assert.equal(alertsForOverviewRole([{id:'publico',tipo:'debito_direto'}],'financeiro').length,1);
});
test('movimentação abre a equipa, conservando o contexto de obra',()=>{
 assert.deepEqual(workforceAlertDestination({tipo:'movimentacao_equipa',obra_id:'120'}),{view:'workforce',workId:'120'});
 assert.equal(workforceAlertDestination({tipo:'reserva_sala'}),null);
});
