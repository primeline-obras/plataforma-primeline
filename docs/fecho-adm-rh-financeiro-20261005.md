# Fecho ADM/RH/Financeiro e preparação do Pacote 2

Data: 05/10/2026. Branch local: `feat/adm-rh-fecho-folha-ponto-20261005`.
Base: `3df019a2f2813c0cbf7f36a8d13000431d33dd50`, main publicado segundo o checkpoint validado.

## Conclusão

**NO-GO para Fase B real e para publicar esta branch.** Existe implementação frontend local da nova Folha, mas os seus contratos de backend ainda não estão implementados/confirmados. HE, férias e vencimentos têm funções puras e especificação; não têm novos fluxos persistentes completos. Não declarar estes módulos operacionalmente fechados.

Não foi executado SQL em produção, criado backup, alterado perfil, feito merge, push ou deploy nesta tarefa. Nenhum ficheiro SQL foi alterado ou criado. O histórico legado não foi convertido ou reescrito.

### Evidência e limites

- Repositório, scripts existentes, relatórios e snapshot de catálogo de **04/10/2026** foram revistos. O snapshot é evidência datada, não uma reconfirmação da BD em 05/10.
- A aba existente do Supabase mostra o projeto `znttyadndpkxuekhjamd`, Primeline-Obras, autenticado, no SQL Editor. O MCP consegue obter o snapshot, mas rejeita o editor como elemento inexistente; avaliações anteriores também tiveram timeout. Nenhuma consulta desta retoma chegou a executar.
- Catálogo atual, contagens, grants, owners, policies, triggers e marcador privado: **VALIDAÇÃO BLOQUEADA PELO AMBIENTE**. Não atribuir a falha a falta de login nem repetir autenticação.
- O checkpoint fornecido regista 227 alocações preservadas, 100 movimentos após o teste Gestão e ausência de marcador B. Estes números **não foram reconfirmados agora**.
- Os testes browser são locais, com dados sintéticos e tráfego externo interceptado. Não demonstram autorização instalada das novas RPCs nem substituem teste de produção.

## A. Mapa completo das pendências

Classes: **A** decidido e implementável; **B** estruturável com regra/infraestrutura pendente; **C** depende realmente do ADM; **D** etapa futura. “Pode agora” refere-se a implementação local, não autorização de produção.

| Item | Classe e estado | Dependência | Risco | Pode agora? | Bloqueia |
|---|---|---|---|---|---|
| Quadro v1 / hotfix de âmbito e sessão | Fechado no checkpoint; regressões locais PASS | Reconfirmação real | Reabrir permissões já corrigidas | Não precisa refazer | Nada novo identificado no frontend existente |
| Fase B | A, scripts existentes incompatíveis com baseline anterior ao hotfix | Catálogo atual e consolidação auditada dos gates | Aceitar drift ou restaurar ACL antiga | Diagnóstico local sim; rollout não | Fase B |
| Folha pessoa/dia, registo progressivo | A, UI e cliente locais implementados | Quatro contratos v2 e persistência controlada | Gravar presença implícita ou fingir sucesso | Frontend sim; backend após catálogo | Publicação do Pacote 2 |
| Horário normal por obra | B, consumidor configurável | Persistência/configuração por obra | Confundir sugestão com facto realizado | Estrutura sim | Ações coletivas com horário normal |
| Janela de correção | C, parametrização pura | Decisão ADM | Permitir alteração tardia sem regra | Estrutura sim; regra não | Correção pelo Encarregado |
| Alocação e transferência na Folha | A, UI com preview e confirmação | Adapter controlado v1, revisão e âmbito no backend | Transferência silenciosa ou parcial | Frontend sim | Fluxo real adicionar/transferir |
| Externos | A/B, UI separada e contrato | Entidade própria, fornecedor autorizado, histórico | Transformar externo em colaborador/payroll | Frontend sim | Persistência de externos |
| Potencial HE e cadeia de validação | A/B, funções puras | Origem única da Folha, RPCs e responsabilidade por obra | Duplicar HE manual ou pagar automaticamente | Estrutura sim | Processo HE completo |
| Sábado/domingo/feriado | C, estado pendente | Classificação e processamento ADM | Inventar adicionais/consumo | Factos sim; regra não | Efeito financeiro e consumo de dias especiais |
| Férias não contíguas e remoção | A/B, seleção pura; UI legado existente | Operação atómica e histórico | Escritas sequenciais incompletas | Estrutura sim | Novo fluxo persistente de férias |
| Saldo anual e override | B/C, especificado | Origem do direito anual, consumo aprovado, revisão | Saldo fictício | Contrato sim | Saldo e override reais |
| Ausência versus trabalho | A, estado de regularização implementado | Processo de regularização backend | Apagar ausência ou aceitar trabalho silenciosamente | Frontend sim | Fecho do dia em conflito |
| Medicina | Fechado; regressões PASS | Backend já aplicado no checkpoint | Duplicar fonte de verdade | Não precisa refazer | Nenhum novo bloqueio |
| Cadastro RH | Fechado; browser PASS, três testes opcionais SKIP | Dependências opcionais de teste | Reabrir cadastro/contratos | Não precisa refazer | Evidência local desses três testes |
| Mapa de Vencimentos | B/C, factos e estados puros | Regras de fecho e ficheiro oficial | Inventar salário ou exportação oficial | Estrutura sim | Processamento/exportação final |
| PDF original antes de pagar | Já implementado | Original disponível | Confundir URL com imutabilidade | Testar/reutilizar | Nada novo no botão existente |
| PDF anotado aprovado/pago | D, especificado | Cópia derivada, Storage, hash e evidência da ação | Sobrescrever original ou certificar documento falso | Desenho sim | Garantia documental completa |
| Apagar fatura administrativo | Já implementado por RPC | Permissão backend existente | Criar segundo caminho de DELETE | Não duplicar | Nada novo identificado |
| Cabeçalho versus itens | Já compara valores e pede confirmação | Reconciliação explícita | Corrigir valores sem validação | Reutilizar | Casos reais divergentes |
| Despesas gerais | Bloqueio deliberado preservado | Modelo tenant de débitos diretos | Importar dados sem empresa | Não reabrir | Importação desse ramo |
| Cargo RH versus perfil operacional | Regra existente preservada | Cadastro autorizado e responsabilidades | Alterar cargo contratual para dar acesso | Diagnóstico sim; dados não | Alteração real de Carolina/José |
| Tarefa concluída nas listas ativas | A, filtro corrigido | Estado final do Planeamento | Confundir 100% com concluído | Sim | Nada no filtro local |
| Alertas de tarefas concluídas | A/B, especificado | Reconciliador backend por origem | Resolver/apagar alertas indevidos | Contrato sim | Fecho integral dos alertas |
| Conclusão reportada pelo Encarregado | A/B, especificado | Estado reportado e confirmação do Diretor | Reativar antigo writer revogado | Contrato sim | Novo fluxo de reporte |
| PDF/Excel de Folha por obra/mês | D | Fonte v2 reconciliada e formato | Exportar factos incompletos | Preparação sim | Exportação nova |

## B. O que foi fechado nesta ronda

- Decidido o nome na navegação e no título: **FOLHA DE PONTO**.
- Implementados e testados o cálculo de factos, estados e UX diária da nova Folha.
- Eliminada a inclusão de tarefas concluídas na lista ativa da semana do Plano de Ação. O calendário histórico continua a mostrá-las como concluídas.
- Confirmado que o frontend de exclusão administrativa de faturas e o acesso ao PDF original **já existiam**; não foram duplicados.
- Registada a incompatibilidade concreta dos gates da Fase B após o hotfix.
- Reduzidas as decisões ADM ainda necessárias a três grupos, sem inventar regras.

Não foram fechadas a instalação backend do Pacote 2, a autorização tenant das novas RPCs, as garantias de Storage ou a reconfirmação real da Fase B.

## C. Implementação local

| Ficheiro | Alteração |
|---|---|
| `src/attendance-domain.js` | Factos dos intervalos, estados, datas exatas, relógio Lisboa, horário configurável, correção parametrizada, seleção de férias, transições HE/vencimentos e filtro de tarefas ativas |
| `src/attendance-client.js` | Cliente v2; preview/confirmação, request estável, recusa de resposta incompleta, ausência de fallback/DML direto |
| `src/attendance-sheet.js` | Uma obra/dia, lista vertical, entradas/saídas progressivas, ações coletivas, candidatos disponíveis, transferência confirmada, externos separados e histórico |
| `src/attendance-sheet.css` | Layout adaptável, botões de pelo menos 48px, lista sem grelha semanal nem scroll horizontal obrigatório |
| `src/app.js` | Nome e ligação ao módulo novo; cache do Plano de Ação |
| `index.html` | CSS da Folha e versão do asset da aplicação |
| `src/action-plan.js` | Semana baseada em tarefas ativas, inclui informação de arquivo e mensagem de erro sem instrução SQL ao utilizador |
| `tests/attendance-domain.test.mjs` | 21 testes de factos, estados, contratos e erros |
| `tests/attendance-sheet-browser.mjs` | 36 grupos browser, dados sintéticos, três viewports, seis perfis |
| `tests/phase-b-hotfix-compatibility.test.mjs` | Prova estática do gate incompatível; teste PostgreSQL preparado, execução bloqueada por servidor local incompleto |
| `tests/foreman-action-plan.test.mjs` | Expectativa de áreas atualizada para Calendar/Quadro já aprovados no Pacote 1; permissões do produto não foram alteradas |

O novo módulo está ligado na branch local. Sem backend v2, mostra indisponibilidade: **não publicar esta branch enquanto esse backend não estiver pronto**. O ficheiro `src/attendance.js` e os SQL legados permanecem para referência histórica; não estão no novo caminho de escrita.

## D. O que ficou apenas estruturado

- HE: transições e estado neutro; sem novas linhas, aprovações persistentes ou pagamentos.
- Férias: seleção não contígua, intervalo, remoção e consumo desconhecido em dia especial; sem novo editor persistente, saldo anual ou override instalado.
- Vencimentos: factos e transições; sem ecrã completo, fecho persistente ou XLSX oficial.
- Externos: UI e payload separados; sem entidade/RPC real instalada.
- Alertas/tarefas: contrato de reporte e reconciliação; sem reativar RPC revogada ou resolver alertas reais.
- Documentos financeiros: desenho de cópia derivada; sem selo gráfico, upload de cópia ou alteração de Storage.

As funções puras não substituem autorização por empresa/obra, auditoria, locks ou persistência. Os testes de papel nessas funções verificam a regra local, não a segurança da BD.

## E–F. Decisões ADM ainda necessárias

1. **Janela de correção do Encarregado:** número de dias e tratamento das exceções. `days=null` não assume “dia seguinte” e não concede correção. O backend deve devolver `can_write` e aplicar a mesma parametrização; o frontend não autoriza pela função RH.
2. **Dias especiais:** classificação de sábado/domingo/feriado, consumo para férias e processamento de HE. O facto trabalhado pode existir sem taxa ou pagamento; `pending_rule` continua sem efeito financeiro.
3. **Fecho mensal:** pendências impeditivas, autoridade de validação/fecho/reabertura e processamento de campos manuais. Necessário também fornecer o modelo oficial do Mapa de Vencimentos para exportar.

Não é necessária nova decisão de negócio para criar alocação diária explícita ou transferir pessoa entre obras com confirmação: isto foi decidido no pedido atual. A implementação backend segura continua necessária.

## G. Fase B — NO-GO

### Incompatibilidade demonstrada no repositório

`quadro_controlado_fase_b_precheck.sql` e `quadro_controlado_fase_b.sql` comparam integralmente as policies de `quadro_pessoal_alocacao`/`quadro_pessoal_movimentos` com `primeline_backup.quadro_policies_20261001` e lançam `POSTCHECK_FAILED: policy legado alterado na Fase A` em qualquer diferença.

`encarregado_escopo_migration.sql`, que integra o hotfix aplicado segundo o checkpoint, acrescenta a policy restritiva `encarregado_sem_dml_direto` em `quadro_pessoal_alocacao`. A baseline A anterior não contém essa proteção. O forward-fix B repete o comparador antigo. O fingerprint privado da instalação também exige reconfirmação das definições entretanto alteradas pelo hotfix.

Isto é um impedimento de compatibilidade, não motivo para remover a policy ou tornar o precheck permissivo. A prova estática passou; a reprodução num PostgreSQL efémero não pôde executar nesta máquina.

### Ordem local a consolidar antes de qualquer autorização real

1. Recolher por leitura a estrutura **pós-hotfix**: policies, grants de tabela/coluna, owners, RLS, writers, triggers, índices, dependências e identidade privada A.
2. Comparar com o backup A e classificar cada delta contra o hotfix auditado; qualquer diferença não explicada exige parar.
3. Consolidar os cinco scripts B para preservar o hotfix, RPCs v1, Cadastro RH e dívida intencional do Ponto. Não executar simplesmente os scripts antigos e não regenerar fingerprint para forçar passagem.
4. Testar a sequência em PostgreSQL compatível: precheck → backup → migration → postcheck; rollback deve repor o estado pós-hotfix aprovado e invalidar autorizações antigas.
5. Concluir o gate real do Encarregado já proposto, com autorização específica para qualquer escrita e informação prévia dos alertas. Ainda não executado nesta tarefa.
6. Só então pedir autorização para o marcador privado correspondente à instalação/tentativa atual e para o rollout B. Backend/marker/Backup B não estão autorizados agora.

Os scripts antigos continuam disponíveis, sem alterações nesta ronda. **Não há um pacote B pós-hotfix pronto para aplicar.**

## H. Folha de Ponto — estado e contratos propostos

### Comportamento implementado

- Uma obra/data, lista vertical com nome, função, estado e Registar/Editar/Histórico.
- Sem consulta ao Quadro global nem herança da última alocação anterior. Os candidatos mostram apenas contexto pontual autorizado.
- Entrada sem saída = Em aberto; minutos fechados não inventam a saída futura. Datas/horas futuras, ordem inválida e sobreposição são recusadas.
- Horário por obra é recebido da RPC. 08–12/13–17 é uma sugestão de configuração futura, não presença automática. Um turno normal deslocado com 8h não cria HE.
- Ações coletivas excluem ausências e pessoas sem autorização. A conclusão coletiva procura o intervalo normal correspondente à entrada, incluindo uma única entrada de tarde; entradas fora do horário exigem edição individual.
- Férias têm zero horas esperadas. Trabalho em dia de ausência vira Regularização, sem apagar a ausência.
- Preview e confirmação usam o mesmo `request_id`. Erro de revisão recarrega e não repete escrita automaticamente. Erro de rede ambíguo mantém o request para repetição idempotente explícita.
- Registo normal não tem aprovação fictícia. O estado derivado não é autorização financeira.

### RPCs: proposta de contrato, não objetos instalados

Assinaturas abaixo devem ser verificadas/construídas no backend após recuperar o catálogo atual. Todas autenticam utilizador ativo por `auth.uid()`, verificam empresa e responsabilidade por obra; o cliente não envia papel/empresa como autoridade.

#### 1. `fn_folha_contexto_v2(p_data date, p_obra_id uuid DEFAULT NULL) → jsonb`

Payload: `{ "p_data": "AAAA-MM-DD", "p_obra_id": "UUID ou null" }`.

Resposta mínima consumida:

```json
{
  "version": 2,
  "date": "AAAA-MM-DD",
  "work_id": "UUID ou null",
  "works": [{"id":"UUID","number":120,"name":"obra autorizada"}],
  "permissions": {"write":false,"external_write":false},
  "schedule": {"intervals":[{"period":"manha","start":"08:00","end":"12:00"},{"period":"tarde","start":"13:00","end":"17:00"}]},
  "special_day": false,
  "providers": [{"id":"UUID","name":"fornecedor autorizado"}],
  "rows": [{"person_id":"UUID","name":"nome autorizado","role":"cargo formal","period":"dia_inteiro","revision":0,"can_write":false,"expected_minutes":480,"absence":null,"sheet":null}],
  "external_rows": []
}
```

`schedule` pode ser null; nesse caso não inventar horário. `sheet`, quando existe, contém `intervals:[{start,end}]` e `note`; `end` pode ser null. `absence` contém tipo e origem efetiva. Cada externo tem identidade própria, `provider_name`, revisão, autorização e folha; nunca é inserido em `colaboradores`.

Ao pedir obra null, devolver apenas obras permitidas e nenhuma lista global de pessoas. Ao pedir uma obra, linhas só desse âmbito/data, incluindo histórico legítimo de pessoas entretanto inativas. Horário/ausências/dias especiais devem vir de fontes reconciliadas, não de inferência do cliente.

Chamadas: abrir/atualizar Folha, trocar data/obra, depois de operação confirmada ou `STALE_REVISION`. Erros: `42501`/403, data inválida, obra não autorizada, sessão expirada, contrato indisponível 404/PGRST202. Ausência de RPC mostra indisponibilidade, sem fallback legado.

#### 2. `fn_folha_pessoas_v2(p_data date, p_obra_id uuid) → jsonb`

Payload: `{ "p_data":"AAAA-MM-DD", "p_obra_id":"UUID" }`.

Resposta: `{ "version":2, "people":[{"person_id":"UUID","name":"nome autorizado","recent":true,"current_work":null,"can_allocate":true,"can_transfer":false,"allocation_revision":0}] }`.

Quando já alocado: `current_work:{id,label,type}`; `type` distingue obra/escritório. Não devolver matriz de outras obras, RH sensível ou custo. Preferir disponíveis, depois equipa recente/pesquisa. Escritório ou destino fora do âmbito não é transferido por este caminho.

Chamada: “Adicionar pessoa à obra”. Erros de autorização/data/âmbito iguais ao contexto. A autorização deve ser novamente verificada na escrita; flags do preview não são poderes permanentes.

#### 3. `fn_folha_operar_v2(p_acao text, p_dados jsonb, p_confirmar boolean DEFAULT false, p_versao text DEFAULT NULL) → jsonb`

Envelope exato: `{p_acao, p_dados, p_confirmar, p_versao}`. Todas as ações enviam em `p_dados`: `{version:2,request_id:UUID,date:"AAAA-MM-DD",work_id:UUID}` mais os campos abaixo:

| Ação | Campos adicionais |
|---|---|
| `save` | `key:{kind:"primeline" ou "external",person_id,work_id,date}`, `expected_revision`, `intervals:[{start,end}]`, `note`, `reason` (obrigatório na correção) |
| `bulk` | `items:[{key,expected_revision,intervals}]`; mesma obra/data, tudo atómico |
| `allocate` | `person_id`, `period:"manha"/"tarde"/"dia_inteiro"`, `expected_allocation_revision`, `source_work_id:null` |
| `transfer` | Os mesmos campos; `source_work_id` identifica explicitamente a obra de origem |
| `external_register` | `provider_id`, `name`, `note`; identidade externa criada pelo servidor |

Preview: `p_confirmar:false,p_versao:null`; resposta `{version:2,committed:false,versao:"token não vazio",summary:"efeito, conflito e alertas previstos"}`. Preview não escreve, não gera alertas nem reserva operação persistente.

Confirmação: mesmos ação/dados/request, `p_confirmar:true,p_versao:"token do preview"`; resposta `{version:2,committed:true,request_id:"o mesmo UUID",changed_keys:[{kind,person_id,work_id,date,revision}]}`. A lista é não vazia, inclusive no replay. O cliente verifica confirmação, request, tipo/pessoa/data/obra das chaves e presença de cada pessoa prevista no destino; o backend tem de garantir o conteúdo exato, revisions e atomicidade.

Guardas necessárias:

- Lock de pessoa/data e revisions, com ordem estável em operação coletiva; revalidar autorização, ausência, alocação e token dentro da transação.
- `(empresa,ator,request_id)` único com hash de payload; replay devolve resultado original, payload diferente recusa `IDEMPOTENCY_CONFLICT`.
- `save` preserva autoria/histórico, não sobrescreve identidade de outro trabalhador/obra e aplica janela parametrizada; não abre permissões de RH administrativo.
- `allocate`/`transfer` reutilizam o motor controlado do Quadro v1, sem DML direto pelo browser; transferência altera explicitamente origem/destino e atualiza revisão/movimentos/auditoria. Não chamar o writer antigo como fallback.
- `bulk` valida todos os elementos antes de qualquer commit; conflito num elemento reverte o conjunto.
- Externos devem pertencer à mesma empresa e fornecedor autorizado. Não entram no Mapa de Vencimentos Primeline nem criam custo/pagamento/auto automaticamente.
- Auditoria e alertas derivados só após confirmação, sem duplicar no replay. O preview deve explicar alertas/destinatários antes de autorizar teste real.

Erros funcionais previstos: `42501`/403 (inativo/papel/empresa/obra), `STALE_REVISION`/409 ou `40001`, `IDEMPOTENCY_CONFLICT`, `PREVIEW_EXPIRED`, `INVALID_INTERVAL`, `FUTURE_TIME`, `CORRECTION_WINDOW_UNCONFIGURED`, `CORRECTION_WINDOW_EXPIRED`, `ALLOCATION_CONFLICT`, `ABSENCE_CONFLICT`, `LEGACY_CONFLICT`, `INVALID_PROVIDER`; nenhum pode devolver sucesso de escrita parcial. Conflito ausência/trabalho pode produzir uma folha em regularização apenas quando o protocolo o permitir explicitamente.

Chamadas: guardar, marcar equipa presente, completar equipa, adicionar pessoa, confirmar transferência e registar externo. Não há POST/PATCH/DELETE de tabela no cliente novo.

#### 4. `fn_folha_historico_v2(p_chave jsonb) → jsonb`

Payload: `{p_chave:{kind,person_id,work_id,date}}`.

Resposta: `{version:2,events:[{at,action,reason}]}`; o backend deverá incluir identificadores de origem, autoria ocupacional autorizada e revisão antes/depois. Não devolver dados de terceiros ou clínicos. Chamada: botão Histórico. Erros: chave inválida, `42501`, sessão/contrato indisponível.

### Testes dos contratos

Mocks cobrem contexto de obra/data diferentes, 404/403/500, resposta incompleta, preview/confirmação, request estável, repetição após falha de rede, stale sem retry automático, ausência de DML, lista disponível/transferência/escritório, histórico e separação de externo. **Permissões backend, tenant, locks e replay persistente destes contratos ainda não estão comprovados.**

## I. Horas Extraordinárias

`analyseSheet` identifica potencial apenas para obra, intervalos fechados acima de 480 minutos. Escritório não gera HE automaticamente; dia especial fica pendente; ausência/trabalho fica em regularização. Horas deslocadas de 8h continuam normais.

`overtimeTransition` define `potential → pending_validation/rejected` por Diretor/Adjunto e `pending_validation → validated_pending_rule` por ADM/Gestão/Gerência. Não calcula taxa nem estado pago.

Pendência técnica: origem única `(folha, revisão)` e reconciliação ao corrigir folha; aprovação pela responsabilidade real da obra, validação administrativa e auditoria. A tabela legada `horas_extraordinarias` não tem esses vínculos/estados no snapshot de 04/10. O lançamento manual existente não foi alterado. Não ativar geração automática antes de impedir duplicação com esse fluxo.

## J. Férias/Ausências

O frontend existente já tem consulta/calendário e edição de dias. A seleção pura nova suporta dias não contíguos, intervalos e remoção. Dia especial com regra não definida devolve consumo null, sem inventar saldo.

A persistência legada usa operações sequenciais em `ausencias`; não foi redesenhada nesta ronda. Para o novo editor, exigir RPC atómica com pessoa/ano, lista de datas adicionadas/removidas, motivo de override, expected revision e request, além de direito anual com origem. Saldo = direito confirmado − consumo confirmado; não assumir 22 dias ou consumo de fins de semana. Justificação, documento e histórico permanecem por origem.

Baixa SS–Doença não deve ser inventada a partir de uma falta genérica: o snapshot/frontend enumera férias e faltas justificadas/injustificadas, sem garantir fonte estruturada dessa baixa. Confirmar o tipo/origem na BD atual antes da integração salarial.

## K. Mapa dos Vencimentos

Estrutura preparada: `payrollFacts` fornece minutos fechados, dias em aberto e ausências com tipo/ID; `payrollTransition` separa rascunho, validado, fechado e exportado. Sem folha válida não há horas presumidas; não inferir execução da alocação.

| Campo | Origem/controlo |
|---|---|
| Horas/dias trabalhados | Folha atual confirmada; preservar source/revisão |
| Férias | Ausência efetiva e consumo aprovado |
| Baixa SS–Doença | Registo estruturado específico, a confirmar |
| Falta injustificada / justificada não remunerada | Tipo e estado efetivos da ausência |
| Prémio | Manual ADM, motivo e auditoria |
| Subsídio Deslocação (Km) | Manual ADM; não calcular taxa inexistente |
| Ajudas de Custo Nacional | Manual ADM, origem/motivo |
| Observações | ADM, sem diagnóstico clínico |

Não existe ainda UI/RPC de mapa mensal persistente nem template oficial ligado. Fecho exige resolver pendências segundo regra ADM; exportação exige modelo oficial. Não apresentar a função pura como processamento salarial completo.

## L. Financeiro/Faturas

Confirmado no código:

- `renderInvoiceDetail` oferece **ABRIR PDF ORIGINAL**, e os cartões têm **VER PDF**.
- `openDeleteInvoiceDialog`/`deleteSelectedInvoice` já chamam `fn_apagar_fatura_administrativo` com `{p_fatura_id}`; conservadas confirmação e recarga. Não criar DELETE direto alternativo.
- Divergência cabeçalho/artigos já é comparada com arredondamento monetário e confirmação explícita; não altera valores automaticamente nesta tarefa.
- Despesas gerais de `fn_importar_mapa_financeiro_xlsx` continuam explicitamente bloqueadas antes de escrita; regressão estática PASS.

Ter URL do original não prova preservação dos bytes. Para “APROVADO POR”/“PAGO”, produzir uma **cópia derivada**, com original intacto, hash de original e derivado, identidade/timestamp da ação real, object key nova, controlo de acesso e auditoria. Aprovação/pagamento não podem ser inferidos pela geração do PDF. Esta etapa depende de Storage e contratos documentais; nenhum selo/cópia foi gerado.

## M. Mão de obra externa

UI separa Pessoal Primeline e Mão de Obra Externa. Permissão para registar vem do contexto, fornecedor limitado ao âmbito. Intervalos, observação e histórico usam identidade `kind:external`. Browser confirma que a criação sintética externa não aumenta a lista Primeline e que a edição mantém a chave externa.

Entidade recomendada: identidade externa por empresa/fornecedor e presença por obra/data, com revisão, autoria, intervalos e histórico. Vínculo futuro ao auto do fornecedor separado; não converter presença em custo comprometido, fatura ou pagamento. Sem tabela/RPC instalada, não há gravação operacional real.

## N. Planeamento, tarefas e perfis

Conclusão final é `planeamento_itens.estado='concluido'`; 100% isolado não conclui tarefa. `activePlanningTasks` exclui concluídas/arquivadas da prioridade/semana, mantendo calendário histórico. O consumo passou a pedir `arquivado_em`, coluna presente no snapshot de 04/10.

O reporte do Encarregado precisa de registo separado com motivo, autoria, revision/request e confirmação pelo Diretor no Planeamento; não foi reativado `fn_atualizar_tarefa_encarregado`. A reconciliação de alertas deve usar a origem da tarefa e fechar apenas pendentes pertinentes, preservando resolvidos/histórico. Não foi implementada no backend nem simulada no frontend.

Cargo formal RH não controla acesso. Manter `utilizadores.funcao` e `obra_responsaveis` como fontes operacionais. Carolina formal Adjunta e José formal Preparador, operacionalmente Diretores segundo o requisito fornecido: pendência de cadastro autorizada separadamente, não uma alteração feita aqui. Sem reconfirmação real, não afirmar lista atual de obras ou perfis alterados.

## O. Testes e resultados

### Node — última execução

Grupo de 19 ficheiros: **94 testes, 91 PASS, 0 FAIL, 3 SKIP**:

`access-control`, `session-boundary`, `session-isolation`, `foreman-scope`, `medicine-client`, `rh-cadastro`, `workforce-allocation-client`, `attendance-domain`, `absences-workflow`, `overtime-workflow`, `invoice-delete-administrative`, `invoice-pending-detail-approval`, `planning-operational`, `foreman-action-plan`, `rnc-module`, `vehicle-assignment-client`, `finance-operational-access`, `writers-economicos-final-static`, `adjunto-access-parity` (em `tests`, extensão `.test.mjs`).

Os três SKIP são os casos opcionais RH de PGlite/cadastro atómico e dois casos DOM que dependem de `RH_TEST_DEPS` com PGlite/jsdom. Não foram contados como PASS. O browser RH independente executou os quatro cenários de correções RH já fechadas, mas não substitui esses três testes.

Compatibilidade Fase B: **3 testes, 2 PASS, 0 FAIL, 1 SKIP** na execução final. Total Node destes dois grupos: **97, 93 PASS, 0 FAIL, 4 SKIP**.

A primeira tentativa do teste PostgreSQL falhou ao inicializar: erro de restricted token e `C:/Program Files/PostgreSQL/17/share/postgres.bki` inexistente. O teste agora verifica esse pré-requisito e assinala SKIP explicitamente. O cliente local é 17.11; não foi criado servidor nem executada prova dinâmica do comparador. As suites históricas que exigem PostgreSQL exato 17.6 não foram declaradas executadas nesta ronda.

### Browser — local/sintético

| Suite | Resultado |
|---|---|
| `attendance-sheet-browser.mjs` | 36 grupos PASS, 0 FAIL, 0 pageErrors; Encarregado/Diretor/Adjunto/Administrativo/Gestão/Financeiro em 1440×900, 820×1180 e 390×844; CSS da aplicação incluído |
| `session-boundary-browser.mjs` | 7 cenários PASS: Gestão↔Encarregado, Diretor→Encarregado, logout, expiração e mudança de identidade |
| `planning-cost-access-browser.mjs` | 33 PASS, 0 FAIL; papéis/viewports, remoção de custos ao restringir sessão, erros legítimos 403/500 visíveis |
| `medicine-browser.mjs` | PASS: ficha, histórico, NULL, vencimento, replay, correção/stale, anulação, inativo, papéis, viewports, sem DML |
| `rh-frontend-browser.mjs` | PASS RH-01/RH-02/RH-08/RH-15, incluindo 49 combinações de permissão e três viewports |
| `workforce-controlled-browser.mjs` | PASS data explícita, recusa/resposta incompleta, botões por âmbito, retirar sem DML e três viewports |

Não somar “grupos browser”, ficheiros que imprimem PASS e testes Node como se fossem a mesma unidade. Consoles sem exceções relevantes nos harnesses concluídos; chamadas de escrita só mocks, com tráfego externo interceptado.

Screenshots locais sintéticos da Folha: `C:\Users\conta\AppData\Local\Temp\primeline-folha-v2-synthetic`. Inspeção visual desktop/mobile e verificações automáticas de largura/touch targets. Não são screenshots de produção nem prova do layout completo com sessão real.

`git diff --check`: PASS na verificação final. SQL/backend existentes não alterados.

## P. Regressões

Nenhuma regressão nova confirmada nas suites frontend executadas. O teste antigo de áreas do Encarregado foi atualizado à regra Calendar/Quadro já implementada e documentada; nenhum papel ganhou acesso por esse ajuste.

A nova Folha **não é uma substituição publicável ainda**: sem RPCs v2, o painel fica indisponível por desenho, e os relatórios mensais antigos não foram portados para esse painel. Isto é uma dependência de entrega, não sucesso funcional em produção. Medicina, Quadro, faturas e cadastro não tiveram novos writers introduzidos.

## Q. Riscos restantes

1. Catálogo real atual não recolhido por falha do MCP; não há nova garantia de tenant/grants/owners nesta ronda.
2. Gate B antigo não reconhece o hotfix e fingerprint precisa de reconciliação auditada; não afrouxar o gate para avançar.
3. RPCs v2 ainda propostas. Segurança, locks, auditoria e idempotência persistente não são demonstradas por mocks.
4. UI nova ligada na branch torna a Folha indisponível sem backend; proibir publicação prematura.
5. Férias e HE legados mantêm limitações de atomicidade/origem; não ligar motor automático sobre lançamentos manuais.
6. A função de intervalos cobre períodos no mesmo dia, não turnos que cruzem a meia-noite. Esses casos exigem contrato de datas explícitas antes de suporte.
7. Falta modelo oficial de vencimentos e reconciliação documental/Storage para PDF derivado.
8. Alertas de tarefas e conclusão reportada precisam de backend; não foram fechados apenas pelo filtro visual.

## R. Próximos passos mínimos

1. Recuperar a leitura do catálogo na mesma sessão Supabase e recolher apenas metadados/gates pós-hotfix; parar em autenticação ou divergência. Não retomar pgpass/exportação local.
2. Consolidar e auditar a Fase B sobre essa baseline, preservando todas as proteções já aplicadas. Nenhuma execução real sem autorização.
3. Preparar backend do Pacote 2 para os quatro contratos, modelo externo, horários, revisions, request e reconciliação; testar tenant/concorrência/rollback em PostgreSQL completo antes de ligar dados reais.
4. Recolher somente as três decisões ADM da secção E–F e o ficheiro oficial. Em paralelo, manter estados neutros; não calcular salário/pagamento.
5. Completar HE/férias/mapa mensal persistentes e alertas sobre as origens controladas, sem duplicar lançamentos. Publicação e testes reais terão gates separados.

**Estado de entrega:** alterações locais para revisão na branch indicada; sem commit/push nesta ronda, sem main/produção/Fase B alterados. GO apenas para revisão local dos contratos/frontend; NO-GO para rollout real desta branch ou dos scripts B antigos.
