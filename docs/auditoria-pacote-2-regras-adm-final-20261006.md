# Auditoria final das regras ADM — Pacote 2

Data: 06/10/2026. **NO-GO LOCAL.** Encontrados **2 P1 e 1 P2**; nenhum P0 identificado.

## A–B. Candidato e preservação

- SHA auditado: `c250283d84feef7034867e18bae5997b3424772d`.
- Branch de auditoria: `audit/pacote-2-regras-adm-final-20261006`, criada exatamente nesse SHA.
- O SHA desta auditoria é o commit que acrescenta este relatório e os testes independentes.
- Auditoria anterior: `253492a35d5aa8542d838e056563d2d85d17766c`, branch `audit/pacote-2-reconciliacao-estado-final-20261006`, preservada.
- Produto inalterado: nenhum ficheiro em `src/`, `index.html` ou `supabase/` modificado nesta auditoria.
- Nenhum acesso novo à BD real, SQL real, deploy, main, marcador ou Fase B. Não houve bloqueio da proteção do produto nas verificações locais. Catálogo/calendário reais não foram consultados, conforme escopo.

## Q. Achados bloqueantes

### ADM-P1-01 — processamento administrativo HE exposto a Diretor/Adjunto

**Confirmado em PostgreSQL local, raw JSON e browser desktop/tablet/mobile.**

`fn_folha_gestao_contexto_v2` agrega HE com `to_jsonb(x)` em `supabase/folha_ponto_v2_gestao.sql:443`. Diretor/Adjunto recebem `processado_em`, `processado_por` e `prazo_processamento`, inclusive preenchidos numa HE processada pelo Administrativo. A remoção de chaves administrativas no fim da função não filtra esses campos aninhados.

Há também um segundo caminho para a mesma exposição: a consulta de histórico admite todo o domínio `he` para Diretor/Adjunto (linha 430), e `he_process` pertence a esse domínio (linhas 29–35). Consequentemente devolve ação administrativa e snapshots completos `antes/depois`. O histórico operacional da UI apresenta os snapshots; o painel HE apresenta “Pago / processado” e prazo mesmo sem `permissions.adm`.

Impacto: viola explicitamente o requisito de não entregar processamento/pagamento administrativo a esses perfis. Não foi observado acesso a folha salarial, km, ajudas ou saldos através desse contexto. A escrita continua recusada aos perfis indevidos; isto é uma falha de projeção/leitura.

Recomendação, sem implementar: projeção explícita por papel no array HE e no histórico; reservar `he_process` e campos administrativos ao destinatário autorizado, incluindo snapshots de outras ações HE. Esconder a UI isoladamente não resolve o JSON.

Testes independentes que falham: `Director/Adjunto raw HE excludes administrative processing fields` e `Director/Adjunto raw history excludes administrative processing snapshots`. Ambos os perfis são recolhidos antes de avaliar a asserção.

### ADM-P1-02 — infraestrutura documental reutilizada não isola metadados por empresa

**Confirmado no catálogo histórico preservado, no SQL existente e numa reprodução local dessa policy. Não é uma reconfirmação da BD real atual.**

O snapshot `tests/fixtures/encarregado-catalogo-real-20261004.json`, `catalog.tables[ausencias_anexos]`, tem RLS ativo, CRUD de authenticated e uma única policy permissiva `ausencias_anexos_rh`, com `USING/CHECK fn_e_administrativo()`. A definição preservada desse helper verifica papel/atividade, sem relacionar a empresa do ator com a ausência/colaborador. O SQL `supabase/equipa_restringir_ausencias_horas_extra.sql:53` contém a mesma regra.

A auditoria aplicou somente a policy SELECT preservada à tabela sintética de anexos já criada pelo harness. O ator Administrativo da empresa B conseguiu ler metadados de anexos associados a doença da empresa A. No fim, a configuração temporária de RLS/grant/policy da fixture foi reposta. Nenhum objeto real foi tocado.

O candidato reutiliza os anexos e acrescenta guardas de confirmação/preservação, mas não corrige essa ACL. O precheck verifica existência/tipos/orfandade e compara o catálogo instalado, sem exigir ligação de tenant na policy documental. Preservar uma policy não comprova que seja segura para esta finalidade.

Impacto: confidencialidade dos metadados/URLs dos comprovativos entre empresas não está garantida. O teste não descarregou bytes nem prova a ACL atual do Storage. Diretor/Adjunto/Encarregado não recebem esses documentos pelo novo contexto ADM. A nova RPC de confirmação também recusa corretamente ator de outra empresa; isso não fecha a leitura direta existente dos anexos.

Recomendação, sem implementar: auditar/restringir o vínculo `ausencias_anexos → ausencias → colaboradores.empresa_id` e a autorização efetiva de acesso aos bytes antes de declarar a infraestrutura documental reutilizável em segurança. Se não estiver completa, manter confirmação final bloqueada de forma explícita.

Teste independente que falha: `reused document policy isolates metadata by company`. Trata-se de uma dependência legada agora reutilizada, não de uma nova policy criada pelo candidato.

### ADM-P2-01 — facto especial revisto continua apresentado como revisão pendente

**Confirmado em PostgreSQL local e browser nos três viewports.**

Depois de `special_review`, `special_reviewed_at` está preenchido e o contexto devolve `special_review_pending=false`. O resumo e Vencimentos deixam de contar essa pendência. Porém `folha_privado.linha` continua a devolver `overtime.estado='pending_rule'` para o dia especial sem HE. `analyseSheet` também deriva `pending_rule` somente de `specialDay`. A Folha apresenta tanto no cabeçalho como na pessoa “DIA ESPECIAL — REQUER REVISÃO”, enquanto mostra “0 pendentes · DIA COMPLETO”.

Origem: `supabase/folha_ponto_v2.sql`, projeção `overtime` de `linha`; `src/attendance-domain.js`, `analyseSheet`; `src/attendance-sheet.js:23` e `:31`. O detalhe de factos de Vencimentos também usa a mensagem de revisão sem distinguir facto já revisto.

Impacto: interpreta uma revisão já concluída como pendente e contradiz o estado operacional. Não é cálculo monetário ativo, nem motivo para apagar a indicação factual de dia especial.

Recomendação, sem implementar: separar “dia especial” factual de “revisão pendente/revisto” e de “regra monetária não instalada”; garantir a mesma projeção no backend, Folha e Vencimentos.

Teste independente que falha: `reviewed special day no longer claims a pending review`.

## C–L. Matriz funcional

| Área | Resultado | Evidência/limite |
|---|---|---|
| Janela A–H | PASS | Encarregado corrige hoje/ontem; +2 recusado. Administrativo +2 exige motivo. Correção muda entradas, saídas e intervalos, com antes/depois, ator, timestamp, request_id e revisão. |
| Horas em falta | PASS | Estado `missing`, resumo pendente, DIA COMPLETO falso e mesmo estado em factos de Vencimentos; zero ausência criada. Texto explícito preservado. Sem desconto automático. |
| Escritório | PASS | Intervalos reais; total abstrato recusado; 660 minutos preservados sem HE. Testes existentes de identidade própria e carga flexível passam. |
| Sábado/domingo/feriado | PASS factual / FAIL visual após revisão | Três datas separadas testadas; `special_day=true`; dia normal coletivo recusado; nenhuma taxa/montante criado. ADM-P2-01 após revisão. |
| Férias/consumo | PASS | Segunda–sexta 5; sexta–segunda 2; fins de semana/feriado conhecidos zero, nenhuma linha nesses dias; seleção parcial recusada. |
| Calendário | PASS local | Fim de semana determinístico; feriados somente configurados; calendário incompleto/ano não validado devolve consumo NULL e calendar_pending, prazo HE NULL. Calendário real não validado nesta tarefa. |
| Direito/saldo | PASS | Direito 17 com fonte aceito; 22 não imposto; transitado e adicionais com autorização/histórico; validade 30/04 do ano de utilização. Sem algoritmo rígido para contrato a termo. |
| Ausências | PASS funcional | Seis tipos conservados/adicionados; pendência visível; Encarregado não confirma; Administrativo confirma; sem inferência salarial. |
| Doença/documento | PASS confirmação / FAIL isolamento legado | Falta de anexo recusa; associação existente reutilizada, sem JSON/base64; último anexo protegido. RPC própria recusa outra empresa. Policy legada falha isolamento: ADM-P1-02. Bytes/Storage não testados. |
| Elegibilidade HE | PASS | Cargo RH/configuração; Pedreiro e Servente, Motorista não por defeito. Configuração auditada apenas Administrativo. Role operacional não é a fonte de elegibilidade. |
| Aprovar/validar HE | PASS escrita | Diretor/Adjunto aprova/rejeita; Administrativo valida/processa; Gerência não recebe a nova ação; revisão/superseded/reconciliação preservados. Leitura administrativa falha: ADM-P1-01. |
| Valores HE | PASS neutralização | Sem cálculo, percentagem, preço/override monetário executável. `validated_pending_rule` preserva a limitação financeira; não equivale a montante calculado. |
| Processamento HE | PASS escrita / FAIL leitura | Regista ator/data, replay sem duplicação; não cria pagamento nem escreve no Mapa de Vencimentos. Alerta interno para Administrativo da mesma empresa, terceiro útil apenas com calendário validado; sem email real. Projeção indevida nos perfis técnicos. |
| Vencimentos/payload | PASS | Sem prémio; premium recusado; km quantidade, allowance euros, note manual; sem HE ou injeção automática de observação. |
| Validar/fechar/reabrir | PASS | Literal Administrativo; não-admin recusado; pendências/calendário/km/ajudas impedem validar/fechar. Sem auto-fecho. |
| Recibos | PASS | Fecho explícito regista recibos_recebidos_em/por; reabertura auditada, sem motivo obrigatório; preserva históricos. |
| Exportadores | PASS neutralização | Exportação oficial recusada; formato HE/montantes não inventados. Nenhum ficheiro financeiro oficial gerado. |

Nota operacional existente: HE já validada com prazo NULL não ganha prazo automaticamente quando alguém completar posteriormente o calendário. A ausência de prazo permanece explícita; não é prova de que o controlo de processamento possa ser dispensado.

## M. Permissões e raw JSON

PASS: contexto de Encarregado/Diretor/Adjunto sem chaves `people`, `live_facts`, `config`, `entitlements`, `vacations`, `payroll` ou `absences`; consulta administrativa com colaborador/competência recusada; Encarregado sem lista HE. Âmbito da obra preservado pelas suites anteriores.

FAIL: campos aninhados HE/histórico administrativo para Diretor/Adjunto e policy legada de anexos entre empresas. Uma allowlist apenas das chaves de topo foi insuficiente; o teste novo inspeciona os campos aninhados e metadados documentais.

Grants/RLS locais: novas tabelas administrativas sem DML direto autenticado; helpers privados não executáveis pelo cliente. As novas ações sensíveis verificam `folha_privado.adm()` antes do lookup do replay. Isso não compensa falhas de leitura.

## N. Replay e concorrência

PASS independente:

- Oito novas ações privilegiadas recusam replay depois de Administrativo passar a Gestão da Plataforma.
- Redução de permissão entre preview e confirmação recusa `configure_he_eligibility`, sem mudar a revisão.
- Duas correções concorrentes: um commit, uma recusa stale, uma revisão/história adicional.
- Dois fechos concorrentes: um fecho, um recibo/ator, um evento; replay do vencedor não duplica.
- Stale revision/fonte/token e remoção de responsabilidade continuam cobertos pelas suites preservadas.

Lock de escrita comum `61001,1`, locks de linha e token/revisão coordenam as ações; os testes usam duas ligações PostgreSQL reais à base efémera. Isolamentos não suportados continuam a exigir READ COMMITTED.

## O. Scripts e regressões

Revisão de precheck/backup/migration/postcheck/rollback: sem alterações nesta auditoria. Precheck é READ ONLY; backup privado inclui constraints/anexos; migrations locais transacionais; postcheck compara legado/ACLs/dados; rollback recusa factos existentes e não usa CASCADE indiscriminado. Instalação sintética/postcheck, recusa de rollback com dados, rollback vazio e compatibilidade Fase B continuam PASS.

Limite: a fixture principal de ausências não reproduz todas as CHECKs do catálogo real; o ramo de extensão/restauração de cada CHECK real não fica provado só pelo rollback vazio. Catálogo real continua gate. Além disso, os scripts não impedem ADM-P1-01/02 ou ADM-P2-01; o PASS sintático/estrutural não torna o pacote apto.

Uma passagem consolidada das 41 suites críticas foi executada; depois repetiu-se somente o backend afetado pelos novos testes documentais e pela recolha de ambos os papéis. Contagens usam a última execução de cada suite, não a soma das repetições. Cobertura: Folha, reconciliação, férias, ausências, HE, Vencimentos, Escritório, legado, externos, Quadro, Planeamento, RH, sessão, Medicina, Financeiro, RNC, Viaturas e scripts/Fase B sintética.

Browser local, tráfego externo interceptado:

| Suite preservada | Resultado |
|---|---|
| ADM | 48 grupos PASS |
| Estados visíveis | 126 PASS |
| Reconciliação | 81 PASS |
| Folha | 57 PASS |
| Consolidação | 51 grupos PASS |
| Sessão | 7 PASS |
| Planeamento/custos | 33 PASS |
| RH, Quadro, Medicina, Viaturas, RNC | PASS |

Auditoria browser independente: **10 PASS / 9 FAIL**, zero pageErrors. Os 9 FAIL são seis reproduções da exposição HE (dois perfis × três viewports) e três da contradição do dia revisto. Não são nove defeitos diferentes. Screenshots locais sintéticos foram inspecionados; não incorporam dados reais nem foram enviados a serviços externos.

## P. Contagens finais

- Base/regressões preservadas: continuam verdes; três SKIPs legítimos mantidos.
- Novos testes PostgreSQL independentes: **10 PASS / 4 FAIL**, 14 grupos.
- Última execução do harness backend: **104 PASS / 5 FAIL / 0 SKIP**, 109 testes. Quatro FAIL são asserções independentes; o quinto é o agregador que falha porque contém esses subtestes.
- Consolidado das últimas execuções das 41 suites: **491 PASS / 5 FAIL / 3 SKIP**, 499 testes. Não somar o browser a estes testes Node/PostgreSQL.
- Browser independente: **10 PASS / 9 FAIL**, como discriminado acima.
- `git diff --check`: PASS.

Os testes que exprimem os requisitos ficam intencionalmente vermelhos para preservar o achado; não foram enfraquecidos para fazer o candidato passar. Os erros de fixture inicial do browser (data de resposta diferente da pedida) foram corrigidos no teste, sem mudança de produto; só a execução final válida fundamenta estes resultados.

## Sweep de contradições e R. Decisão

Confirmadas: revisão especial concluída ainda marcada pending_rule/REQUER REVISÃO; processamento administrativo entregue a perfis operacionais; dependência documental sem tenant na policy preservada.

Não encontrados nos cenários executados: +2 Encarregado permitido, correção administrativa sem motivo, férias em fins de semana geradas pelo intervalo, HE no mapa salarial, prémio editável/aceito, direito automático 22, cargo confundido com login, monetização ativa, fecho automático ou prazo com calendário não validado.

**NO-GO LOCAL para avançar à preparação do rollout.**

É necessária correção específica dos dois P1 e do P2, seguida de reauditoria. Produto não corrigido nesta tarefa. Calendário/catálogo reais mantêm-se pendentes; nenhuma tentativa de acesso por método bloqueado foi feita.
