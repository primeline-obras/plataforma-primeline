# Auditoria independente final — Pacote 2 / Folha de Ponto

Auditoria realizada em 06/10/2026. O nome do artefacto mantém a referência 20261005 solicitada.

## A–B. Identificação, preservação e método

- SHA auditado: `77d50afd44bdade4490a95085665bc74bcc22a4f`.
- Candidato remoto: `feat/adm-rh-fecho-folha-ponto-20261005`, reconfirmado nesse SHA, working tree inicialmente limpo.
- Branch da auditoria: `audit/pacote-2-folha-ponto-final-20261005`, criada exatamente no candidato. O commit que contém este relatório identifica a entrega.
- Main de referência: `3df019a2f2813c0cbf7f36a8d13000431d33dd50`; não alterada.

Revisão de código/modelo/scripts, catálogo instalado numa base PostgreSQL 17.6 efémera, suites existentes, testes independentes adicionais e browser com RPCs sintéticas. A matriz do autor foi usada como checklist, não como evidência suficiente. A instalação/rollback local foi concluída mesmo após os testes de confidencialidade falharem. Não foi alterado código de produto, executado SQL real, feito deploy, modificado perfil/dado real ou executada Fase B real.

## C. Matriz A–AN independente

PASS é evidência local; não representa validação do catálogo ou sessões reais. PG: suite backend e casos independentes; D: domínio; B: browser Folha; C: browser consolidação; S: estáticos/regressões. PENDENTE ADM refere-se apenas à ativação/regras ainda não aprovadas, separadas no final.

| ID | Requisito | Resultado | Evidência / limite |
|---|---|---|---|
| A | Nome FOLHA DE PONTO | PASS | Novos consumidores/diálogos; B/C. Nomes históricos do legado permanecem históricos. |
| B | Pessoa + dia | PASS | Chaves pessoa/local/data e revisões; PG/D. |
| C | Sem herança da última alocação | PASS | Consulta por data explícita; PG/D/B. |
| D | Ponto progressivo | PASS | Intervalo aberto e posterior edição; PG/B. |
| E | Completo no final do dia | PASS | Intervalos completos e recusa de horas futuras; PG/D/B. |
| F | Coletiva progressiva | PASS | Start/finish, não altera intervalos já fechados, atomicidade; PG/B. |
| G | Coletiva normal | PASS | Horários 08–17/09–18, jornada completa, períodos, janela e no-overwrite; PG/D/C. |
| H | Não registado ≠ presente | PASS | Nenhuma folha/minuto inventado; D/B/C. |
| I | Em aberto | PASS | Saída NULL conservada; PG/D/B. |
| J | Horas em falta | PASS | Carga versus minutos sem ausência inventada; PG/D/C. |
| K | Horário configurável | PASS | RPC/formulário e invariantes de períodos/minutos; PG/C. |
| L | 8h deslocadas não são HE | PASS | Comparação de carga e minutos; PG/D. |
| M | Escritório flexível | PASS | Local NULL explícito, unicidade e carga 480 configurável; PG/C. |
| N | Diretor/Adjunto/Preparador próprio ponto | PASS | Próprio permitido; terceiro, vínculo ausente/ambíguo, inatividade/tenant recusados; PG/C. |
| O | Ponto normal sem aprovação | PASS | Gravação de factos independente de HE; PG/B/C. |
| P | Adicionar sem alocação | PASS | Destino explícito e candidatos; PG/B. |
| Q | Manhã/tarde/dia inteiro | PASS | Períodos/intervalos e split controlados; PG/D/B. |
| R | Transferência Encarregado | PASS | Destino responsável, origem real da mesma empresa, histórico e concorrência; PG/B. |
| S | Retirada do dia | PASS | UUID/revisão, ausência/ponto/conflito recusados; PG/B. |
| T | Histórico de movimentos | PASS | Núcleo v1 e histórico v2 preservados; PG/B. |
| U | Férias zero esperado | PASS | Carga zero e ausência válida sem ponto; PG/D/B. |
| V | Ausência + trabalho regulariza | PASS | Conserva os dois factos; PG/D/B. |
| W | Motivo opcional | PASS | Writer/UI não exigem motivo, auditam quando fornecido; PG/S/B. |
| X | HE da Folha | PASS | Origem folha/revisão, opt-in e conflito com origem manual; PG/S. |
| Y | Diretor/Adjunto aprova HE | PASS | Aprovar/rejeitar com responsabilidade e revisão; PG/C. |
| Z | Administrativo valida HE | PASS | Transição posterior separada, sem euros; PG/C. |
| AA | Sem valor enquanto pendente | PASS | Estados pendentes, nenhum cálculo monetário; PG/S/C. |
| AB | Dias especiais factuais | PASS | Facto/pendência sem remuneração presumida; PG/D/C. |
| AC | Externos separados | PASS | Identidade empresa/fornecedor, múltiplas obras/dias, sem RH/economia; PG/S/B. |
| AD | Resumo do dia | PASS | Derivado de folhas/ausências/conflitos, incluindo externos; PG/D/B/C. |
| AE | DIA COMPLETO | PASS | Indicador factual, não fecho administrativo; PG/D/B/C. |
| AF | Histórico/auditoria | P2 | Append-only v2 PASS; apresentação do histórico legado falha, achado P2-01. |
| AG | Idempotência | PASS | Replay exato, payload diferente recusado; PG/D. |
| AH | Concorrência | PASS | Folha, alocação, transferência, bulk, replay e legado/v2; PG. |
| AI | Tenant/permissões | P1 | Tenant externo fechado; confidencialidade por papel falha no histórico administrativo, P1-01. |
| AJ | Reporte ≠ conclusão | PASS | Não altera `planeamento_itens.estado`; PG/C. |
| AK | Conclusão reconcilia reporte/alerta | PASS | Fluxo autenticado Diretor confirma, retira da lista ativa e preserva resolvidos; PG. Limite de jobs sem ator na secção S. |
| AL | Férias não contíguas/atómicas | PASS | Seleção/range/remoção/revisão/override/fonte; PG/D/C. |
| AM | Vencimentos sem salário inventado | P1 | Draft/cálculo/fecho seguros; isolamento da informação salarial falha em P1-01. |
| AN | Cargo RH ≠ perfil operacional | PASS | Cargo formal apresentado; autorização pelo utilizador ativo/responsabilidade; PG/C. |

Não foram convertidos requisitos aprovados em PENDENTE ADM. O P1 afeta três condições de segurança/isolamento, não três causas independentes.

## D–F. Lista consolidada de achados

### P0

Nenhum P0 confirmado nas verificações locais concluídas. Isto não substitui reconfirmação real de catálogo/privilegios.

### P1-01 — histórico administrativo salarial devolvido a perfil operacional

**Localização:** `supabase/folha_ponto_v2_gestao.sql`, gravação do histórico por `fn_folha_gestao_v2` (linhas 213–214) e seleção/retorno por `fn_folha_gestao_contexto_v2` (linhas 251–262).

O writer administrativo aceita `work_id` em `payroll_save` e guarda-o no histórico. O reader operacional valida a obra, mas seleciona todo o histórico dessa obra sem allowlist de ações/campos por papel. A ausência do painel salarial no frontend não protege o payload da RPC.

**Reprodução defensiva sintética:** um Administrativo grava rascunho da sua empresa, de colaborador da mesma empresa, com obra explícita e campos manuais. O Encarregado responsável consulta `fn_folha_gestao_contexto_v2(obra,NULL,NULL)`. `history` contém `payroll_save`, incluindo os campos manuais/observação nos JSONs antes/depois. Não houve acesso a outra empresa nem escrita não autorizada pelo Encarregado.

**Esperado:** contexto operacional não recebe histórico de vencimentos/direitos/férias administrativas ou outros dados RH reservados. **Obtido:** teste de confidencialidade falha. A mesma query de histórico é partilhada por Diretor/Adjunto; leitura de custos de obra não equivale a autorização administrativa salarial.

**Correção mínima recomendada, não aplicada:** separar/projetar histórico por papel e ação no backend; recusar/normalizar `work_id` nos comandos administrativos que não pertencem a uma obra. Adicionar negativas para todos os tipos administrativos e perfis operacionais. Ocultar UI apenas não corrige.

### P2-01 — histórico legado devolvido pela RPC é descartado pelo cliente

**Localização:** `src/attendance-client.js:46–48`, `src/attendance-sheet.js:84`, retorno da RPC em `supabase/folha_ponto_v2.sql:365`.

Backend retorna `events`, `legacy` e `legacy_interpretation='original'`. O cliente retorna só `j.events`; a UI mostra “Sem alterações registadas” quando só há evidência legada. O teste independente com resposta legítima contendo apenas legado falha.

**Impacto:** a proteção contra mistura permanece ativa, mas falta a apresentação histórica exigida e a pessoa não tem essa evidência disponível no novo consumidor. Não foi confirmado desaparecimento de dados na BD.

**Correção recomendada, não aplicada:** contrato/consumidor devem conservar e apresentar a origem legada separadamente, sem converter horas nem atribuir significado novo.

Não foi produzida uma lista de microajustes estéticos. Outros limites de operação/rollout estão nas secções seguintes, separados de defeitos confirmados.

## G. Modelo de dados

Revistas as 12 tabelas públicas `folha_*` e `folha_privado.operacoes`. Catálogo local confirmou owner postgres, RLS e ausência de grants diretos não administrativos. Tabelas novas começam vazias; não há backfill.

- `folha_registos`: exclusividade colaborador/externo, local obra/escritório, obra NULL só Escritório, externo não pode ser Escritório, minutos/revisões e índices parciais. `NULLS NOT DISTINCT` impede duas folhas de Escritório para o mesmo colaborador/data.
- Identidade externa única por empresa/fornecedor/nome operacional normalizado; afetação tem PK externo/obra/data.
- HE única por folha/revisão; vencimentos por pessoa/competência; direito por pessoa/ano; reporte por tarefa; operação por empresa/ator/request.
- Dois históricos têm triggers append-only; rollback recusa apagar evidência.
- Triggers de integridade verificam empresa de obra/pessoa/fornecedor/externo nas tabelas de factos pertinentes. RPCs validam os restantes relacionamentos.

Nem todas as referências de empresa/obra nos históricos/HE/operações possuem FK própria/composite tenant. A integridade depende também de RPCs privadas e ausência de DML direto. Manutenção com superuser é fronteira de confiança; não foi alegada segurança contra owner postgres que modifica dados/ACL. Hashes/revisões não são prova de integridade contra esse owner.

## H. RPCs e helpers

| RPC | Localmente confirmado |
|---|---|
| `fn_folha_contexto_v2(date,uuid)` | Ator ativo, obra responsável ou escritório próprio, equipa/data explícita, sem dados de custos. |
| `fn_folha_pessoas_v2(date,uuid)` | Candidatos operacionais da mesma empresa, sem PII económica; contexto de alocação pontual. |
| `fn_folha_operar_v2(text,jsonb,boolean,text)` | Papel/tenant/obra, self-service, preview/token/revisão/request e writes atómicos. |
| `fn_folha_historico_v2(jsonb)` | Âmbito da pessoa/data/obra e evidência v2/legado; falha no consumidor, P2-01. |
| `fn_folha_gestao_contexto_v2(uuid,uuid,date)` | Parâmetros administrativos restritos, mas histórico de obra não filtrado por papel: P1-01. |
| `fn_folha_gestao_v2(text,jsonb,boolean,text)` | Ações administrativas/reportes/HE verificadas; `work_id` salarial contribui para P1-01. |

Seis RPCs SECURITY DEFINER, owner postgres, `search_path=pg_catalog`, EXECUTE authenticated, sem PUBLIC/anon/service_role. Helpers privados sem USAGE/EXECUTE externo. Não confiam em empresa/papel enviados pelo cliente; negativas com esses campos e IDs fora da empresa estão cobertas. O catálogo REAL não foi confirmado.

## I–J. Escritório e Encarregado

Diretor/Adjunto/Preparador: gravação própria permitida; terceiros, vínculo ausente/ambíguo, outro tenant, ator/colaborador indisponível e alteração de obra para ampliar escrita recusados. Contexto com vínculo ambíguo desativa Escritório; não precisa lançar exceção na consulta para impedir escrita. Cargo RH distinto não amplia autorização.

480 minutos configuráveis, horários deslocados, >8h sem auto-HE mesmo com opt-in de obra ativo, <8h missing, unicidade NULL e histórico verificados. Administrativo/Gestão/Gerência preservam administração na empresa.

Encarregado: sem Escritório e sem DML direto, apenas obras responsáveis/equipa explícita; operações externas ao âmbito recusadas. Não há writer de custos novo. **Sem RH sensível não passa integralmente por P1-01.** Financeiro, inativo e identidade sem utilizador não obtêm escrita operacional. Gerência/Administrativo/Gestão, Diretor/Adjunto/Preparador e Encarregado estão cobertos nas suites; payload de perfil não substitui o utilizador real.

## K–M. Coletivas, alocação, preview e concorrência

Start/finish limitam o modo progressivo a hoje, usando a hora fornecida pelo frontend; backend recusa horas futuras e preserva intervalos fechados. A BD não comprova que a hora fornecida seja a hora efetivamente observada em obra; registo factual continua dependente do utilizador autorizado. Não foi inventada política de tolerância de relógio.

Dia normal usa horário configurado e exige fim da jornada completa, inclusive meia jornada; janela NULL não concede retroativo. Exclui ausência/conflito/folha existente; erro de uma revisão aborta o conjunto. Horários 08–12/13–17 e 09–13/14–18 estão cobertos.

Allocate cria destino explícito; transfer verifica origem real/empresa e destino responsável, mantém metade oposta quando aplicável; retirada exige os IDs e preserva movimentos. Source falso, UUID manipulado, conflito/ausência/ponto e revisão antiga são recusados.

Preview não persiste operação/histórico/alerta/revisão. Confirmação verifica token/snapshot/payload. Replay não duplica; mesmo request com payload diferente é recusado. Duas conexões cobrem folha, alocação/transferência, bulk, replay e writers legado/v2 nos dois sentidos. Novos testes de transferência e bulk simultâneos confirmaram só um commit e nenhuma escrita parcial. READ COMMITTED é exigido; snapshots antigos não são aceites silenciosamente.

## N–O. Legado e externos

Legado preservado sem conversão/backfill/herança. Conflito legado/v2 nos dois sentidos impede folha efetiva duplicada. Apresentação do legado: **P2-01**, não PASS.

Externos reutilizam identidade em duas obras/datas e conservam fornecedor/empresa. Reutilizar ID com fornecedor diferente é recusado; homónimo no mesmo fornecedor exige identificação operacional distinta, sem merge silencioso. Inativo fica sem escrita. Não cria colaborador, vencimento Primeline, custo, fatura, auto ou pagamento.

## P–R. HE, férias e vencimentos

HE: origem folha/revisão única; opt-in/calendário e carga; 8h deslocadas e Escritório >8h sem geração; dia especial factual pendente; Diretor/Adjunto approve/reject e Administrativo validate. Correção supersede origem antiga, stale é recusado e origem manual legado impede duplicação. Nenhum euro/taxa/pagamento automático.

Férias: carga zero sem exigir ponto; trabalho coexistente regulariza sem apagar ausência. Dias/range/não contíguas/remover/revisão/replay/override/direito com fonte e histórico cobertos. Sem default de 22 dias ou consumo especial presumido.

Vencimentos: Primeline apenas, factos/ausências/pendências/manuais/draft; sem salário/taxa/pagamento e exportação oficial recusada. UI não fecha/exporta. Isolamento administrativo da informação: **P1-01**. Modelo oficial/regras ADM continuam desativados, não apresentados como funcionalidades concluídas.

## S. Tarefas e alertas

Reporte não altera Planeamento. Diretor/Adjunto consulta reporte; navegação abre o fluxo existente. Conclusão autenticada reconcilia reporte, revisão e alerta pendente da origem conhecida, retirando tarefa das listas ativas; 100% isolado não conclui.

Trigger limita UPDATE de alertas a tipo/entidade/obra/empresa/estado pendente conhecidos, preservando outras origens e já resolvidos. Se conclusão for feita por rotina sem ator autorizado, o trigger retorna sem reconciliação; nenhum job desse tipo foi demonstrado como consumidor necessário no catálogo real. Isso deve ser reconfirmado no gate de catálogo, sem assumir cobertura de todos os writers futuros.

## T–V. Segurança, frontend e regressões

Varredura de todas as tabelas/funções novas, ACL owner/search_path/EXECUTE, triggers, parâmetros e clientes. Novas tabelas não têm acesso direto para roles de aplicação. P1-01 ocorre pelo reader SECURITY DEFINER, não por grant aberto. Policy/RLS fechadas não corrigem projeção excessiva dentro de uma RPC autorizada.

Cliente v2 usa RPCs sem fallback/DML, valida versão/commit/request/revisão, conserva request em resposta ambígua e não reenvia stale silenciosamente. Boundary de sessão elimina DOM e recria documento/realm, incluindo módulos/closures, em logout/expiração/troca de identidade.

Browser: Folha 45 grupos PASS; consolidação 48 grupos PASS em seis perfis/três tamanhos; sessão 7 cenários PASS; custos Planeamento 33 PASS; Quadro, RH, Medicina, RNC e Viaturas PASS. Console sem pageErrors relevantes nos harnesses. Estes mocks não detectaram P1-01, confirmado separadamente em PostgreSQL real local.

Reexecutadas regressões de Financeiro/tenant/writers/hotfix, Subempreitadas, Documentos, alertas e contratos, além de Quadro/RH/Medicina/Planeamento/sessão. Houve intermitência de arranque PostgREST: a suite financeira isolada passou 122 testes e a suite de âmbito isolada passou 33; uma execução agregada sequencial voltou a falhar no arranque de uma instância REST. Essa falha é preservada como limitação do ambiente, não ocultada nem contada como terceiro defeito de produto.

## W–X. Scripts Folha e Fase B

Folha: precheck READ ONLY estrito com hotfix consolidado, backup privado, migrations localmente instaladas, postcheck de novas ACL/RLS/RPCs/triggers e preservação de dados/estruturas legadas, rollback vazio e recusa com factos. Scripts de instalação são transacionais; nenhum foi aplicado em produção.

Limite explícito: o precheck Folha completo incorpora verificações do catálogo económico real e das suas tabelas privadas de backup. Foi revisto por código/contratos, mas não executado integralmente na fixture reduzida da Folha; os contratos económicos são exercitados na suite financeira separada. A execução integral do precheck com todas essas dependências permanece gate antes da instalação, não um PASS real inferido da fixture.

Fase B pós-hotfix: cinco scripts auditados; gate independente privado, catálogo completo/instalação/readiness/assets, recusa ausência/drift, backup/install/postcheck/rollback local completo. Preserva hotfix, Folha v2, v1 e Cadastro RH; fecha DML/writer antigo esperado do Quadro sem fechar Ponto legado prematuramente. Rollback restaura estado pós-hotfix e não apaga histórico/revisões nem reativa aprovação consumida.

Gate não regenera fingerprint automaticamente. Aprovação ainda precisa ser estabelecida por procedimento independente real; uma linha criada/modificada pelo owner postgres é uma decisão confiada ao operador, não uma assinatura criptográfica de auditor externo. Os testes criam aprovação apenas na base sintética para exercitar o mecanismo, não para aprovar produção.

## Y. Catálogo real

**REAL_CATALOG_VALIDATION_REQUIRED.** Uma única tentativa de ligação pelo Chrome DevTools `list_pages` terminou em timeout. Não houve query real, token extraído, credencial reutilizada manualmente, autenticação repetida ou tentativa de contornar proteção. A limitação não impediu as verificações locais. Catálogos anteriores/fixtures não foram apresentados como estado atual real.

## Z. Resultados de testes

Resultados sem somar reexecuções/suites sobrepostas:

| Execução | PASS | FAIL | SKIP | Interpretação |
|---|---:|---:|---:|---|
| Conjunto agregado sequencial, 41 ficheiros | 466 | 4 | 3 | Dois achados, teste-pai Folha e arranque REST financeiro. |
| Contratos Folha finais, incluindo casos independentes adicionais | 44 | 3 | 0 | P1-01, P2-01 e teste-pai; instalação/rollback continuam PASS. |
| Financeiro/tenant/writers/hotfix isolado | 122 | 0 | 0 | SQL e REST local, incluindo regressões económicas. |
| Âmbito Encarregado isolado | 33 | 0 | 0 | SQL/REST, papéis/RLS/grants e rollback. |
| Unitários/contratos/documentos/alertas, sem runtime PG configurado | 99 | 0 | 4 | Três RH e um Quadro-alertas; este último foi exercitado na execução agregada. |

Os dois testes negativos novos falham no comportamento saudável esperado: P1-01 e P2-01. O runner também marca o teste-pai Folha como falhado; esse terceiro FAIL **não é terceiro defeito independente**. O conjunto agregado não é declarado integralmente PASS.

Suites browser: 45 + 48 grupos Folha, sessão 7, custos 33, e demais regressões descritas acima, sem soma artificial com testes Node. Instalação/postcheck/rollback Folha e B continuam executados depois dos achados.

SKIPs RH dependem de PGlite/jsdom não configurados em `RH_TEST_DEPS`; permanecem SKIP, não PASS. Evidência PostgreSQL/browser de outras suites não é substituição silenciosa.

## AA–AB. Decisão e bloqueantes mínimos

**NO-GO LOCAL para rollout do candidato.** Existe um P1 confirmado de confidencialidade administrativa no reader operacional. Não se aplica a declaração de aptidão condicionada solicitada para o caso sem P0/P1.

Antes de produção:

1. Corrigir P1-01 no produto, revalidando projeção/ações administrativas para todos os perfis operacionais; não ampliar acesso.
2. Corrigir P2-01 para cumprir apresentação do legado antes de substituir seu consumidor.
3. Reconfirmar catálogo REAL e precheck estrito; resolver divergências sem regenerar aprovação para esconder drift.
4. Manter desativadas as regras ADM ainda não aprovadas: janela retroativa, calendário/consumo especial, valorização HE/vencimentos e modelo/exportador. Direitos reais precisam de fonte.
5. Validar preview autenticado/readiness e obter autorização expressa para instalação/publicação. Fase B permanece gate e autorização separados.

Nenhuma correção de produto foi efetuada nesta auditoria. Nenhum dado/perfil real, main, deploy, marcador ou Fase B real foi alterado.
