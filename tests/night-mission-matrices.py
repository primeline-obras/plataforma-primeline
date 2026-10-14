import csv,json,re,hashlib
from pathlib import Path
R=Path('docs/auditorias/auditoria-global-noturna-20261014')
for n in range(3,8):(R/f'FASE-{n}').mkdir(exist_ok=True)
def readcsv(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def csvout(rel,rows):
 assert rows
 with (R/rel).open('w',encoding='utf-8-sig',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]),quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(rows)
def doc(rel,text):(R/rel).write_text(text.strip()+'\n',encoding='utf-8')
def location(file,needle):
 text=Path(file).read_text(encoding='utf-8-sig');at=text.find(needle)
 return file+':'+str(text[:at].count('\n')+1) if at>=0 else file+' [PONTO NÃO LOCALIZADO]'
areas=readcsv(R/'02-INVENTARIO-PLATAFORMA.csv');prior=readcsv(R/'FASE-2/34-PENDENCIAS-CLASSIFICADAS.csv');refs=readcsv(R/'11-REFERENCIAS-FRONTEND.csv')
assert len(areas)==38 and len(prior)==34
runs=[{'phase':3,'suite':'night-phase3-rh-run.mjs','pass':299,'fail':0,'skip':0,'nature':'292 contagens preservadas +7 novas; PG nativo'}, {'phase':3,'suite':'night-phase3-finance.test.mjs','pass':9,'fail':0,'skip':0,'nature':'8 cenários +grupo; auth monetária stubs'}, {'phase':3,'suite':'night-phase3-procurement +session-boundary +procurement-planning-pending +planning-operational','pass':29,'fail':0,'skip':0,'nature':'4 novas +25 regressões seguras'}, {'phase':5,'suite':'night-phase5-profiles.test.mjs','pass':8,'fail':0,'skip':0,'nature':'capabilities frontend, não grants'}, {'phase':7,'suite':'night-phase7-rh-batch.test.mjs','pass':5,'fail':0,'skip':0,'nature':'4 cenários +grupo; RH/import nativo'}]
(R/'RESULTADOS-FASES-3-A-7.json').write_text(json.dumps({'observed_final_runs':runs,'total_node_pass':350,'fail':0,'skip':0,'phase1_pass_preserved':236,'phase2_pass_preserved':42,'global_unique_total_not_claimed':True,'production_access':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
e2e=[
('FIN-A','Orçamento→TEE→Planeamento→Auto→Fatura','orcamento_fases;TEE;auto','importar_orcamento_fases;TEEtriggers;submitMeasurement;submitBilling','decidir_faturacao_auto;links','FIN-CHAIN','PASS PARCIAL','Budget2000;auto1200-dedução200=fatura1000;draft→emitida','Ponte TEEartigos→auto não provada;aprovaçãoauto seed;authstubs'),
('FIN-B','Recebimento→badge→saldo','faturacao1000/recebido100','marcar_faturacao_auto_paga','renderMeasurementsTab;overview','FIN-CONSUMERS','VULNERABILIDADE REPRODUZIDA','PAGO semação;saldo900 noutroconsumer','Causa N-FIN-05preservada;efeito consumidor'),
('FIN-C','Draftauto→Faturado','auto250;advance200','totalClientBilling','KPI autos/emitidas','FIN-DRAFT','DECISÃO SEMÂNTICA','helper450;emitidas0','N-FIN-02;nome final não inferido'),
('FIN-D','Mapa→caixa','contratozero;forecast100/123','buildRows;actualCashFlowByMonth','Mapa Financeiro','FIN-MAPS','OBSERVADO / DECISÃO','margem-23;entrada100;PVzero→2000','Conceitos diferentes;N-FIN-03/08'),
('FIN-E','TEE/SUB→previsão→recusa','TEE300+SUB500','sincronizar_tee/subprevisao','task;forecast','FIN-TEE-CONSUMERS','FALHA / REGRA OBSERVADA','Recusa remove300;task mantém;um mês;IVAigual','N-FIN-06/08/09;Q07'),
('FIN-F','Fecho→alterarcompromisso','mesfechado','ajustar_saida_prevista_mensal','mapa','FIN-CLOSED','PASS','Fechado intacto','Alterações fora dohistórico precisamregra'),
('RH-A','Cadastro/contrato→Equipa→Folha→mês→correção','Cadastro/contratoseeds;480→240','equipa_operar_v2;plano_integrado_v3','relatorio_horas_v3;conferencia_contexto_v3','RH-CHAIN','PASS PARCIAL','Previewzero;mensal/auditoriaatualizam;payroll0','Cadastro seed nesta cadeia;writer testado RH7 separado'),
('RH-B','FALTOU→Mapa→classificação→mês','ausencianeutra','folha_faltou_v2','ausencias_contexto_v3;conferencia','RH-FALTOU','PASS','UUID/proveniência;zero horas','Fechopayroll distinto;semvalidação fictícia'),
('RH-C','Preview→revogação→confirm','atorinativo','plano_integrado_v3','conferencia','RH-REVOKE','PASS','42501zerofactos','Local sintético'),
('RH-D','Multiobra→empresa errada','obras100/103','plano_integrado_v3','mês','RH-TENANT','PASS','42501rollbacktotal','Matriz escopo synthetic'),
('TASK-A','Tarefa→reporte→alertas→conclusão→validação','tarefa emexecucao','gestao_v2 task_report/task_confirm','reportes;alertas','TASK-CHAIN','PASS PARCIAL','Não conclui;3destinatáriosúnicos;confirmresolve','Conclusão oficial seedUPDATE, não batch frontend ligado'),
('TASK-B','Adj/Preparador→stale→revogação','revision1','task_confirm/reportreplay','reportes','TASK-ROLES','PASS','Adjconfirma;Prep42501;stale40001','Sem inferir restantescapabilities'),
('PUR-A','Consulta→trocaobra','consultaA','procurement.load','render','TEMP-P3-C01','FALHA COMPROVADA','ContextoB comdados A','Mesmaidentidade;sem bypass tenant provado'),
('PUR-B','Preço→adjudfalhada','2×50=100','saveCandidate;withButton','candidate','PUR-INTERRUPTED','OBSERVADO / UX','Preço guardado;adjudfalha;erroexplícito','PersistênciaRPCmodelada;adjudSQLnãoexecutada'),
('PUR-C','Item→históricopreço','itemsemheader','loadPriceRows','priceRows','TEMP-P3-C02','FALHA DE PROVENIÊNCIA','Preçosemorigem semwarning','Header sintético;cap REST/RLSnão vistos'),
('PUR-D','Comparativo→custeio','menor140/estimado160/adjud180/venda240','calculateBestPrices/Costing','margem/desvio','PUR-CONCEPTS','PASS','Margem60;desvio20;negociação40','Não comprova cadeiaadjuddocfatura'),
('MIG-A','Policysegura→antigo→rollback','policytenantfixture','autos_faturacao_workflow.sql','SELECTauthenticated','MIG-ORDER','VULNERABILIDADE ORDEM SINTÉTICA','Leiturareabre;rollbackrestaura','Não catálogo real'),
('DOC-A','Doc→entidade inexistente','metadatafixture','INSERTfixture','joinfatura','DOC-MISSING','HIPÓTESE','Fixtureaceitaórfão','Semtriggerreal;NÃOprovaproduto'),
('RH7-A','Cadastro→contrato→alocação→audit→leitor','payloadformalPreparador;escritorioexplícito','fn_rh_guardar/criar_colaborador','fn_rh_consultar','RH7-CADASTRO','PASS','Contrato/alocação/autor','Clusterseparado;criadorcampos_completos versionado'),
('RH7-B','Excel→preview→falha→rollback','válida+inexistente','fn_rh_importar','cadastro/audit','RH7-BATCH','PASS','Sem gravação parcial','Writer completo semstub'),
]
rows=[dict(id_temporario=k,processo=p,origem=o,writer=w,leitores_consumidores=l,prova=e,estado=s,resultado=r,limite=b,teste='tests/night-phase3-*;tests/night-phase7-rh-batch.test.mjs')for k,p,o,w,l,e,s,r,b in e2e];csvout('FASE-3/MATRIZ-END-TO-END.csv',rows)
new=[dict(id_temporario='TEMP-P3-C01',codigo_existente_correspondencia='N-ARCH-01;resiliência;IDoficiala confirmar',modulo='Compras',prioridade='P2',estado='FALHA COMPROVADA LOCAL',problema='Trocaobra A→B conserva consultasA sobcontexto B',evidencia='src/procurement.js:175-237 load;EVIDENCIAS-COMPRAS.json',sequencia='loadApendente→loadBalterastateworkretorna→Aresolve→loadedA/contextB',dependencias='Sem bypass tenant provado',aceitacao='RespostaA não renderiza B;Bcarregada;açõesalvocerto'),dict(id_temporario='TEMP-P3-C02',codigo_existente_correspondencia='N-FOR-05/N-FOR-02',modulo='Preços',prioridade='P2',estado='FALHA DE PROVENIÊNCIA REPRODUZIDA',problema='Itemsemheader exibe preço semwarning',evidencia='src/subcontractors.js:611-662 loadPriceRows',sequencia='headers200[]+items200[item]→fornecedorindefinido→priceErrorvazio',dependencias='Dados reais/RLSnão provados',aceitacao='Origemausente identificaincompletude')];csvout('FASE-3/NOVAS-DESCOBERTAS.csv',new)
focus=[
('Sessão antiga não retorna REST/body/Storage após clear; 403 preserva login','CORRETO','session-boundary (7 testes)',3,'Auth hospedado e JWT externo não testados'),
('Reporte gera três destinatários únicos; confirmação resolve alertas','CORRETO','TASK-CHAIN',5,'Rotina global/email/agendamento não ligados'),
('Contrato escolhido por heurística; zero cai no inicial','OBSERVADO / DECISÃO','FIN-MAPS',5,'Vigência contratual não exercitada integralmente'),
('Projetos usa totais próprios e empresa do bootstrap','ESTÁTICO','src/projects.js:70;N-ADM-09',4,'Criação→associação da obra→totais não exercitada'),
('Orçamento de fase gravado por RPC e lido na cadeia','CORRETO PARCIAL','FIN-CHAIN',7,'Itens MQT/TEE não reconciliados artigo a artigo'),
('Preview não muta; pesos/dependências controlam indicadores','CORRETO PARCIAL','planning-operational (13 testes)',5,'Batch DB não ligado à conclusão de tarefa nesta cadeia'),
('Reporte não conclui; confirmação exige Planeamento concluído','CORRETO','TASK-CHAIN/TASK-ROLES',4,'Calendário clicável continua standby'),
('Auto/adiantamento podem contar como faturado antes de emitir','DECISÃO SEMÂNTICA','FIN-DRAFT',5,'RSP/fonte SQL não ligados integralmente'),
('MGO possui fonte SQL e métricas distintas; cargo RH não é login','ESTÁTICO','src/management-map.js;N-FIN-07',5,'MGO completo não executado nesta cadeia'),
('Resumo SQL não é o agregado HR29; fontes diferentes','ESTÁTICO','N-FIN-07;HR38 preservado',5,'Mitigação HR38 não implementada'),
('Margem mensal -23 e caixa entrada100; zero efetivo usa fallback','OBSERVADO / DECISÃO','FIN-MAPS',5,'Mapa anual não equivale a ledger'),
('Recusa retira300 do forecast mas mantém tarefa','FALHA COMPROVADA','FIN-TEE-CONSUMERS',5,'Autorização futura versus executado exige Q07'),
('Auto criado1200 menos dedução200 resulta1000; aprovação semeada','CORRETO PARCIAL','FIN-CHAIN',7,'Ponte granular TEE→auto não demonstrada'),
('Recebimento100 mostra PAGO com saldo900 noutro consumidor','VULNERABILIDADE REPRODUZIDA','FIN-CONSUMERS',5,'RPC parcial não ligada; Q04'),
('Falha de artigos mantém cabeçalho; prova Fase2 preservada','FALHA ANTERIOR','N2-FIN-01',7,'Adjudicação→documento→fatura completa não executada'),
('Débitos tenant-safe existem numa branch separada','PREPARADO NÃO INTEGRADO','DD-TENANT abc160d',9,'Não consumir gate ou instalar'),
('Identidade de fornecedor exige ID/relacionamentos','ESTÁTICO','N-FOR-04;subcontractors',6,'Duplicados reais não consultados'),
('Preço sem cabeçalho e sem aviso de origem','FALHA REPRODUZIDA','TEMP-P3-C02',3,'Paginação e cap REST não comprovados'),
('Contexto da obra muda enquanto chega resposta anterior','FALHA COMPROVADA','TEMP-P3-C01;PUR-INTERRUPTED',7,'Adjudicação SQL completa não exercitada'),
('Menor140 não é adjudicado180; margem60','CORRETO','PUR-CONCEPTS',5,'Sem transação de adjudicação integrada'),
('Cadastro real cria contrato/alocação; lote inválido faz rollback','CORRETO','RH7-CADASTRO/BATCH/ROLES',7,'Dependências dos ficheiros identificadas; sem catálogo hospedado'),
('Leitores Medicina reduzidos por perfil; prova anterior preservada','ANTERIOR; NÃO REEXECUTADO','Fase1 Medicina/Viaturas',6,'Documento→Medicina→alerta não ligado nesta fase'),
('FALTOU chega à classificação/mês sem inventar horas','CORRETO','RH-FALTOU;native299',5,'Calendário real e payroll não testados'),
('Equipa usa permanências; FaseB está separada','CORRETO PARCIAL','native299;PHASE-B',9,'FaseB real proibida'),
('Plano480→240 propaga mensal/auditoria; preview zero factos','CORRETO','RH-CHAIN/TENANT',7,'FP28/29 continuam standby'),
('Referências/multiobra/HR27/30/31 regressões nativas','CORRETO COM HR38 ABERTO','RESULTADO-RH-LOCAL.txt',6,'Privacidade de agregados ainda depende de mitigação'),
('Conferência não cria Vencimentos; HE informativa preservada','CORRETO','native299 MONTHLY/HR27',5,'Conferência não equivale ao fecho salarial'),
('Concorrência de atribuição/saída RH preservada na Fase1','ANTERIOR/ESTÁTICO','N-ADM-08;vehicle-assignment-concurrency',6,'Nova cadeia viatura/documentos não executada'),
('Texto documental protegido; associação/entidade precisa provar','CONTROLO PROTEGIDO / HIPÓTESE','Fase2HTML;DOC-MISSING',7,'Fixture sem trigger não prova órfão no produto'),
('Empresa do bootstrap chega ao arquivo da empresa','ESTÁTICO','N-ADM-09;N-DOC-01',4,'Grants/associação de empresa não exercitados'),
('Gestão continua sem canCreate; achado anterior','FALHA ANTERIOR','N-ADM-07;src/rnc.js:22',4,'Cadeia RNC/evidências/PDF não exercitada'),
('Observações Segurança escapadas; writers separados','ESTÁTICO','src/app.js renderSafetyTab',6,'EPI→alerta não ligado nesta fase'),
('Agenda deduplica colegas/omite Gestão; today UTC permanece','ESTÁTICO','src/calendar.js:25;N-ADM-08',10,'CRUD/participantes/notificações não ligados'),
('Salas e Agenda são entidades distintas; email não provado','ESTÁTICO','meeting-rooms;N-ADM-11',6,'Reservas/edição/alertas não integrados'),
('Imóvel tem anexos próprios e dependência de empresa','ESTÁTICO','src/properties.js',7,'CRUD e múltiplas associações não exercitados'),
('Versão de pedido não é contrato nem MQT','ESTÁTICO','src/budget-requests.js',5,'Pedido→PDF→contrato não definido nesta cadeia'),
('Configuração possui helpers admin que agrupam Gerência','ESTÁTICO','src/settings.js;N-SEC-03',4,'CRUD global de responsáveis/catálogo não executado'),
('Import fase protegido e lote RH fazem gravação controlada','CORRETO PARCIAL','FIN-CHAIN;RH7-BATCH',9,'Não comprova todos importadores/ordem de produção'),
]
axes=['1_interface_sem_writer','2_writer_sem_interface','3_leitor_erro_paginacao','4_permissoes_front_back','5_estados_relatorios','6_regressao_representativa','7_parcialidade','8_legado_ativo','9_branch_nao_integrada','10_doc_obsoleta']
coverage=[];missing=[]
for idx,(claim,status,proof,axis,limit) in enumerate(focus):
 a=areas[idx];row=dict(area_id=idx+1,area=a['modulo'],conclusao_focada=claim,classificacao=status,evidencia_codigo=a['evidencia'],prova=proof,limite=limit)
 for k in axes:row[k]='NÃO INVESTIGADO NESTA FASE; NÃO É PASS'
 row[axes[axis-1]]=status+' — '+proof;coverage.append(row)
 missing.append(dict(area=a['modulo'],lacuna=limit,criterio_aceitacao='Ligar a ação referida ao writer real, histórico e consumidor; falhas sem efeito indevido; preservar tenant/revisão',teste_existente_para_reusar=a['testes_existentes_exemplos'],fonte=a['evidencia'],estado='NÃO EXECUTADO; NÃO É SKIP DE SUITE',prioridade='P1' if idx+1 in [10,14,15,26] else 'P2/P3 conforme risco'))
csvout('FASE-4/COBERTURA-38-AREAS.csv',coverage);csvout('FASE-4/TESTES-EM-FALTA.csv',missing)
# Critical operations; view availability is never substituted for backend permission.
ops=[
('LOGIN','Sessão','signIn','src/supabase-browser.js','export async function signIn','Auth/login','token/sessão','session-boundary','settings',None),
('INVOICE_CREATE','Faturas','form submit','src/app.js','form.addEventListener("submit", async','POST faturas+itens','draft/artigos','Fase2N2-FIN-01','finance','insertInvoices'),
('INVOICE_APPROVE','Faturas','advanceInvoiceFlow','src/app.js','async function advanceInvoiceFlow','fn_avancar_estado_fluxo_fatura','aprovação/estado','Fase1 contratos','invoices','approveInvoices'),
('INVOICE_PAY','Financeiro','canPayInvoices','src/app.js','function canPayInvoices','fn_marcar_fatura_paga','pago/eventos','Fase1 SQL','finance','payInvoices'),
('WORK_EDIT','Obras','canEditWork','src/app.js','function canEditWork','PATCH/RPC conforme ação','obra/revisão','capabilities frontend','works','editWork'),
('CUSTOMER_CREATE','Faturação','submitBilling','src/app.js','async function submitBilling','POST faturacao/links','draft/pendente','FIN-CHAIN','works',None),
('CUSTOMER_DECIDE','Faturação','decidir','src/app.js','rpc/fn_decidir_faturacao_auto','fn_decidir_faturacao_auto','emitida/recusada','FIN-CHAIN auth stubs','works',None),
('CUSTOMER_RECEIVE','Recebimento','openPaymentDialog','src/app.js','function openPaymentDialog','fn_marcar_faturacao_auto_paga','recebido/pago','FIN-CONSUMERS','works',None),
('PARTIAL_RPC','Recebimento','SEM INTERFACE','src/app.js','rpc/fn_marcar_faturacao_auto_paga','fn_registar_recebimento_parcial','movimentos/replay','Fase2 parciais','works',None),
('BUDGET_IMPORT','MQT','import','src/xlsx-operational-import.js','fn_importar_orcamento_fases','fn_importar_orcamento_fases','fase/valores','FIN-CHAIN','works',None),
('PLAN_BATCH','Planeamento','requestPlanningBatch','src/planning-batch.js','requestPlanningBatch','fn_guardar_planeamento_lote','preview/changes','planning-operational','planning',None),
('TASK_REPORT','PlanoAção','report','src/action-plan.js','task_report','fn_folha_gestao_v2 task_report','reported/alertas','TASK-CHAIN','action-plan',None),
('TASK_CONFIRM','Planeamento','conclusão e trigger automático','src/planning.js','function captureInput(input)','folha_privado.tarefa_concluida; task_confirm alternativo','confirmed/alertas','TASK-ROLES','planning',None),
('TEAM_MOVE','Equipa','transfer','src/attendance-sheet.js','team_transfer','fn_equipa_operar_v2','membership/história','native299','team',None),
('POINT_SAVE','Folha','plan','src/attendance-hours-client.js','fn_folha_plano_integrado_v3','fn_folha_plano_integrado_v3','factos/revisão','RH-CHAIN/TENANT','team',None),
('ABSENCE_REPORT','FALTOU','reportFaltou','src/attendance-hours-client.js','reportFaltou','fn_folha_faltou_v2','neutro/sem horas','RH-FALTOU','team',None),
('ABSENCE_CLASSIFY','Ausências','classify','src/attendance-hours-client.js','classify','fn_folha_faltou_v2','classificação/autor','RH-FALTOU','team',None),
('MONTHLY','Conferência','month','src/attendance-hours-client.js','confer','fn_folha_conferencia_v3','conferida/devolvida','native MONTHLY','team',None),
('RATE_APPROVE','RH tarifa','rate','src/attendance-hours-client.js','fn_folha_custo_hora','fn_folha_custo_hora_v3','vigência/autor','native cost-map','team',None),
('AGG_READ','Custos horas','operationalMap','src/attendance-hours-client.js','operationalMap','fn_folha_custos_operacionais_contexto_v3','agregado/pending','HR29;HR38 aberto','team',None),
('RH_READ','RH','open','src/rh-cadastro.js','fn_rh_consultar','fn_rh_consultar','cadastro/contrato','RH7-ROLES','team',None),
('RH_IMPORT','RH','import','src/rh-cadastro.js','fn_rh_importar','fn_rh_importar','preview/erros/audit','RH7-BATCH/ROLES','team',None),
('MEDICINE','Medicina','consultar','src/medicine.js','fn_medicina_consultar_colaborador','fn_medicina_consultar_colaborador','aptidão/validade','Fase1 nativo','team',None),
('VEHICLE','Viaturas','assign','src/vehicle-assignment.js','fn_','fn_alterar_responsavel_viatura','atribuição/história','Fase1 nativo','vehicles',None),
('DOCUMENT','Documentos','submitUpload','src/documents.js','async function submitUpload','Storage+documentos_obra','pendente/associado','N-DOC-01','documents',None),
('DOWNLOAD','Documentos','download','src/supabase-browser.js','export async function downloadWorkDocument','Storage privado','blob/epoch','session-boundary','documents',None),
('CONSULT_CREATE','Compras','form','src/procurement.js','rpc/fn_criar_consulta','fn_criar_consulta_planeamento','consulta/itens','pending-consultations','works',None),
('PRICE_SAVE','Compras','saveCandidate','src/procurement.js','async function saveCandidate','fn_guardar_precos_candidato_subempreitada','preços/proposta','PUR-INTERRUPTED','works',None),
('AWARD','Compras','adjudicar','src/procurement.js','rpc/fn_adjudicar_candidato_subempreitada','fn_adjudicar_candidato_subempreitada','subempreitada/plan','SQL não executado','works',None),
('COMPARATIVE_DELETE','Comparativo','eliminar','src/comparative-map.js','rpc/fn_eliminar_mapa_comparativo','fn_eliminar_mapa_comparativo','cascade/confirm','Fase1 testes','works',None),
('ALERT_RESOLVE','Alertas','resolveAlert','src/production-dashboard.js','async function resolveAlert','fn_resolver_alerta','resolvido/autor','TASK-CHAIN via confirm','overview',None),
('RNC_CREATE','RNC','canCreate','src/rnc.js','const canCreate','fn_criar_rnc','aberto/evidências','N-ADM-07','rnc',None),
]
caps=json.loads((R/'FASE-5/EVIDENCIAS-CAPABILITIES.json').read_text())['results'];actions=[]
for key,module,fn,file,needle,backend,states,proof,view,cap in ops:
 for cr in caps:
  role=cr['role'];status='REVISÃO ESTÁTICA; PAR BACKEND NÃO EXECUTADO';auth='Não inferir escrita da vista';allowed='NÃO INFERIDO'
  if cap:status='CAPABILITY FRONTEND TESTADA; BACKEND NÃO CERTIFICADO';allowed=str(cr[cap]);auth='accessFor propriedade '+cap
  if key in ['RH_READ','RH_IMPORT']:
   status='PERMISSÃO DB TESTADA';allowed=str(role in (['gestao_plataforma','gerencia','administrativo'] if key=='RH_READ' else ['gestao_plataforma']));auth='fn_rh_empresa(false/true);ativo/empresa;RH7-ROLES'
  if key=='TASK_REPORT' and role=='encarregado':status='TRANSIÇÃO DB TESTADA';allowed='True';auth='obra;funcao encarregado;ativo'
  if key=='TASK_CONFIRM' and role in ['diretor_obra','adjunto','preparador']:status='PERMISSÃO/TRANSIÇÃO DB TESTADA';allowed=str(role!='preparador');auth='role;reported+plan concluído;revisão'
  if key=='POINT_SAVE' and role=='administrativo':status='TRANSIÇÃO DB TESTADA';allowed='True';auth='ator/tenant/revisões;RH-CHAIN'
  actions.append(dict(acao=key,modulo=module,perfil=role,vista_disponivel=str(view in cr['views']),capacidade_avaliada=allowed,componente_funcao=file+' '+fn,ponto=location(file,needle),contrato=backend,autorizacao=auth,ambito='empresa/obra conforme contrato; catálogo não consultado',entrada_saida=states,dependencias='migrations/ACL/Storage; não instalar',estados=states,historico='Referido no SQL/RPC; certificado apenas nas provas específicas',erro='Ver cliente referido; não certificado para cada perfil',teste_evidencia=proof,verificacao=status,limite='Vista não prova grant; sem Auth hospedado'))
csvout('FASE-5/MATRIZ-ACOES-PERFIS.csv',actions)
traces=[]
for r in refs:
 file=r['ficheiro'];line=int(r['linha']);src=Path(file).read_text(encoding='utf-8-sig').splitlines();context=src[line-1][:240] if line<=len(src) else 'REFERÊNCIA FORA DO FICHEIRO'
 traces.append(dict(ficheiro=file,linha=line,tipo=r['tipo'],endpoint=r['objeto'],contexto_codigo=context,contrato_local='SQL indexado' if r['tipo']=='RPC' else 'Tabela REST; verificar grants/RLS',entrada_saida='Payload/projection no código; não inferidos por nome',estado='RASTREABILIDADE ESTÁTICA; EXECUÇÃO NÃO CERTIFICADA',evidencia=r['limite']))
csvout('FASE-5/RASTREABILIDADE-FRONTEND-BACKEND.csv',traces)
sel=json.loads((R/'FASE-5/ENTRADAS-LEXICAIS.json').read_text())['entries'];csvout('FASE-5/FILA-PONTOS-DE-ENTRADA.csv',sel)
relations=[
('obras','contratos','obra_id','Contrato/vigência explícitos','Heurística N-FIN-07','FIN-MAPS'),
('fases','orcamento_fases','fase_id/obra_id','Fase e alvo locked','Import protege alvo incoerente','FIN-CHAIN'),
('fases','itens_orcamento','fase_id','Artigo MQT','TEE→auto granular não provado','N-FIN-10'),
('fases','planeamento_itens','fase_id','Pesos/progresso/datas','Não normalizar pesos automaticamente','planning-operational'),
('alteracoes_tee','planeamento_itens','tee_id','Aprovação sincroniza tarefa','Recusa mantém tarefa','FIN-TEE-CONSUMERS'),
('alteracoes_tee','previsao_financeira_mensal','obra_id+mes início','Compromisso preco_custo','IVA/distribuição Q08/09','FIN-CLOSED'),
('alteracoes_tee_itens','autos_medicao','PONTE NÃO COMPROVADA','Não inventar FK','Granularidade Q16','REVISAO'),
('autos_medicao','faturacao_autos_medicao','auto_medicao_id','Auto único no schema histórico','Falha deixa draft órfão','FIN-CHAIN/Fase2'),
('faturacao','faturacao_autos_medicao','faturacao_id','Cabeçalho/links','HTTP não atómico','N-FIN-01'),
('faturacao','faturacao_recebimentos','faturacao_id','Parcela/total agregado','Writer antigo diverge','N2-FIN-02/03'),
('contratos','autos_medicao','obra/dedução adiantamento','Advance contratual não é caixa','Nome faturado ambíguo','FIN-DRAFT'),
('documentos','Storage/entidade','url+tipo+entidade_id','Metadata e bytes separados','Integridade real não provada','DOC-MISSING hipótese'),
('fornecedores','consultas_subempreitada_candidatos','fornecedor_id','Identidade fornecedor','Nome não basta','N-FOR-04'),
('consultas_subempreitada','consultas_subempreitada_itens / consultas_subempreitada_candidatos','consulta_id/item_orcamento_id','Consulta/proposta','Contexto A/B trocado','TEMP-P3-C01'),
('mapas_comparativos','comparativo_itens_precos','item_id+proposta_id','Cotação comparável','Menor não é adjudicado','PUR-CONCEPTS'),
('subempreitadas','planeamento_itens','planeamento_item_id/trigger','Adjudicação/vínculo','Preço separado da adjudicação','PUR-INTERRUPTED'),
('faturas','faturas_itens','fatura_id','Documento fornecedor/itens','Cabeçalho sem artigos','N2-FIN-01'),
('faturas','subempreitadas','subempreitada_id+fornecedor/obra','Vínculo validado por RPC','Não inferir por texto','src/app.js:1109'),
('colaboradores','colaboradores_contratos','colaborador_id','Cargo formal/contrato','Login separado','RH7-CADASTRO'),
('utilizadores','colaboradores','utilizador_id','Ligação RH explícita','Não inferir por nome','AD03 preservado'),
('colaboradores','quadro_equipa_permanencias','colaborador/obra/inicio/fim','Equipa operacional','Técnico sem permanência fictícia','RH-CHAIN'),
('colaboradores','folha_registos','colaborador/data/obra','Factos laborais','Correção preserva referência','RH-CHAIN'),
('colaboradores','ausencias','colaborador/data/estado','Neutro→Admin classifica','Não inventar horas','RH-FALTOU'),
('folha_registos','folha_avaliacoes_diarias','colaborador/data/revisão','Referência histórica','Unknown permanece pendente','native299'),
('folha_avaliacoes_diarias','folha_conferencias_mensais','colaborador/mês/snapshot','Factos atuais','Não equivale a payroll','RH-CHAIN'),
('folha_custos_hora_versoes','mapas/HR29','pessoa/vigência/revisão','Tarifa RH confidencial','HR38 inferência; padrão não implementado','HR38 preservado'),
('planeamento_itens','folha_tarefas_reportes','tarefa_id/revisão','Reporte→confirmação','Exige Planeamento concluído','TASK-CHAIN'),
('folha_tarefas_reportes','alertas','entidade/obra/empresa/destinatário','Notificação de reporte','Replay não duplica; confirmação resolve','TASK-CHAIN'),
('folha_externos','relatório/Excel','externo_id/obra/provider','Modelo externo separado','Sem salário/HE internos','native299 HR30'),
('viaturas','viaturas_atribuicoes_historico','viatura/colaborador/revisão','Atribuição autorizada','Saída RH concorrente','Fase1 nativo'),
]
csvout('FASE-6/MATRIZ-FONTES-DE-VERDADE.csv',[dict(origem=a,destino=b,chave=c,fonte_verdade=d,risco=e,evidencia=f,estado='CÓDIGO/TESTES; NÃO CATÁLOGO REAL')for a,b,c,d,e,f in relations])
graph=json.loads((R/'FASE-6/GRAFO-SQL-LEXICAL.json').read_text());group={}
for d in graph['definitions']:group.setdefault(d['function'],[]).append(d)
conflicts=[]
for fn,items in group.items():
 if len(items)>1:
  for d in items:conflicts.append(dict(funcao=fn,ficheiro=d['file'],linha=d['line'],sha256_texto_git=d['definition_sha256'],security_definer=d['security_definer'],search_path=d['search_path'],ocorrencias_nome=len(items),natureza='HISTÓRICO/RESTAURO/CHECK' if d['historical_or_restore'] else 'DEFINIÇÃO CANDIDATA',owner_acl='Ler ALTER/REVOKE/GRANT; instalação não inferida',risco='Ordem pode substituir contrato; sobrecargas/pg_depend não certificados',decisao='Manifest proposto; não baseline por ordem alfabética'))
csvout('FASE-6/MIGRATIONS-CONFLITOS.csv',conflicts)
resilience=[
('Preview cancelado','RH/Planeamento','PASS','RH-CHAIN;planning-operational','Sem factos após preview'),
('Duas sessões','Folha/plano','PASS','native299','Mesmo request replay; stale rejeitado'),
('Mesmo request','Folha/FALTOU/tarefas','PASS','TASK-CHAIN;native299','Uma operação/história'),
('Revisão stale','RH/tarefas','PASS','TASK-ROLES','40001/revisão preservada'),
('Falha entre escritas','Financeiro','VULNERABILIDADE ANTERIOR','Fase2N-FIN-01/N2-FIN-01','Consumidores novos; não repetir causa'),
('Resposta perdida','Clientes/sessão','PASS SESSÃO;FALHA FINANCEIRA ANTERIOR','session-boundary;Fase2','Não inventar recovery'),
('Troca sessão','Auth/Storage','PASS','session-boundary7','Resposta/body antigos AbortError'),
('Revogação','RH/tarefa','PASS','RH-REVOKE;native299','42501 sem factos'),
('Documento inexistente','Financeiro','HIPÓTESE POR VERIFICAR','DOC-MISSING','Fixture sem trigger não prova produto'),
('Troca obra','Compras','FALHA COMPROVADA','TEMP-P3-C01','ContextoB/dados A'),
('Troca empresa','Folha','PASS','RH-TENANT;native299','Rollback total'),
('Restauro permitido','Migrations','PASS NA FIXTURE','MIG-ORDER;native lifecycles','Rollback policy; após uso fail-closed'),
('Referência garantia','Horas','PASS SUITE EXECUTADA','native299 REFERENCES','Sobreposição/revisão preservadas'),
('Linha tardia inválida','RH import','PASS','RH7-BATCH','Alterações/audit rollback total'),
('Adjudicação falhada','Compras','OBSERVADO / UX','PUR-INTERRUPTED','Preço gravado; adjudicação não'),
('Preço sem origem','Compras','FALHA REPRODUZIDA','TEMP-P3-C02','Sem aviso de incompletude'),
('HTML','Documentos/mensagem','VULNERABILIDADE ANTERIOR','Fase2HTML','Sem nova técnica de exploração'),
('Oito perfis RH','Cadastro/import','PASS','RH7-ROLES','Read Admin/Gerência/Gestão; import Gestão'),
('Oito perfis frontend','Faturas/obra','PASS FRONTEND','FASE-5/EVIDENCIAS-CAPABILITIES.json','32 booleans; grants separados'),
]
csvout('FASE-7/MATRIZ-TESTES-ADVERSARIAIS.csv',[dict(cenario=a,modulos=b,resultado=c,prova=d,criterio=e,correcao='NENHUMA',ambiente='SINTÉTICO/ESTÁTICO',limite='Resultado de diagnóstico não é aprovação de segurança')for a,b,c,d,e in resilience])
csvout('FASE-7/REGRESSOES-EM-FALTA.csv',[dict(area=x['area'],lacuna=x['lacuna'],evidencia=x['fonte'],cenario_necessario=x['criterio_aceitacao'],estado=x['estado'],restricao='Sem credenciais/dados reais nesta missão')for x in missing])
consolidated=[]
for r in prior:consolidated.append(dict(codigo_existente=r['id'],id_temporario='',modulo=r['dominio'],problema=r['descricao_especifica'],evidencia=r['evidencia']+';'+r['evidencia_fase2'],estado=r['estado']+' — PRESERVADO; NÃO CORRIGIDO NESTA MISSÃO',prioridade=r['prioridade'],dependencias=r['dependencias_limites'],criterio_aceitacao=r['criterios_aceitacao']))
for n in new:consolidated.append(dict(codigo_existente=n['codigo_existente_correspondencia'],id_temporario=n['id_temporario'],modulo=n['modulo'],problema=n['problema'],evidencia=n['evidencia'],estado=n['estado'],prioridade=n['prioridade'],dependencias=n['dependencias'],criterio_aceitacao=n['aceitacao']))
for temp,orig,desc in [('N2-FIN-01','N-FIN-01','Fornecedor sem artigos após falha; formulário limpo'),('N2-FIN-02','N-FIN-05','Mistura de APIs diverge ledger/cabeçalho'),('N2-FIN-03','N-FIN-05','Acumulado recebido desloca caixa para último mês')]:consolidated.append(dict(codigo_existente=orig,id_temporario=temp,modulo='Financeiro',problema=desc,evidencia='FASE-2/EVIDENCIAS-FINANCEIRO.json',estado='FALHA ANTERIOR PRESERVADA; NÃO CORRIGIDA',prioridade='P1',dependencias='Q04/Q05;Storage conforme origem',criterio_aceitacao='Fechar critérios do plano; sem compensação inferida'))
csvout('CONSOLIDACAO-PARA-BACKLOG.csv',consolidated)
counts={s:sum(r['verificacao']==s for r in actions)for s in sorted(set(r['verificacao']for r in actions))}
summary={'areas':38,'critical_actions':len(ops),'profile_action_pairs':len(actions),'profile_pair_status':counts,'lexical_entry_candidates':len(sel),'static_api_references':len(traces),'dollar_quoted_function_definitions':len(graph['definitions']),'qualified_call_edges':len(graph['edges']),'function_names_with_multiple_definitions':sum(len(v)>1 for v in group.values()),'conflict_csv_rows':len(conflicts),'e2e_records':len(rows),'new_discoveries':len(new),'consolidated_records':len(consolidated),'complete_functional_coverage_claimed':False}
(R/'CONTAGENS-MATRIZES.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(summary,ensure_ascii=False))
# Phase 3 narratives use the actual observed evidence, not existence-only certification.
doc('FASE-3/FINANCEIRO-END-TO-END.md','''# Financeiro end-to-end

## Provas ligadas
FIN-CHAIN liga a RPC protegida de orçamento de fases a uma fase/obra sintética, TEE aprovado aos triggers de tarefa e previsão, handlers reais submitMeasurement/submitBilling a INSERTs PostgreSQL e decisão da fatura à RPC real. Orçamento2000; auto bruto1200 menos adiantamento200 produz1000; draft pendente passa a emitida após decisão.

**Limites importantes:** MQT→TEE é associação de fase, não reconciliação de artigos. Não foi encontrada/provada ponte granular TEE-itens→auto. A aprovação do auto foi semeada por UPDATE na fixture. Auth financeira foi permitida por stubs; esta suite verifica transições e consumidores, não ACL. Não chamar isto de processo completo do UI até à produção.

## Consumidores
Receber100 de1000 pela API antiga produz badge PAGO e esconde a ação de receber restante em renderMeasurementsTab, enquanto a Visão Geral por diferença ainda tem saldo900. É efeito de N-FIN-05, cuja causa já foi provada na Fase2. A RPC parcial preparada continua sem chamada no frontend deste checkpoint.

FIN-DRAFT: auto rascunho250 com avanço contratual200 resulta450 no helper chamado faturado, sem fatura emitida. FIN-MAPS executa buildRows real: valor efetivo zero cai no inicial; mês com entrada100 e saída com IVA123/semIVAzero resulta-23; caixa entrada100 continua100. Margem de mapa não é caixa; bases e nomes precisam Q05/06/08/10.

TEE300 e subempreitada500 com execução outubro/novembro entram integralmente no início: outubro800, um mês, mesmos totais sem/comIVA. Recusar TEE remove300 da previsão mas a tarefa persiste. Mês fechado não muda após alterar compromisso. N-FIN-06/08/09 preservados; não reescrever fórmulas por suposição.

## Integridade e futuro gate
Falhas entre cabeçalho/links/itens/Storage e replays financeiros da Fase2 preservados, sem repetir a exploração. Exigir transação BD, fonte de parcelas por data, recovery auditado de bytes, entidade/tenant comprovados, autorizações correntes, revisão e consumidores concordantes. Dados históricos sem parcelas não podem ser reconstruídos por inferência.

Evidência: EVIDENCIAS-FINANCEIRO.json; tests/night-phase3-finance.test.mjs. **9 PASS Node incluindo grupo; reprodução aprovada não significa produto seguro.** Nenhum valor real usado. NO-GO destes fluxos com P1 aberto.
''')
doc('FASE-3/ADMINISTRATIVO-RH-END-TO-END.md','''# Administrativo e RH end-to-end

## Cadeia executada
RH-CHAIN: cadastro/contrato semeados → team_add real → preview do plano sem factos → confirmar480min → relatório factual e conferência480 → corrigir240min → conferência240, histórico aumentado, zero Vencimentos criados. Cadastro nesta cadeia é fronteira de fixture, não UI completa.

RH7-CADASTRO complementa a fronteira numa segunda BD: fn_rh_guardar real chama criador do ficheiro colaboradores_campos_completos, cria alocação de escritório explicitamente fornecida, contrato sem termo, auditoria e leitura por fn_rh_consultar. Cargo formal Preparador não foi convertido em papel de login. O criador usado é versão identificada no Git; não representa baseline hospedada confirmada.

RH-FALTOU: equipa → ausência neutra pela RPC → mapa administrativo com mesmo UUID/proveniência → classificação com motivo → história mensal. Zero pontos/horas/saídas/faltas compensatórias inventados. Conferência é processo diferente de payroll.

## Resiliência
Preview cancelado não escreve; ator inativo após preview recusa42501; obra de outra empresa no plano recusa integralmente. Suite nativa cobre duas conexões, idempotência, stale, referência histórica, multiobra, externos, HE informativa, férias, leitores e rollback antes/depois de uso. AD13/14/15/03 preservados. Nada foi ativado na produção.

Lote RH: preview de duas linhas não altera; confirmação com segunda linha inexistente recusa e faz rollback de primeira mudança e auditoria. Repetição de mesmo conteúdo é no-op, não cache de request_id. Gestão importa; Gerência/Admin leem mas não importam; Financeiro/Diretor/Adjunto/Preparador/Encarregado não obtêm cadastro completo pelo contrato testado. Empresa estrangeira retorna0; inativo recusado.

## Limites
Medicina e Viaturas têm provas nativas anteriores preservadas; não foi construída nova cadeia completa cadastro→documento→Medicina→viatura→alerta nesta missão. Storage hospedado e Auth real não acessados. Exportador externo/HR30 e HR27/31 regredidos no harness; não introduzir HE monetária. FP28/29/horário/almoço/tolerância intactos.

Evidências: RESULTADO-RH-LOCAL.txt; EVIDENCIAS-RH-TAREFAS.json; FASE-7/EVIDENCIAS-RH-LOTE.json. O total final do harness consta no log e RESULTADOS-FASES-3-A-7.json; não somar reexecuções.
''')
doc('FASE-3/COMPRAS-EQUIPA-TECNICA.md','''# Compras e equipa técnica

## Compras: resultados novos
TEMP-P3-C01 (P2): loadA fica pendente; loadB altera state.work e retorna devido loading; respostaA preenche consultas e loadedWorkId=A, mas renderiza contexto B. Função real src/procurement.js:175–237 executada em VM. Não houve outra identidade/empresa nem prova de bypass RLS; existe risco de ações no alvo errado.

TEMP-P3-C02 (P2, N-FOR-05/02): as três consultas retornam200; header de fatura ausente e item presente. loadPriceRows produz preço sem fornecedor e priceError vazio. Falha de proveniência provada em fixture; ausência real por RLS/paginação não demonstrada. Queries não têm paginação visível; cap real desconhecido.

saveCandidate guarda proposta100 antes de adjudicação falhada; withButton mostra erro e reativa botão. Não é automaticamente corrupção: preço de proposta pode legitimamente existir sem adjudicação. Necessita indicação clara de etapa. Comparativo real: menor140/estimado160/adjudicado180/venda240 → negociação40/desvio20/margem60. Não tratar soma dos menores como preço adjudicado.

**Fronteira não concluída:** criação de fornecedor/consulta → adjudicação SQL → Storage/documentos → fatura não foi ligada integralmente em uma BD. Rastreabilidade do código identifica RPCs, vínculos e readers; nenhum PASS end-to-end integral foi atribuído a essa cadeia.

## Equipa técnica
Tarefa em execução → reporte do Encarregado → três alertas para responsáveis únicos → confirmação autorizada resolve alertas/história. Reporte não altera conclusão oficial. Adjunto confirma; Preparador não confirma; stale/replay após inativação recusados.

Há também ligação indireta correta: folha_privado.tarefa_concluida (folha_ponto_v2_gestao.sql:411–431) confirma reporte e resolve alertas quando Diretor/Adjunto/Gestão conclui a tarefa. Por isso ausência de literal task_confirm no frontend **não prova operação órfã**. A RPC explícita é alternativa; não criar botão novo nesta auditoria. Teste TASK-AUTO-CONFIRM verifica o trigger com ator válido; UPDATE oficial foi fronteira de fixture, sem executar batch completo de Planeamento.

Pesos/progressos/dependências têm13 regressões puras; não foi certificado que todos indicadores globais/reunião/MGO propagam automaticamente esta conclusão. HR29 permanece aprovado no âmbito; HR38 continua bloqueio de confidencialidade a mitigar, sem nova regra de limiar.
''')
doc('FASE-3/TESTES-RESILIENCIA.md','''# Resiliência — resultados e limites

336 contagens Node na primeira execução final dos três blocos, depois337 com o caso adicional do trigger automático:299 no harness RH,9 Financeiro,29 Compras/sessão/Planeamento. Considerar apenas337 finais; não somar reexecuções. Inclui grupos pai. Resultados posteriores das Fases5/7 são separados no JSON global.

Duas sessões, request igual, stale e cancelamento: corretos nos contratos Folha/Equipa/FALTOU do harness. Preview→inativação e alvo estrangeiro:42501/sem factos. Resposta REST/body/Storage antiga:AbortError após troca;403 não faz logout. Autorizações por responsabilidades/locks e referências garantia têm casos na suite preservada executada.

Obra A→B durante load de Compras: falha nova TEMP-P3-C01. Header de fatura ausente em consulta bem-sucedida: proveniência incompleta TEMP-P3-C02. Falhas de fatura/artigos/links/upload e resposta perdida já comprovadas na Fase2; consumidores foram testados agora, sem repetir as mesmas cargas.

Documento de entidade inexistente inserido na metadata **mínima da fixture**: hipótese, não falha de produto. Não se instalaram triggers integrais documentais nesse cluster. Recuperação de Storage e adjudicação completa não provadas.

Rollback de ordem SQL errada em transação local restabelece policy e leitura anterior. Rollbacks específicos antes de uso passam; após uso recusam drift/história nas suites. Não é autorização de rollback real.

Matriz transversal: FASE-7/MATRIZ-TESTES-ADVERSARIAIS.csv. PASS de reprodução é VULNERABILIDADE REPRODUZIDA/FALHA COMPROVADA na classificação, não fecho. Erros iniciais de bootstrap foram corrigidos só nas fixtures (comandos parametrizados separados, datas textuais de API, dependências/versão RH), sem alterar expectativas do produto.
''')
doc('FASE-3/MIGRATIONS-E-PUBLICACAO.md','''# Migrations e publicação — manifesto proposto

Ordem errada comprovada localmente: policy tenant simplificada → autos_faturacao_workflow.sql histórico → policy permissiva true passa a OR com a segura → authenticated lê linha fora do scope da fixture. Rollback da transação restaura policy/grants e leitura0. Não é reconstrução de catálogo real nem prova de exposição atual em produção.

575 declarações dollar-quoted/1.713 chamadas qualificadas no grafo novo;136 nomes com múltiplas definições e370 ocorrências de conflito. Diferem do inventário geral588/140 da Fase1 porque o scanner novo não cobre toda sintaxe, sobrecargas, SQL dinâmico ou pg_depend. Hashes são texto normalizado do Git, não fingerprints pg_get_functiondef. Seeds reais excluídos.

## Sequência proposta (não operacional)
1. Reconciliar catálogo/versionamento/grants reais numa tarefa futura read-only autorizada.
2. Distinguir scripts históricos, ativos, checks e rollback por assinatura/hash/owner/ACL.
3. Preservar cadeia FolhaV2→equipa persistente→fecho reconciliado→cutover CLOSED; preparar avaliação AD15→AD14→AD13→AD03 e extensões HR27/FALTOU/readers/mensal/destinos/plano/mapas segundo prechecks.
4. Financeiro/autos: hotfix tenant precede writers e compatibilidade de consumidores; scripts antigos permissivos não reaplicar.
5. DD-TENANT abc160d e FaseB b7bf4c1 são branches separadas; não integram esta base automaticamente.
6. Backup/migration/postcheck/rollback futuro exigem baseline concreta e autorização; Storage não é transação SQL.

Rollback histórico pode restaurar definição/permissão antiga; nunca executar em lote por nome/ordem alfabética. Após uso, guards atuais preservam referências/histórico. Ver grafo/risco detalhado na Fase6. Nenhum manifesto operacional alterado. Publicação NO-GO com P1 financeiro/HTML/HR38 aberto.
''')
doc('FASE-3/QUESTOES-PARA-DECISAO.md','''# Decisões da Fase3

Preservar Q01–20 da Fase2, sem perguntas durante a missão. HR27/30/31 e HR41 não reabertos. Custo-padrão HR38 só aprovado em princípio; fonte/aprovador/vigência continuam pendentes.

1. Recebimentos/saldo/estorno/excesso e nomenclatura de mapas: Q04/05, Financeiro. Reutilizar RPC parcial existente e movimentos por data; não reconciliar legado por inferência.
2. TEE recusado depois de tarefa/execução: Q07, Planeamento/Financeiro. Preservar factos e definir autorização futura.
3. IVA, zero versus desconhecido, vigência e distribuição mensal: Q06/08/09/10. Não alterar fórmulas sem contrato.
4. Preços guardados antes de adjudicação falhada: propor etapa explícita com retry seguro; não presumir que guardar cotação deve ser revertido. Módulos Compras/Comparativo.
5. Falhas TEMP-P3-C01/02 são técnicas: invalidar resposta por obra e identificar origem incompleta, sem nova permissão comercial. Correção apenas noutra tarefa autorizada.
6. Storage recovery/retensão e PDF obrigatório: Q19; associação comprovada e trilho preservado antes de eliminar bytes.

Obra128/preços Encarregado continuam futuros contratos Q11–16; nenhum preço/margem/capability inferido.
''')
doc('FASE-3/RESUMO-PARA-CHATGPT.md','''# Resumo Fase3

Circuitos executados com fronteiras explícitas,20 linhas na matriz.337 contagens finais Node:299 RH/tarefas,9 Financeiro,29 Compras/sessão/Planeamento. Sem produto/produção alterados.

Novos TEMP-P3-C01/02: resposta de consultas da obra A persiste sob contexto B; preço sem header não sinaliza origem incompleta. P2 propostos, sem códigos oficiais novos. Financeiro confirma efeitos dos P1 anteriores nos consumidores e diferença de conceitos entre mapas. RH/FALTOU/conferência/edição/tenant/revogação preservados. Trigger de conclusão autorizada confirma reporte/alertas; task_confirm não é necessariamente órfã.

Compras→adjudicação SQL→documentos→fatura completa, Auth hosted, catálogo e triggers documentais reais não certificados. Seeds/RPC stubs explicitados; não declarar E2E integral nestas fronteiras. NO-GO dos circuitos bloqueados; decisões na secção própria. Ver evidências JSON e FASE-7 para regressões posteriores.
''')
doc('FASE-4/INTERFACES-WRITERS-LEITORES.md','''# Interfaces, writers e leitores

38 áreas reconciliadas com dez eixos de cobertura. Uma conclusão focada por área; os outros eixos não exercitados estão explicitamente NÃO INVESTIGADO. **Não são380 verificações funcionais aprovadas.** Não repetimos apenas a lista de módulos: cada linha aponta falha/estado/limite e teste necessário.

Novos caminhos úteis: consultas load por obra tem race; preço sem header perde proveniência; conclusão de Planeamento possui trigger indireto de confirmação (não precisa literal task_confirm). RPC parcial de recebimentos tem contrato no SQL mas a UI usa writer antigo. Cadastro RH chama criação/alocação/contrato e auditoria; import rejeita lote integralmente em erro.

520 atributos data-* distintos por ficheiro são candidatos de entrada, incluindo estado/decoração. Não equivalem a520 ações. FILA-PONTOS-DE-ENTRADA.csv na Fase5 preserva todos para revisão.218 referências REST/RPC estão ligadas a linha/contexto, mas nomes e menus não provam funcionamento integral.

32 operações críticas/256 pares de perfil na Fase5:32 capabilities frontend executadas,21 pares com prova DB,203 pares backend não executados. Os números são do universo crítico delimitado, não todas ações da aplicação. Escritores/leitores de módulos não integrados continuam nas lacunas, sem falso PASS.
''')
doc('FASE-4/COBERTURA-POR-PERFIL.md','''# Cobertura por perfil

Oito papéis reais: gestao_plataforma,gerencia,administrativo,financeiro,diretor_obra,adjunto,preparador,encarregado. Cargo RH não deriva o papel. Gestão superutilizador funcional mantém tenant/revisão/auditoria; Gerência separada.

Frontend accessFor executado para oito perfis, com quatro booleans financeiros/obra por perfil. Ações de faturas de fornecedor seguem esse gate, mas grants/SQL reais não foram certificados por este teste.

Cadastro RH nativo: Gestão/Gerência/Admin leem; apenas Gestão importa Excel; os outros cinco perfis não leem cadastro completo. Usuário inativo recusado; outra empresa retorna0. Folha/tarefas: Admin confirma plano, Encarregado reporta, Diretor/Adjunto validam, Preparador não confirma tarefa. Demais contratos específicos têm provas no harness, não foi certificada toda matriz de operações.

Financeiro monetário usa stubs de autorização; isso não prova acesso econômico entre empresas. Médico/viaturas têm suites anteriores, não UAT nova. HR29 autorizado para técnicos segue intacto; HR38 permanece P1. Quadro do Encarregado não ganhou escrita.
''')
doc('FASE-4/DIVERGENCIAS-DOCUMENTACAO.md','''# Divergências e documentação

1. Fase1 descreve a ponte TEE→Auto em diagrama como sequência de negócio. Nesta fase não foi provada FK/reconciliação granular por artigo. Tratar a seta como intenção/processo conceitual, não contrato técnico implementado.
2. Inventário Fase1 dizia não encontrar ledger no fluxo. Fase2 encontrou fn_registar_recebimento_parcial/faturacao_recebimentos no SQL; a UI continua usando a antiga. Preservar história e atualizar interpretação, sem editar relatórios anteriores.
3. Ausência de literal task_confirm no frontend não é UI ausente: trigger tarefa_concluida implementa a confirmação indireta quando ator autorizado conclui no Planeamento.
4. Relatório RH23/09 antigo tem lacunas já implementadas, N-ADM-10. Não convertê-lo automaticamente em novos requisitos.
5. Histórico de produção informado: assets63/63 e smoke leituraPASS, writerCLOSED. Esta auditoria não reabre esses resultados nem verifica novo deploy. Gestão de Horas desta base é candidato local; não presumir publicado.
6. Débitos/FaseB estão preparados em outras branches; precheck anteriorPASS não significa migration instalada/autorizada.
7. Contagens de scanners diferem por método;588 ocorrências antigas e575 funções dollar-quoted não são objetos instalados. MJS/suites/filecounts não representam cobertura funcional.

Nenhuma documentação histórica apagada ou sobrescrita. Novas conclusões remetem à evidência atual.
''')
doc('FASE-4/RESUMO-FINAL.md','''# Resumo Fase4

Entregue matriz das38 áreas e38 lacunas específicas. Cobertura transversal realizada como revisão focada, **não E2E completo das38 áreas**. Matriz separa falha anterior/nova, comportamento correto parcial, hipótese e não investigado em cada eixo.

Prioridades: races de consultas/origem de preços; P1 financeiros/HTML anteriores; falta de fonte padrãoHR38; cadeias incompletas de adjudicação/documentos/relatórios; grants/manifest. Medicina, Viaturas, RNC, Salas, Agenda, Imóveis e Pedidos têm contratos/indexes revisados, mas nova cadeia completa não certificada. Próxima tarefa deve escolher a lacuna concreta antes de implementar.

Nada funcional alterado; sem produção. Fases5–7 aprofundam pontos críticos e mostram denominadores de cobertura, não certificação integral.
''')
doc('FASE-5/BACKEND-SEM-INTERFACE.md','''# Backend sem referência direta de interface

256 nomes públicos no scanner;132 não têm literal correspondente nos src. É correlação estática, não132 funcionalidades órfãs. Pode haver trigger, rotina automática, helper privado, overload, SQL dinâmico, job, contrato futuro ou legado. BACKEND-CANDIDATOS.json conserva candidatos e definições.

## Casos relevantes reconciliados
- fn_registar_recebimento_parcial: definição no hotfix e provas locais; nenhuma chamada nos src. Writer antigo usado no diálogo. Contrato preparado desconectado, ligado a N-FIN-05; não ligar silenciosamente.
- task_confirm explícito: cliente genérico poderia chamar, mas ponto direto não encontrado. **Existe trigger tarefa_concluida** que confirma/recolhe alertas quando Planeamento conclui autorizado. Não é órfão nem motivo de nova UI automática.
- fn_atualizar_tarefa_encarregado e fn_guardar_ponto_obra: vias antigas substituídas/revogadas pelos fluxos V2. Não classificá-las como funcionalidades atuais a reativar.
- Helpers folha_privado e funções de trigger não precisam UI nem EXECUTE externo. Grants privados negados nos testes nativos.
- Rotinas de alerta/email precisam job/integração externa não inspecionada; enviar_email não prova entrega.
- Débitos tenant-safe/FaseB/HR38 padrão operacional: branches/futuro ou decisão, não produto integrado nesta base.

Critério para chamar órfão confirmado: percurso previsto não tem interface/caller indireto legítimo, assinatura e instalação comprovadas, requisito aprovado. Esse critério não foi aplicado automaticamente ao132.
''')
doc('FASE-5/INTERFACES-SEM-CONTRATO.md','''# Interfaces sem contrato completo

A fila520 data-* inclui metadados e decoração; handler_candidate é apenas dataset/closest no mesmo ficheiro. Eventos delegados/importados podem estar noutro componente. Não é prova automática de botão sem writer.

## Comprovado ou preservado
- Gestão em RNC: gate canCreate exclui Gestão, N-ADM-07 já demonstrado; regra superutilizador existe. Não mudar permissões nesta missão.
- Fatura fornecedor pode limpar formulário depois de artigos falhados, N2-FIN-01. A ação possui writer, mas confirmação funcional incompleta.
- Cliente financeiro marcaPAGO e retira ação após100/1000; overview mantém saldo. Writer não suporta o contrato de parcial da interface.
- Consulta mudou de contexto durante load; ação pode referir alvo anterior. Precisa invalidar response/contexto, não ampliar autorização.
- Doc genérico sem entidade existente: apenas hipótese em fixture sem trigger. Não afirmar que Storage real aceita.

## Intencionais e desconhecidos
FP28/29, calendário clicável, HE monetária, custos-padrãoHR38, nova consulta de preços do Encarregado não implementados/aprovados. Não são automaticamente bugs de botões.

203 pares críticos backend não executados permanecem explicitamente na matriz. CRUD completo de Imóveis/Salas/RNC/Pedidos e adjudicação/doc/fatura integrado estão no CSV de regressões. Não afirmar fecho desses módulos.
''')
doc('FASE-5/PERMISSOES-ADVERSARIAIS.md','''# Permissões defensivas por perfil

Provas sintéticas, sem SQL hospedado e sem técnicas novas de exploração. Oito papéis reais preservados.

RH7-ROLES executa reader/import como authenticated, com auth.uid de fixture e utilizadores ativos por empresa. Gestão/Gerência/Admin leem; só Gestão importa; Financeiro/técnicos/Encarregado não recebem cadastro RH completo; outra empresa retorna0; inativo rejeitado. Cadastro/import usam fn_rh_empresa, independente de helperadmin legado.

Folha/harness: caller/tenant/obra e revisões; ator inativo após lock e mudança de empresa recusados; mesma request concorrente idempotente; outra obra/empresa recusa sem parcial. TASK-ROLES: Adjunto confirma; Preparador não; revisão antiga e replay revogado recusados. ROLE financeiro monetário não foi testado por esta suite: helpers foram stubs permitidos.

Frontend8: insertInvoices,approveInvoices,payInvoices,editWork seguem accessFor; Encarregado não se torna Gerência com isAdmin=true. Teste de booleans não certifica backend. Quadro mantém leitura do Encarregado; não concedemos tarifa/preços/custos novos.

JWT/Auth hospedado e identidade inválida criptográfica não exercitados nesta extensão; testes de troca/401/403 usam respostas sintéticas. A prova PostgREST anterior permanece histórica, não novo resultado. Não marcar estes itens PASS ou BLOQUEADO por proteção inexistente; são NÃO EXECUTADOS/fora da missão real.

Não encontrado bloqueio de segurança essencial nos testes locais concluídos. Qualquer lacuna de fixture/contrato está separada da proibição de produção.
''')
doc('FASE-5/COBERTURA-E-LIMITACOES.md','''# Cobertura reconciliada

Universos distintos:
-32 operações críticas identificadas →256 pares com oito perfis.
-32 pares executaram capability frontend apenas.
-21 pares possuem prova DB de autorização/transição (16 RH reader/import,3 taskconfirm,1 taskreport,1 planosave).
-203 pares ficaram em revisão estática, sem execução backend.
-520 candidatos data-* e218 referências estáticas API; não equivalem a operações completas.
-256 nomes públicos de funções no scanner;132 sem literal frontend, não necessariamente órfãos.

**Não declarar cobertura completa de ações/perfis.** Catálogo/Auth/Storage hospedados proibidos; nenhuma credencial. Falta de execução local está explicitamente NÃO INVESTIGADO, não SKIP fictício. Zero suítes finais SKIP; isso não significa todas ações executadas.

CadastroRH writer e contrato da criação foram exercitados em outro cluster que a Folha; não apresentar como uma única transação ponta-a-ponta. Criador do RH extraído de colaboradores_campos_completos e helperauth da fixture identificados. Medicina/Viaturas conservam prova anterior, sem nova cadeia completa.

MATRIZ-ACOES-PERFIS liga componente/função/linha, contrato, entrada/saída, escopo, estado, história, erro e evidência; campos não certificados assim o dizem. Provas em fonte real não significam instalação real.
''')
doc('FASE-5/DESCOBERTAS.md','''# Descobertas Fase5

Sem novos códigos oficiais. TEMP-P3-C01/C02 preservados como dois problemas novos locais; P1 anteriores permanecem abertos.

A análise bidirecional evitou falso positivo: task_confirm sem literalUI tem trigger indireto funcional e testado. RPC parcial está preparada e desconectada do diálogo; isso amplia a importância de integrar um contrato único, não cria autorização nova.

Matriz8 distingue Gestão/Gerência/Admin e Financeiro; RH7 confirma papéis restritos. HR41 ajustes confidenciais aprovados ao Administrativo autorizado não foram reduzidos. HR38 padrão só princípio: fonte, aprovador e vigência por decidir. Não implementar min-workers/ocultação ou usar cargoformal como login.

Lacunas concretas: adjudicação integrada, origem/paginação preços, propriedade/contexto empresarial, cadeia documentária, indicadores globais e UAT Auth hospedado. Não há prova de novo P0 nem certificação de ausência de P0/P1 no restante.
''')
doc('FASE-6/GRAFO-DEPENDENCIAS.md','''# Grafo de dependências e fontes

MATRIZ-FONTES-DE-VERDADE contém30 relações críticas com chave, origem, risco e prova. Nomes abreviados de consumidor não são FK inventadas. GRAFO-SQL-LEXICAL.json contém575 declarações,1.713 chamadas qualificadas e2.020 candidatosDDL (table/view/trigger/policy/schema/index/alter/grant/revoke/constraint). Trata sintaxe textual, não pg_depend instalado; SQL dinâmico/sobrecargas e statements multiline exigem revisão.

```mermaid
flowchart LR
 F[fases / MQT] -->|fase_id| P[planeamento_itens]
 F -->|fase_id e obra_id| O[orcamento_fases]
 T[alteracoes_tee] -->|tee_id trigger| P
 T -->|obra e mês inicial| PREV[previsao_financeira_mensal]
 A[autos_medicao] -->|auto_medicao_id| L[faturacao_autos_medicao]
 FAT[faturacao] -->|faturacao_id| L
 FAT -->|faturacao_id| R[faturacao_recebimentos]
 R -. consumidor atual ainda usa agregado .-> MAP[caixa / mapas]
 C[colaboradores] -->|colaborador/data/obra| HR[folha_registos]
 HR --> EV[folha_avaliacoes_diarias]
 EV --> MON[folha_conferencias_mensais]
 P --> REP[folha_tarefas_reportes]
 REP --> AL[alertas]
 DOC[metadata documental] -. bytes em outro sistema .-> ST[Storage]
```

Nenhuma seta TEE-itens→auto granular foi comprovada; não incluída como FK. Não há nó implementado de custos-padrão independente: HR38 fonte/aprovador/vigência por fechar. Tarifas individuais confidenciais e valores padrão futuros são arquiteturas diferentes; não inferir salário do login/cargo.

## Migrations (propostas, não ordem operacional)
FolhaV2 → gestãoV2 → equipa persistente → fecho com baseline reconciliada → cutover fechado → avaliação AD15/14/13/03 → extensões HR27/FALTOU/readers/mensal/destinos/referências/plano/mapas. Checks de cada pacote determinam ordem/compatibilidade; rollback antes do uso difere após uso.

Financeiro/autos/hotfix e Storage têm dependências próprias. Um SQL antigo permissivo executado depois da restrição pode reabrir grant/policy. Branch DD-TENANT/FaseB não foi incorporada por existir localmente. Grafo não escolhe última definição por data/ordem alfabética. Sem baseline real reconstruída de documentação.
''')
doc('FASE-6/ESTADOS-ECONOMICOS.md','''# Estados económicos e conceitos

| Conceito | Fonte demonstrada | Distinção/risco |
| --- | --- | --- |
| Orçamentado | RPC orçamento de fase/MQT | Não é compromisso adjudicado nem factura |
| Previsto | TEE/SUB trigger por mês início | Pode ser integral no início; Q09 para distribuição |
| Estimado | Comparativo custo160 / fallback contratual | Não é realizado/pago |
| Contratado | contratos vigente escolhido por consumidor | Q10 para versão única; zero vsNULL Q06 |
| Adjudicado | Comparativo180 / candidato escolhido | Menor140 não é valor adjudicado |
| Executado | Planeamento oficial / factos laborais | Reporte Encarregado não equivale conclusão oficial |
| Medido | Auto1200 menos avanço200 | Pode existir draft semfatura; artigosTEE semponteprovada |
| Faturado | Cabeçalho aprovado/emitido e links | Helper inclui autos+advance; Q05 |
| Recebido | Parcela / agregado valor_recebido | Writer antigo fecha com100/1000; ledger existente divergente |
| Pago | Fatura fornecedor ou cliente estado | São direções do dinheiro diferentes; parcial não é integral |
| Pendente | referência/valorização/HE/classificação | HR31 não virazero nem inferência salarial |
| Corrigido/anulado | revisão e história | Não apagar factos/estornos nem criar horas compensatórias |

Comparativo: negociação40=180−140; desvio20=180−160; margem60=240−180. MapaFinanceiro mensal-23 não é entrada caixa100. Com/semIVA desconhecidos não podem ser intercambiados; implementação histórica copia compromisso nos dois totais. Mês fechado preservado. HR27 é informativa; conferência validada não processa HE nem gera salário. HR30 externo não herda o modelo interno.

Nenhuma fórmula alterada. Q04/05/06/08/09/10/16 permanecem conforme contrato; preços/margem reais não consultados.
''')
doc('FASE-6/RISCO-ROLLBACK-REPLAY.md','''# Rollback e replay

## Sequências concretas
1. Policy tenant da fixture → autos_faturacao_workflow antigo com USING(true) → SELECT externo lê cabeçalho. Rollback da transação retorna policy/grants e0leituras. MIG-ORDER; não prova catálogo atual.
2. Backup/precheck de pacote → drift de ACL/função/trigger → check rejeita; rollback do ensaio restaura. Casos do harness299.
3. Avaliação/jornada/conferência utilizadas → rollback do pacote recusado com DATA_DRIFT/AFTER_USE, sem destruição de história. Antes de uso os lifecycles permitem rollback/reinstalação.
4. Mesmo request Folha/Equipa/FALTOU retorna resposta idempotente; payload diferente ou revogação atual recusa. Duas sessões verificadas no harness.
5. Reimport RH de conteúdo igual é no-op; versão antiga diferente recusa; IDs repetidos fazem rollback do lote. Não equivale a cache de request_id.
6. Retry financeiro depois de commit perdido cria risco de draft duplicado (prova Fase2). Não reconstruir nem compensar documentos reais nesta missão.

## Riscos que não foram executados
Rollback histórico completo do hotfix Financeiro/Storage sobre a baseline atual pode restaurar assinatura/ACL incompatível; não simulado sem fixture de catálogo suficiente. SQL avulso sem pre/postcheck é risco de manutenção, não prova de instalação errada. Triggers e grants de Storage hosted não certificados.

Hash Git normalizado não substitui pg_get_functiondef+owner+ACL instalados. Prechecks devem recusar divergência; não atualizar hash para fazer passar. Nenhum rollback real ou writer legado reaberto.
''')
doc('FASE-6/INTEGRIDADE-TRANSACIONAL.md','''# Integridade transacional

**Correto na fixture:** plano multiobra recusa alvo estrangeiro integralmente; preview0; FALTOU/report/classify preservam UUID/história; lote RH com linha inválida não altera cadastro nem auditoria; mês fechado e rollback seguro preservados.

**Falhas anteriores com efeitos novos:** faturação cabeçalho/links/documentos em pedidos separados; fornecedor cabeçalho/artigos separado; escritor antigo de recebimento sem movimentos conflita com API parcial; caixa usa acumulado/data final. Não foram corrigidos.

**Nova falha de contexto:** load de consultas altera state.work antes de proteger concorrência; resposta anterior aparece sob nova obra. Isso é consistência cliente, não transação BD nem bypass comprovado. Proveniência de preço também pode desaparecer com header ausente/200.

**Observado, não automaticamente bug:** preços de proposta guardados antes de adjudicar; falha na segunda etapa deixa proposta legítima não adjudicada. Exigir etapa clara e retry idempotente de adjudicação; regra de apagar proposta não foi aprovada.

**Hipótese:** genérico INSERT metadata órfã na fixture, sem triggers reais de integridade. Não chamar prova de produto. Mudança de responsável global sem propagação e adjudicação parcialmente gravada no SQL requerem novos casos ligados; não executados.

No Storage, bytes e metadata são sistemas diferentes. Intenção/finalização/reconciliação com proveniência é proposta técnica; retenção e eliminação precisam decisão. Não apagar por nome/data.
''')
doc('FASE-6/CENARIOS-DE-FALHA.md','''# Cenários de falha e provas

-Consulta A pendente→selecionar B→A resolve: contexto B/dados A, TEMP-P3-C01 comprovado.
-Items200 presentes+headers200 vazios: preço sem origem/semwarning, TEMP-P3-C02 comprovado.
-Fatura1000→writer antigo recebe100→badgePAGO/ação escondida/saldo900: FIN-CONSUMERS, efeito de P1 conhecido.
-TEE300+SUB500→recusarTEE: forecast500 mas task persiste, FIN-TEE-CONSUMERS.
-Policysegura→SQLhistórico permissivo: leitura reaberta na fixture; rollback restaura, MIG-ORDER.
-LoteRH linha1 válida→linha2 inexistente→confirm: erro e rollback de cadastro/auditoria, RH7-BATCH correto.
-PreviewPlano→atorinativo ou empresaerrada:42501 sem factos, RH-REVOKE/TENANT corretos.
-Documento→entidadeinexistente numa tabela mínima: órfão permitido apenas por fixture incompleta; hipótese a testar no contrato real.

Preservados sem repetir causa: Fase2 linkfail/uploadfail/metadatafail/respostaperdida/misturaAPI/movimentosmensais. Cada risco relevante tem sequência ou etiqueta HIPÓTESE. Referência de garantia stale/overlap e invalidação mensal possuem casos no harness preservado executado; não reconstruir dados reais.
''')
doc('FASE-6/DESCOBERTAS.md','''# Descobertas Fase6

A cadeia mostra efeitos distintos dos mesmos factos em consumers; não transforma diferença de conceito em bug sem requisito. Demonstrado: PAGO vs saldo e permanência de tarefa após retirar previsão. Omissão de fonte de preços e contexto de obra surgem antes da BD.

Manifest lexical:575 declarações,136 nomes repetidos,370 conflitos;2.020 candidatosDDL. O inventário geral anterior588/140 usa outro método. Não são funções instaladas. Owners/grants exigem leitura ALTER/REVOKE/GRANT e precheck real futuro; não inferir ownerpostgres por costume. Nenhuma instalação real verificável foi feita.

30 relações de verdade catalogadas; elo TEEartigos→auto não comprovado e custos-padrão não implementados. DD/FaseB separados. A criaçãoRH usou cadeia de fontes identificada, não uma baseline real inventada. Limites detalhados no grafo.
''')
doc('FASE-7/TESTES-REPRODUZIVEIS.md','''# Testes reproduzíveis — somente local

Node empacotado, pg17.6 e módulo pg já presentes em TEMP; Playwright/Edge usados nas fases anteriores. Não instalar ferramentas com aprovação externa. Variáveis apontam para binários locais, nunca para produção.

```powershell
$env:QUADRO_PG_BIN=Join-Path $env:TEMP 'primeline-doc-guard-pg176\\package\\native\\bin'
$env:QUADRO_TEST_DEPS=Join-Path $env:TEMP 'primeline-medicina-test-deps\\runtime\\node_modules'
node tests/night-phase3-rh-run.mjs
node --test tests/night-phase3-finance.test.mjs
node --test tests/night-phase3-procurement.test.mjs tests/session-boundary.test.mjs tests/procurement-planning-pending-consultations.test.mjs tests/planning-operational.test.mjs
node --test tests/night-phase5-profiles.test.mjs
node --test tests/night-phase7-rh-batch.test.mjs
```

Final:299+9+29+8+5=350 contagens Node,0FAIL/0SKIP. Pais de grupos incluídos; não350 operações independentes nem cobertura única de toda plataforma. Cinco novas famílias/suites, reusando o bootstrap seguro. Regeneradores night-mission-* só escrevem matrizes/documentação Fases3–7; não executar geradores antigos que sobrescrevem Fases1/2.

Clusters localhost/porta livre/trust apenas descartável, parados em finally, não eliminados. Auth na fixture usa test.actor, não tokens reais. Finança usa helpers autorizados sintéticos, portanto não certificado cross-tenant. Cadastro/importRH usam writers reais e roles por empresa; dependencia do criador do ficheirocampos_completos explicitada.

As asserções de diagnóstico de C01/C02 e P1 antigo verificam a falha observada e são classificadas FALHA/VULNERABILIDADE, não aprovação de segurança. Não alterar expectativas para mascarar o resultado. Nenhuma nova cargaHTML/exploração foi necessária; evidênciasFase2 preservadas.
''')
doc('FASE-7/RISCOS-COMPROVADOS.md','''# Riscos comprovados

Novos sem códigooficial: TEMP-P3-C01 P2 trocaobra durante load; TEMP-P3-C02 P2 preço sem origem/aviso. Correspondências N-ARCH-01/resiliência e N-FOR-05/02 propostas, não integração automática no Backlog Mestre.

P1 N-SEC-01/FIN-01/FIN-05 e filhosN2 anteriores preservados; HR38 também. Financeiroconsumer agora provaPAGO/sem ação emcontrastecomsaldo900. OrdemSQLhistórica reabre leitura nafixture; não declara RLSrealvulnerável. TEErecusado/taskpersistente mantémN-FIN-06.

Nenhuma correção implementada. Não encontrado novo P0 emcenários executados; não é certificação de ausência de P0/P1 no restante. Metadataórfã somente emfixturesemtriggers é hipótese.
''')
doc('FASE-7/COBERTURA-ALCANCADA.md','''# Cobertura alcançada

350 contagens finais Node/0FAIL/0SKIP nas execuções Fases3–7. São resultados de cenários seguros, incluindo reuso de292contagens do harness, regressões puras/cliente e testes novos.236Fase1 e42Fase2 preservados, sem soma apresentada como total único.

Matriz adversarial19cenários/famílias: válido/inválido/permissão/inexistente/revisão/concorrência/repetição/falha/cancelamento/recuperação/auditoria/tenant/sessão conformeaplicável. Etiquetas separam PASS, FALHA/VULNERABILIDADE, OBSERVADO e HIPÓTESE. CSVregressões38lacunas explícitas; itens nãoexecutados não contamSKIP de suite.

Rastreabilidade:32operações/256pares,21DB+32frontend;203backendnãoexecutados. Cobertura das38áreas é revisão focada; não todas ações/estados. UAT Auth hospedado, catálogo real, Storage, cadeia adjudicação/doc/fatura, módulos periféricos e baselinecrossbranchnão exercitadosintegralmente.

Não houve bloqueio de proteção essencial nestes testes. Restrições de produção foram respeitadas, sem tentativa de contorno. Limite defixturefoi documentado (docmissing), não convertidoemprova.
''')
doc('FASE-7/RECOMENDACOES.md','''# Recomendações

1. Rever saídaHTML/contexto em tarefa autorizada, mantendo estrutura e texto legítimo.
2. Corrigir atomicidade faturas/linhas e integrar receipts existentes/consumidores; Q04/05 antes de nova regra financeira.
3. Invalidar loads por obra e expor preço sem proveniência; C01/C02 tecnicamente independentes de conceder preço ao Encarregado.
4. Formalizar manifest/baselines por assinatura/hash/owner/ACL e separar históricos/rollback; sem SQL real nesta missão.
5. Fechar fonte/aprovador/vigência do padrãooperacionalHR38. HR41 confidencialAdmin preservado; não limitarHR29 silenciosamente.
6. Escolher lacunas concretas no CSV antes de ampliar funcionalidades: adjudicação/documentos, contratosvigentes, downstreamindicadores, módulosperiféricos e Auth hosted autorizado.

Não publicar com os P1 abertos; não executarrollback/compensação automática. QuestõesQ01–20 continuam no relatórioconsolidado; nenhuma ausência de respostaéaprovação.
''')
# Retoma final por fase: generated after evidence, never rewrites prior phases.
for n in range(4,8):
 doc(f'FASE-{n}/RETOMA.md',f'''# Retoma Fase {n}

Branch codex/auditoria-global-noturna-20261014. Base Fases1/2 f72686cfdc4f61514a86851aa18de7976242ca56. Checkpoints iniciais767d301/1eab4b6; Fase3 guardada21b2f89. SHA final na entrega e git rev-parse HEAD; não criar autorreferência impossível no próprio commit.

Fase {n} entregue no âmbito descrito no resumo/cobertura. Não afirmar todas ações/perfis executados.350contagensNode novas execuçõesFases3–7/0FAIL/0SKIP, incluindo grupos e reuso; ver RESULTADOS-FASES-3-A-7.json. Validação documental posterior separada. Originais Fases1/2 preservados.

Worktree C:/Users/conta/.codex/worktrees/auditoria-global-noturna-20261014/primeline-go-urgente. Repositório principal preservado. Tudo local; sempush/merge/deploy/Supabase/Cloudflare/SQL real.

Próximo: ler RESUMO-GLOBAL-FINAL.md e CONSOLIDACAO-PARA-BACKLOG.csv. Escolher contrato/lacuna e obter autorização futura; não implementarautomaticamente. DecisõesQ01–20 preservadas; HR27/30/31/41 não reabertos; HR38 aprovação de princípio somente.

Runtimes: Node/pg17.6/pg emTEMP, Python e artifact-tool empacotados; nenhum segredo. Clusters parados/não eliminados; reproduzíveis. Não executar geradoresnight-global antigos que sobrescrevem Fases1/2.
''')
retoma=R/'FASE-3/RETOMA.md'
text=retoma.read_text(encoding='utf-8-sig')
marker='\n## Fecho das entregas Fases3–7\n'
if marker in text:text=text.split(marker)[0]
text+=marker+'\nStatus final: as 43 entregas das Fases 3–7 estão prontas no âmbito medido. Fase 3: 337 contagens finais (299 RH + 9 Financeiro + 29 Compras/sessão). Fases 5/7 acrescentam 8 + 5; total 350 contagens executadas, sem alegar cobertura única. Há ainda 203 pares backend não executados e 38 lacunas. Ver RESUMO-GLOBAL-FINAL e VERIFICACAO-FINAL (20 verificações PASS). Produto preservado; nenhuma integração ou produção. Aguardar revisão das provas e autorização futura, sem correção automática.\n'
retoma.write_text(text,encoding='utf-8')
doc('RESUMO-GLOBAL-FINAL.md', '# Primeline GO — resumo global da auditoria noturna\n\n## Resultado e âmbito\n\nFases 1/2 preservadas; entregas das Fases 3–7 preparadas, com **cobertura funcional parcial explicitamente medida**. A missão não certifica toda a plataforma ou produção.\n\nProduto, SQL funcional e permissões inalterados. Sem SQL hospedado, push, merge, deploy, Cloudflare, credenciais ou dados pessoais reais.\n\nBranch: codex/auditoria-global-noturna-20261014.\nBase: f72686cfdc4f61514a86851aa18de7976242ca56.\nCheckpoints locais: 767d301 → 1eab4b6 → 21b2f89 → consolidação final.\nSHA final na entrega/HEAD. Worktree conferida no encerramento; repositório principal preservado.\n\n## Verificado e limites dos denominadores\n\n- 38 áreas revistas por lacunas específicas; os dez eixos não representam 380 provas aprovadas.\n- 20 percursos/casos end-to-end com writers, leitores e fronteiras de fixtures identificados.\n- 32 operações críticas/256 pares de perfil: 32 capabilities frontend executadas, 21 pares com prova DB, 203 pares backend apenas revistos estaticamente.\n- 520 candidatos data-* e 218 referências API não equivalem a operações completas.\n- 30 relações de fontes de verdade; 575 declarações SQL, 1.713 chamadas qualificadas, 2.020 candidatos DDL e 136 nomes repetidos em 370 ocorrências de conflito. Não representam o catálogo instalado nem toda sintaxe SQL.\n\n## Novos problemas comprovados\n\n1. **TEMP-P3-C01 — P2 proposto:** trocar da obra A para B durante o carregamento de Compras pode manter consultas de A sob contexto B. Função real procurement.load executada em VM. Sem bypass entre empresas demonstrado.\n2. **TEMP-P3-C02 — P2 proposto, N-FOR-05/02:** um item cujo cabeçalho de fatura não é devolvido aparece sem aviso de origem incompleta. Ausência sintética; causa real por RLS/paginação não investigada.\n\nSem códigos oficiais novos do Backlog Mestre.\n\n## Problemas anteriores aprofundados\n\nP1 de HTML, faturação não atómica, recebimentos, filhos N2 e HR-38 permanecem abertos. Novo efeito nos consumidores: receber 100 de 1.000 mostra PAGO e retira a ação de receber o restante, enquanto a Visão Geral ainda calcula saldo 900.\n\nTEE recusado retira previsão mas mantém tarefa, N-FIN-06. SQL histórico permissivo reabriu leitura numa fixture depois da policy segura; rollback restaurou. É prova de ordem local, não exposição atual da produção.\n\n## Comportamentos corretos\n\nFolha/Equipa preservou preview sem escrita, revisão, idempotência, concorrência, tenant e recusa após inativação. FALTOU chegou ao mapa/classificação/história mensal sem horas inventadas. Correção de 480 para 240 minutos chegou à conferência sem criar Vencimentos.\n\nCadastro RH real criou contrato, alocação explícita e auditoria. Lote com segunda linha inválida fez rollback da primeira alteração e auditoria. Mesmo conteúdo não duplicou audit. Oito perfis RH distinguidos.\n\nReporte Encarregado não conclui oficialmente. Diretor/Adjunto validam; Preparador não confirmou. O trigger tarefa_concluida liga a conclusão autorizada no Planeamento à confirmação e resolução de alertas: ausência de literal task_confirm não prova backend órfão. Meses fechados preservados; cotação, adjudicado, desvio e margem distintos.\n\n## Resultados finais\n\n| Bloco | PASS Node | FAIL | SKIP |\n| --- | ---: | ---: | ---: |\n| Harness RH/tarefas, 7 casos novos | 299 | 0 | 0 |\n| Financeiro/consumidores/ordem SQL | 9 | 0 | 0 |\n| Compras/sessão/Planeamento | 29 | 0 | 0 |\n| Capabilities dos oito perfis | 8 | 0 | 0 |\n| Cadastro/import RH | 5 | 0 | 0 |\n| **Total destas execuções** | **350** | **0** | **0** |\n\n236 da Fase 1 e 42 da Fase 2 preservados, não somados como cobertura única. Grupos pai incluídos no contador Node. Teste que passa ao demonstrar falha é FALHA/VULNERABILIDADE REPRODUZIDA, nunca aprovação de segurança. Validações posteriores dos artefactos são contadas separadamente.\n\n## Hipóteses e não executado\n\nMetadata órfã numa fixture sem triggers reais é hipótese. Não provados órfãos/duplicados reais, contrato da Obra 128, limites REST, RLS/ACL/owners atuais, CSP, SMTP ou Storage/Auth hospedados.\n\nNão ligados integralmente: adjudicação SQL → documentos → fatura; batch Planeamento → todos indicadores; cadeias completas de Medicina, Viaturas, RNC, Salas, Imóveis e Pedidos. Matrizes identificam 203 pares backend não executados e 38 lacunas específicas.\n\nNão houve bloqueio de proteção essencial às suites locais concluídas. Proibição de produção respeitada, sem contorno. Scanner lexical não prova ausência de outros defeitos; nenhuma exploração HTML nova necessária.\n\n## Decisões e dependências\n\nQ01–20 preservadas: fonte/aprovador/vigência do padrão HR-38; parciais/excesso/estornos e nomes financeiros; zero/NULL, IVA, contrato vigente, distribuição temporal, recusa TEE, recovery/retensão documental e regras da Obra 128.\n\nHR-27/30/31/41 não reabertos. Custo-padrão operacional tem só aprovação de princípio; FP-28/29 em standby.\n\nRefs locais de Débitos/Fase B coincidem com SHAs anteriores, mas possuem respetivamente dois e um commits ausentes desta base. Ver FASE-6/BRANCHES-PREPARADAS.json. Sem integração nem remoto consultado; precheck anterior PASS não autoriza instalação. Testes no outro computador exigem runtimes locais documentados.\n\n## Prioridades e próximo passo\n\n1. Saída HTML e manifesto de scripts numa tarefa autorizada.\n2. Atomicidade de faturas e integração de receipts/consumidores após Q04/05.\n3. Invalidar carregamento por obra e explicitar proveniência de preços, sem novos acessos.\n4. Fechar decisões HR-38 sem expor RH individual ou alterar permissões silenciosamente.\n5. Escolher lacunas concretas para novas regressões integradas.\n\n**NO-GO para publicação dos circuitos com P1 aberto.** Provas prontas para revisão e preparação de correções autorizadas.\n\nCONSOLIDACAO-PARA-BACKLOG preserva 34 IDs e cinco extensões temporárias, três anteriores e duas novas: 39 registos, não 39 bugs independentes. Nenhum item histórico apagado ou marcado corrigido automaticamente.\n')
