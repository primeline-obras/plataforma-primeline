# Auditoria estrutural e funcional — RH / Pessoal

Data: 30/09/2026. Estado: **auditoria de código e testes concluída; certificação da BD e da sessão real pendente**.

## 1. Resumo executivo

A aplicação tem cadastro RH com gravação transacional, importação parcial controlada, NISS protegido, contratos consultáveis, alocação, ponto, férias, ausências, documentos e atribuição controlada de viaturas. Ainda não oferece um ciclo de vida completo e coerente para o Administrativo.

Os bloqueios mais importantes encontrados são:

1. **Risco de perda de alocação:** a troca de dia inteiro apaga a colocação anterior numa chamada e cria a nova noutra. Uma falha na segunda deixa a primeira apagada.
2. **Conteúdo de RH interpretado como HTML:** o nome da pessoa e o nome da obra são interpolados sem escape na lista de horas extra. Uma prova local com marcação inofensiva confirmou a interpretação como HTML. A exploração de JavaScript e os headers da produção não foram testados.
3. **Inativos incorretos:** o carregamento do painel de inativos não usa a opção que impede o cliente de substituir `data_saida=not.is.null` por `data_saida=is.null`.
4. **Escritório bloqueado:** o helper de autorização recusa `obra_id = null` antes de reconhecer o Administrativo. Afeta também garantia e trabalhos pontuais.
5. **Quadro e ponto discordam sobre a alocação:** o quadro usa eventos do próprio dia; o ponto transporta o último evento anterior por período. Remover uma colocação pode fazer reaparecer uma anterior no ponto.
6. **Sem continuidade de Medicina/EPI:** a criação admite uma consulta e uma entrega inicial, mas faltam ações posteriores. A solução de backend de Medicina **já existe em branch separada**, ainda sem integração da interface nem aplicação autorizada nesta auditoria.
7. **Contratos:** corrigir o contrato ativo existe; renovar/encerrar com histórico não tem fluxo. O filtro “sem contrato” não inclui contratos de tipo desconhecido.
8. **Horas extra:** cria e lista `por_pagar`, mas não oferece correção, anulação ou pagamento. Informar quem autorizou não constitui aprovação autenticada dessa pessoa.
9. **Ponto:** falta cobertura funcional dedicada; há riscos em correções concorrentes, validações já decididas e consulta histórica após saída.
10. **Permissões:** vários scripts concedem acesso por papel, sem condição explícita de empresa. A gravidade potencial é alta; a instalação efetiva dessas definições precisa de leitura do catálogo real.

**Recomendação:** não declarar o RH pronto para aceitação integral. Fazer primeiro os pacotes de integridade/segurança, inativos/alocação e continuidade dos fluxos essenciais. Não é necessário reimplementar o cadastro nem a solução já preparada de Medicina.

### Base e limites da evidência

- Produção analisada: commit `3f67ae912ff00c99fd2559203a344f8593acd89f`, indicado pelo utilizador. Nenhuma alteração a `main`.
- Medicina analisada separadamente: `ba7f6d8d20dbe614dd9ceb881d16ef7d4c0a86b7`, branch `feat/medicina-trabalho-controlada-20260930`. Nenhuma integração dessa branch.
- Branch deste relatório: `codex/auditoria-rh-pessoal-20260930`, criada diretamente a partir do commit de produção indicado.
- O Chrome DevTools MCP listou o dashboard do projeto **Primeline-Obras**, `znttyadndpkxuekhjamd`. O snapshot mostra o SQL Editor autenticado. Não havia aba da aplicação com a sessão de Belmira.
- Tentativas de interação com o editor falharam com timeout e identificadores de elementos indisponíveis, incluindo após selecionar explicitamente a página. **Nenhum resultado novo de SELECT foi obtido.** Não se conclui que a sessão expirou. A investigação não ficou à espera de reparação do MCP.
- Não foi executado SQL de escrita, backup, migration ou rotina geradora de alertas. Não foram alterados dados reais. Os testes SQL referidos abaixo usam bases sintéticas locais.
- Não foram obtidos nesta auditoria: catálogo real completo, grants efetivos, políticas efetivamente instaladas, contagens de anomalias, cron ativo, inventário de objetos Storage ou renderização real em tablet/telemóvel.
- Não se inferiu instalação de SQL a partir da presença de ficheiros. Há scripts que substituem políticas/funções anteriores; ordem de ficheiros ou nome “final” não prova o estado real.

Legenda usada no relatório: **C** = confirmado no código do commit; **T** = reproduzido em teste local; **R** = declaração anterior do utilizador; **V** = exige verificação na BD/interface real. P0/P1 atribuídos a código não significam que já houve exploração ou corrupção em produção.

## 2. Arquitetura atual e decisões anteriores

```text
Equipa / Colaboradores -> rh-cadastro.js -> fn_rh_consultar / guardar / importar
    -> colaboradores + colaboradores_rh_privado + colaboradores_contratos
    -> rh_cadastro_auditoria
    -> criação inicial de alocação, EPI e Medicina

Quadro -> app.js -> DML REST quadro_pessoal_alocacao -> movimentos / log
Ponto -> attendance.js -> RPCs de ponto -> ponto_pessoal_obra
Férias / Ausências -> app.js -> REST ausencias + ausencias_anexos
Horas extra -> app.js -> REST horas_extraordinarias
Documentos RH -> app.js -> Storage documentos + tabela documentos
Viaturas -> vehicle-assignment.js -> RPC controlada -> histórico/revisão
Alertas -> rotinas SQL + resolução explícita -> dashboard/sino
```

Há três registos de atividade distintos: alocação planeada (`quadro_pessoal_alocacao`), ponto efetivo (`ponto_pessoal_obra`) e lançamentos de mão de obra/custos (`lancamentos_mao_obra`). Não há evidência de sincronização automática completa dos três; não apresentar horas extra ou ponto como pagamento/custo financeiro confirmado.

### Decisões recuperadas

| Evidência | Decisão existente | Consequência para esta auditoria |
|---|---|---|
| `docs/rh-cadastro-auditoria.md`; commits `00d4905`, `90890bc` | Cadastro único; contrato ativo corrigível; Excel atualiza existentes por UUID; vazio preserva; tipo contratual desconhecido pode permanecer NULL | Reutilizar. Não “corrigir” os 47 tipos desconhecidos por inferência |
| Mesmo documento | NISS privado; conformidade separada de número SS; não recolher dados clínicos | Manter separação e minimização |
| Mesmo documento, limites | Renovação/encerramento e reconciliação de alertas contratuais pendentes | Lacunas já reconhecidas, continuam sem fluxo completo |
| `96ad5f8` / `quadro_pessoal_operacional_relatorio.sql` | Diretor e Encarregado voltaram ao quadro; alteração restrita às suas obras | Dois testes antigos contradizem esta decisão |
| `9cddf4c` / `ponto_pessoal_obra.sql` | Ponto por alocação, justificação com validação administrativa | Não substituir o ponto por simples edição da alocação |
| `7d60967`, `a05e025`; `docs/viaturas-atribuicao-controlada.md` | Atribuição de viatura com revisão, request_id, histórico e bloqueio de saída com viatura | Já existe solução; falta principalmente ligação à ficha RH |
| Branch Medicina `ba7f6d8` | Registar/corrigir/anular, histórico, autor, request_id, revisão, empresa, reconciliação, Encarregado leitura | Backend preparado, não confundir com funcionalidade publicada |

O documento RH antigo ainda contém linguagem de “publicação pendente”, embora a entrega conste do commit de produção fornecido. Usar o código e a verificação de instalação, não essa frase histórica, para decidir o estado atual.

## 3. Inventário de tabelas, RPCs, triggers e policies

**Este é um inventário do repositório, não uma exportação certificada do catálogo real.** Tipos/colunas não definidos nos scripts base não foram inventados. O catálogo atual completo continua V.

### Tabelas e fontes

| Objeto | Dados/finalidade identificados | Proteção/limite no repositório |
|---|---|---|
| `colaboradores` | UUID, empresa, nome, função, nível, valor/hora, identificação/contactos, datas, código RH, observações, três conformidades, permite_multiplas_obras | RLS por papel em scripts; log genérico; campos e duplicados validados na RPC RH, mas DML direto continua previsto |
| `colaboradores_rh_privado` | PK/FK colaborador; NISS textual com check de 11 algarismos | RLS; sem acesso direto anon/authenticated; RPC por empresa |
| `colaboradores_contratos` | Pessoa, tipo, início/fim, estado, criação | Tipos `a_prazo`/`tempo_indeterminado`, estados ativo/renovado/encerrado; tipo NULL autorizado; não se encontrou índice único parcial de ativo por pessoa nos scripts revistos |
| `rh_cadastro_auditoria` | Pessoa, empresa, autor, origem, antes/depois, data | RLS; acesso direto de cliente revogado; não tem consumidor de leitura na UI |
| `medicina_trabalho` | Pessoa, última consulta, resultado, próxima consulta, criação | Produção lê seis colunas; scripts legados permitem RH DML; estrutura controlada só na branch separada |
| `epis` | Pessoa, tipo, entrega, validade | Entrega inicial; leitura em Segurança; RLS RH; não há workflow dedicado posterior |
| `documentos` | Empresa, entidade polimórfica, tipo, nome, caminho, emissão/validade | Tipos textuais não vazios; índices entidade/validade; sem vínculo específico à consulta/contrato; audit trigger previsto noutro script |
| `storage.objects`, bucket `documentos` | Bytes em `rh/colaborador/...`, `rh/ausencia/...`, `rh/viatura/...` | Cliente usa UUID, POST sem upsert, download autenticado, DELETE separado; policies atuais V |
| `ausencias` | Pessoa, dia, tipo, estado, comentário | Check de combinações tipo/estado e comentário obrigatório se justificada; duplicado pessoa/dia tratado no frontend; índice real V |
| `ausencias_anexos` | Ausência, caminho, nome, criação | RLS RH e auditoria previstos; upload e associação não são uma transação |
| `horas_extraordinarias` | Pessoa, obra, dia, horas, motivo, autorizado_por, estado_pagamento | Trigger valida obra, horas positivas e responsável; DML RH previsto; não é workflow de autorização/pagamento |
| `quadro_pessoal_alocacao` | Pessoa/obra, tipo/local, dia/semana, período, criado_por | Checks e trigger de conflitos; índices foram alterados entre scripts; CRUD direto |
| `quadro_pessoal_movimentos` | Adicionada/alterada/retirada, origem/destino, pessoa/dia/período, autor | Trigger após DML, SELECT por política; não substitui atomicidade de troca |
| `ponto_pessoal_obra` | Pessoa/obra/empresa/dia, períodos, quatro horários, horas, estado/justificação, observação, autores/datas | UNIQUE pessoa/obra/dia; checks estados e horas 0–24; RPC exige até 16 h; RLS sem DML direto de cliente |
| `lancamentos_mao_obra` | Lançamentos económicos de trabalho | Guarda contra ausência; fonte distinta do ponto |
| `feriados_empresa` | Data, nome, âmbito, município, folga | Usado como calendário visual; não prova desconto/contabilização de férias |
| `viaturas`, `viaturas_atribuicoes_historico` | Responsável atual, revisão e eventos de mudança | RPC, imutabilidade do histórico, idempotência, isolamento e lock partilhado com saída |
| `alertas` | Tipo, entidade, data/antecedência/ocorrência, estado, destinatário, resolução | Índice de ocorrência e RPC resolver; rotinas de geração distintas; cron/DDL atuais V |
| `utilizadores`, `obra_responsaveis`, `administradores_plataforma` | Identidade, papel, empresa e responsabilidade de obra | Base de autorização; cadastro de pessoa e conta de login são entidades distintas |
| `log_auditoria` | Tabela/registo/campo, antes/depois, autor/data | Trigger genérico; consulta UI limitada a 200 eventos, só gestão autorizada |
| `parametros_operacionais` | Antecedências configuráveis | UI médica usa 30 dias fixos, não o parâmetro |

### RPCs e funções principais

| Assinatura/identificação | Consumidor e finalidade | Constatação |
|---|---|---|
| `fn_rh_consultar(uuid default null)` | `rh-cadastro.js:76,132` | JSON com cadastro, NISS, contratos e hash de versão; inclui inativos se consultados pela RPC |
| `fn_rh_guardar(jsonb,boolean default false)` | `rh-cadastro.js:112` | Cadastro/contrato atómicos, conflito de versão, auditoria |
| `fn_rh_importar(jsonb,boolean default false)` | `rh-cadastro.js:158,168` | Preview e confirmação; importação Gestão; lote atómico, vazios preservados |
| `fn_rh_guardar_interno(jsonb,boolean,boolean)` | Wrapper RH | Não executável diretamente por authenticated; serializa por empresa |
| `fn_criar_colaborador_com_alocacao(...)` | Cadastro inicial | Há sobrecargas históricas de 6, 12 e versão com conformidade; não presumir quais permanecem instaladas |
| `fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date)` e variante com mais seis campos | Reativação e cadastro | Legado sem filtro explícito de empresa no UPDATE; solução Medicina corrige as duas sobrecargas |
| `fn_listar_ponto_obra(date,uuid)` | `attendance.js:101` | Lista por último evento anterior e ativo atual, não pelo mesmo critério diário do quadro |
| `fn_guardar_ponto_obra(uuid,uuid,date,text,time,time,time,time,text)` | `attendance.js:225` | Upsert, valida horários/ausência; sem revisão esperada/request_id |
| `fn_validar_justificacao_ponto(uuid,text)` | `attendance.js:208` | Atualiza estado sem exigir que decisão anterior ainda seja pendente |
| `fn_relatorio_mensal_ponto(date)` | `attendance.js:130` | Inclui histórico de inativos; agrupa pela função/nome atuais da pessoa |
| `fn_pode_consultar_quadro()`, `fn_pode_gerir_quadro(uuid)` | RLS quadro | RH global; Diretor/Encarregado por obra para escrita |
| `fn_quadro_ferias_encarregado_global(...)` | Script histórico | Frontend atual não chama; não eliminar sem catálogo de dependências |
| `fn_apagar_documento_entidade(uuid)` | `app.js:4171` | Apaga metadados, não bytes; verificação de papel, sem empresa explícita no corpo revisto |
| `fn_resolver_alerta(uuid)` | Sino/dashboard | Decisão com autor/data, lock e preservação; não resolve o problema na origem |
| `fn_verificar_primeiras_consultas_medicina()`, `fn_verificar_alertas_vencimento()`, `fn_verificar_alertas_fim_contrato()`, `fn_executar_rotinas_diarias()` | Rotinas | Geram/alteram dados; **não chamadas nesta auditoria** |
| `fn_alterar_responsavel_viatura(...)` | `vehicle-assignment.js` | Contrato versionado, revisão esperada e request_id; interface já existe |

### Triggers, constraints e RLS que precisam de confirmação de instalação

- `trg_normalizar_estado_ausencia`; checks `ausencias_fluxo_check`, `ausencias_justificacao_comentario_check`.
- `trg_validar_autorizacao_horas_extra`; FK `autorizado_por -> utilizadores`.
- `trg_validar_conflito_quadro_pessoal`; `trg_quadro_pessoal_movimentos`; guardas de ausência sobre quadro, mão de obra e horas extra.
- `trg_auditoria_*` de colaboradores, contratos, ausências, horas extra, alocação, documentos e ponto nos respetivos scripts. O script genérico de auditoria **não enumera EPI e Medicina**; não concluir ausência real sem catálogo.
- `trg_alerta_validade_documento` é criado em `documentos_rh_ativos.sql` e **removido** em `alertas_vencimentos_resolucao_corrigido.sql`. Não recomendar reinstalar o primeiro sem respeitar a decisão de geração diária.
- Policies `pl_colaboradores_rh`, `pl_colaboradores_seguranca_select`, `pl_epis_rh`, `pl_medicina_rh`, `pl_contratos_rh`; posteriores `ausencias_ferias_select`, `ausencias_rh_*`, `ausencias_anexos_rh`, `horas_extra_rh`, `quadro_pessoal_operacional_*`, `quadro_pessoal_movimentos_select`.
- NISS/auditoria privada sem grants diretos; ponto sem grants diretos; outras tabelas com grants DML e RLS. RLS baseada só em `fn_e_administrativo()` não constitui isolamento por empresa.
- Contratos múltiplos: RPC bloqueia se encontra vários ativos e serializa o seu próprio fluxo; isso não é equivalente a constraint contra outras vias de escrita.
- Política e trigger de viaturas controladas estão descritos em `docs/viaturas-atribuicao-controlada.md`; não confundir esse workflow com o antigo formulário de frota ainda existente em Equipa.

## 4. Mapa funcional

| Área | Fluxo utilizável no código | Ponto em falta/risco | Situação |
|---|---|---|---|
| Colaborador | Novo, editar, importação existente, saída por data | Inativos carregados incorretamente; sem ficha histórica e sem controlo de múltiplas obras | C/T |
| Contrato | Criar/corrigir ativo; consultar lista histórica na ficha | Sem renovar/encerrar; múltiplos ativos bloqueiam abertura; tipo por confirmar fora do KPI | C |
| Medicina | Consulta inicial na criação; lista global | Sem nova/corrigir/anular/histórico individual/ligação a ficha de aptidão | C; backend preparado |
| EPI | Entrega inicial; lista em Segurança | Sem nova entrega/correção/validade/autoria na UI RH | C |
| Documentos | Upload/download/apagar | Sem corrigir metadados, versionamento ou relação com evento; operações Storage/BD separadas | C |
| Alocação | Ímanes, períodos, movimentos | Escritório bloqueado; troca não atómica; critérios incompatíveis com ponto | C/T |
| Ponto | Guardar/atualizar, validar/rejeitar justificação, Excel mensal | Sem revisão, fecho/retificação, histórico de alterações na ficha; inativos e obras históricas | C |
| Férias | Mapa mensal; edição semanal segunda–sexta | Sem aprovação/saldo; POST+DELETE separados; sem cancelamento lógico | C |
| Ausência | Criar, editar, justificar, anexar | Sem cancelar; anexos podem ficar com nova pessoa/data; edição sem revisão | C |
| Horas extra | Criar; listar pendentes | Sem corrigir/anular/pagar/ver pagos; autorização declarativa | C |
| Viatura | Módulo Viaturas com atribuição controlada | Falta resumo na ficha RH; formulário antigo em Equipa compete com fluxo novo | C |
| Alertas | Sino, agrupamento, resolver | Falta reconciliação consistente com origem; limiares e critérios divergem | C/V |

## 5. Matriz campo a campo e ação a ação

A matriz completa está no **Anexo A**, para manter o diagnóstico legível. Todas as colunas pedidas estão presentes. “Existe na BD = script/ref.” significa que há definição ou consumo no repositório; **a existência e o tipo atuais na BD real não foram recertificados**. Uma ação marcada disponível significa caminho implementado, não aceitação real por Belmira.

## 6. Ciclo de vida e becos sem saída

| Etapa / ação necessária | Local / backend | Confirmação, histórico e efeito | Falha/dependência |
|---|---|---|---|
| Novo colaborador | Equipa → Novo; `fn_rh_guardar` | Guardar único; cria pessoa/alocação e opcionais de forma transacional; auditoria RH | Repetição após perda de resposta não tem request_id próprio; não experimentar em produção |
| Completar cadastro | Editar / Excel Gestão | Versão e preview; avisos contratuais | DML direto pode contornar regras se grants/policies legados permanecem |
| Associar contrato | Secção Contrato ativo | Correção com antes/depois; tipo/início obrigatórios na edição manual | Não renovar alterando apenas datas do contrato antigo |
| Primeira consulta | Só criação da pessoa | Linha com próxima NULL válida | Pessoa já existente sem consulta não tem ação de inserção |
| Entregar EPI | Só criação da pessoa | Tipo “Entrega inicial”, validade NULL | Sem gestão de novas entregas nem detalhe de artigos |
| Anexar documentos | Botão Documentos fora do modal | Bytes privados + metadados; apagar tem confirmação | Não liga a contrato/consulta; falha parcial possível |
| Alocar / mudar obra | Quadro; DML direto | Movimentos e log previstos | DELETE+POST pode perder anterior; Escritório recusado |
| Férias | Mapa → edição semanal | Dias confirmados; desmarcar apaga | Sem aprovação/saldo; gravação parcialmente aplicável |
| Ausência | Equipa → Ausências | Normaliza estado, permite comentário/anexo | Sem cancelamento; origem e anexo podem perder coerência na correção |
| Ponto | Equipa → Ponto | Autores e log; validação RH | Conflitos sem revisão; equipa diária não coincide com quadro |
| Horas extra | Equipa → Horas extra | Registo com autorizado_por | Sem decisão pelo autorizador nem ação para pagar/corrigir |
| Viatura | Viaturas → responsável | RPC controlada, motivo/autor/request/revisão | Saída bloqueada com viatura: precisa ligação clara para desatribuir |
| Renovar contrato | Não há botão dedicado | Seria novo vínculo/estado anterior preservado | Beco sem saída P1 |
| Nova consulta | Backend preparado, UI ausente | Modelo controlado já especificado | Não corrigir com PATCH direto |
| Novo EPI | Sem botão | Histórico não gerível pelo RH | Beco sem saída P1 |
| Saída | Editar → data de saída | Preserva registos; guarda viatura impede saída indevida | Alertas não médicos e inativação futura precisam de decisão |
| Consulta após saída | Painel Inativos / relatório mensal de ponto | Relatório SQL não filtra ativos | Lista de inativos errada; sem Editar/Documentos/histórico; não reativar para consultar |

## 7. Problemas de frontend confirmados

| ID | Problema e prova | Impacto / recomendação |
|---|---|---|
| RH-01 | `app.js:2584` pede inativos sem `includeInactiveCollaborators:true`; `supabase-browser.js:363–376` força ativos. O teste do helper confirma esse comportamento | P1: painel pode apresentar ativos como inativos e acionar reativação na pessoa errada. Corrigir consumidor e testar integração |
| RH-02 | `app.js:861` retorna false para obra vazia antes de `canManageTeam`; `saveWorkforceAllocation:2394` usa o helper também para Escritório | P1: Administrativo não consegue mover para linhas sem obra. Prova local devolveu false |
| RH-03 | `app.js:2434–2474`: DELETE confirmado antes de POST de nova alocação | P0: falha ou política no POST perde colocação; operação deve ser atómica no servidor |
| RH-04 | `app.js:1719` filtra `data === date`; `ponto_pessoal_obra.sql:96,173` usa `data <= p_data` e último evento | P1: pessoa ausente no quadro pode aparecer no ponto; múltiplas obras são reduzidas a uma por período no ponto |
| RH-05 | `app.js:2272` Medicina só gera cartões; `rh-cadastro.js:91` só oferece consulta/EPI quando cria | P1: continuidade impossível; integrar backend preparado e criar workflow EPI próprio |
| RH-06 | `app.js:2578,2263`: só `por_pagar`; cartões não têm ações | P1: horas extra sem saída operacional e sem histórico de pagos |
| RH-07 | `app.js:2228`: inativos só têm Reativar; `activeMedicine`, contratos/horas dependem de mapa de ativos | P1: não há ficha de arquivo; corrigir carregamento não basta |
| RH-08 | `app.js:2267` interpola `person.nome`, `work.numero`, `work.nome` sem escape em innerHTML | P0: injeção de HTML persistido; DOM sintético confirmou elemento inserido. Usar texto/escape e teste de conteúdo hostil |
| RH-09 | `app.js:2519`: férias POST e DELETE em pedidos separados; `createAbsence`/`justifyAbsence` gravam antes do upload | P1: sucesso parcial; repetição pode duplicar tentativa/anexo ou falhar por ausência já existente |
| RH-10 | `app.js:4305,4168`: Storage antes de metadados no upload; metadados antes de Storage no apagar | P1: objetos órfãos e mensagem de falha com operação parcialmente concluída; reconciliar/compensar |
| RH-11 | KPI “sem contrato” verifica só existência (`app.js:2187`); tipo NULL apresentado mas não classificado como pendência | P2: oculta necessidade de RH confirmar os tipos |
| RH-12 | Medicina atenção `days <= 30` fixo (`app.js:2081`); backend usa parâmetro | P2: indicadores podem discordar do sino |
| RH-13 | Carregamentos de contratos/horas/responsáveis/utilizadores sem paginação; erros de contratos/horas não estão entre falhas essenciais/documentais (`app.js:2595`) | P1/P2: “sem registos” pode significar erro; listas podem truncar no limite REST do servidor, que não foi medido |
| RH-14 | `app.js:2073`, `activeWorkOptions:1986` excluem concluída/cancelada, mas o schema usado noutros scripts contém `fechada` | P2: obra fechada pode aparecer em seletores; confirmar schema atual e centralizar estados |
| RH-15 | Formulário de frota de Equipa ainda inclui atribuição (`app.js:1939`) e caminho antigo; módulo Viaturas usa RPC protegida | P1: atualizar frontend comum; não remover a proteção da BD para fazer o formulário antigo funcionar |

## 8. Problemas de backend e integridade

| ID | Evidência de código | Risco / correção proposta |
|---|---|---|
| RH-16 | `fn_rh_guardar_interno` valida campos/duplicados, mas scripts `pl_colaboradores_rh`/`pl_contratos_rh` permitem DML por papel | P0 condicionado à instalação: API pode contornar validação, versão e auditoria específica. Confirmar grants; preferir escritas controladas |
| RH-17 | `colaboradores_campos_completos.sql:128` e sobrecarga antiga atualizam por UUID sem empresa | P0 potencial entre empresas. **Já corrigido na branch Medicina**, ainda não aplicado nesta tarefa |
| RH-18 | `ponto_pessoal_obra.sql:244` upsert sem revisão; redefine justificação para pendente; validar (`:277`) não exige estado pendente | P1: segunda gravação pode perder correção/decisão. Revisão e transição explícita |
| RH-19 | Ponto testa ausência/intervalos com SELECT, sem lock coordenado com alocação/ausência; trigger de alocação também consulta conflitos sem serialização | P0 potencial sob concorrência; não demonstrado em duas sessões nesta auditoria. Testes concorrentes e constraint/lock partilhado antes de certificar |
| RH-20 | Ponto lista apenas ativos atuais (`:96`), mas escrita verifica empresa sem recusar saída; obras listadas só preparação/em curso/receção provisória | P1: leitura histórica e capacidade de correção divergem; definir data efetiva e retificação de período encerrado |
| RH-21 | Contratos: número de ativos verificado só no fluxo RH; dois ativos fazem `flattened()` falhar | P1: catálogo de constraints e resolução controlada de duplicados; unicidade parcial depois de tratar anomalias |
| RH-22 | Ausência tem identidade pessoa/dia editável; anexos seguem UUID; blockers são sobre registo de trabalho, não garantem coerência quando ausência é inserida depois | P1: documento pode passar a justificar outra pessoa/data; reconciliação bidirecional e histórico de correção |
| RH-23 | `documentos.entidade_id` polimórfico e tipos livres; `fn_apagar_documento_entidade` só testa papel/existência | P1/P0 de isolamento: validar entidade/empresa e relações; não presumir FK polimórfica existente |
| RH-24 | Horas extra: trigger aceita autorizado_por NULL e valida pertença a responsável, não uma ação autenticada desse responsável | P1: distinguir “indicado como autorizador” de “aprovou”; edição/pagamento com auditoria |
| RH-25 | Criação RH sem request_id; identificadores opcionais podem não impedir repetição de pessoa após resposta perdida | P1: testar repetição e estratégia de idempotência sem usar nome como identidade |
| RH-26 | `data_saida is null` define ativo, mesmo se data de saída é futura; conformidades são três booleans independentes de documentos/validade | P2/decisão RH: definir saída programada e significado dos indicadores; não inventar conformidade automática |

As sobrecargas antigas de criação também exigem atenção: `colaboradores_campos_completos.sql:54` verifica a obra por UUID/estado, sem comparar a sua empresa com a do utilizador. O wrapper RH novo faz essa comparação, mas não elimina automaticamente as RPCs antigas. Confirmar EXECUTE e dependências antes de as restringir. A branch Medicina não deve ser tomada como correção de todas as vias legadas de criação.

Outros limites: NIF/NISS têm validação de formato, não foi encontrado cálculo de dígito de controlo; NISS não tem unicidade declarada no script revisto. Uma política de duplicação deve ser decidida pelo RH antes de impor constraints. Histórico de função/valor-hora não é uma tabela temporal; o log pode guardar alterações, mas o relatório de ponto usa nome/função atuais.

## 9. Permissões

### Matriz da interface por papel (C; eficácia real de RLS = V)

| Papel | Cadastro/contratos | Medicina | EPI | Quadro | Ponto | Férias | Ausências/HE | Docs RH | Importar |
|---|---|---|---|---|---|---|---|---|---|
| Gestão Plataforma | Criar/editar | Ler + inicial | Inicial; ler Segurança | Gerir | Guardar/validar/exportar | Gerir | Gerir disponível | Gerir | Sim |
| Gerência | Criar/editar | Ler + inicial | Igual | Gerir | Igual | Gerir | Igual | Gerir | Não |
| Administrativo/Belmira | Criar/editar | Ler + inicial | Igual | Gerir, com falha Escritório | Igual | Gerir | Igual | Gerir | Não |
| Diretor | Não | Sem aba | Leitura depende Segurança/RLS | Ver/alterar próprias obras | Aba não oferecida | Ler | Não | Sem arquivo RH | Não |
| Adjunto/Preparador | Não | Não | Verificar Segurança/RLS | Sem vista quadro | Não | Ler | Não | Sem arquivo RH | Não |
| Encarregado | Não | Ler pessoas permitidas | Verificação real pendente | Ver/alterar próprias obras | Guardar próprias obras; não validar | Ler | Não | Sem arquivo RH | Não |
| Financeiro | Sem vista Equipa | Não | Não | Não | Não | Não na UI RH | Não | Não | Não |

“Gerir disponível” não inclui ações ausentes: horas extra não pode ser paga pela UI e contrato não tem renovação. Não é recomendação de dar esses poderes a todos os papéis.

### Riscos de acesso direto

- RLS filtra linhas, não esconde automaticamente NIF, morada ou valor/hora. `pl_colaboradores_seguranca_select` usa a existência de responsabilidade de obra, sem projeção de colunas. Confirmar grants de coluna atuais; separar leitura operacional mínima.
- Policies de férias em scripts permitem `tipo='ferias'` a authenticated, sem empresa explícita. Acesso global pode ser intencional dentro da empresa, não entre empresas.
- `fn_e_administrativo()` identifica papel; não compara a empresa da linha com a empresa da sessão. Isto afeta diversas policies, documentos e RPCs antigas.
- `fn_rh_consultar/guardar/importar` já verificam empresa. A proteção de NISS é uma boa base a preservar.
- Funções de ciclo de vida antigas e eliminação de documento exigem revisão de todas as sobrecargas e EXECUTE; esconder botão não remove uma RPC exposta.
- A lista de ponto devolve `to_jsonb(a)` da ausência, incluindo comentário, ao Encarregado da obra. Confirmar com RH o mínimo operacional que deve ver; não expor justificações pessoais por conveniência.
- Não foi simulada a sessão real de Belmira, não foram trocados utilizadores e não foram efetuadas tentativas de escrita via API.

## 10. Alertas RH

| Origem | Lógica no repositório | Lacuna |
|---|---|---|
| Primeira consulta | Admissão + 30 dias; ausência de qualquer linha médica no legado | Linha futura/inválida pode suprimir aviso; branch Medicina já trata validade/consulta corrente |
| Medicina a vencer | Cada linha com próxima data dentro da antecedência | Histórico pode continuar a gerar avisos; UI conta linhas, não pessoas; branch trata reconciliação médica |
| EPI | Cada validade preenchida, ativo atual | Não há workflow para renovar/inativar entrega; histórico pode continuar a alertar |
| Contrato | A prazo ativo; limiares configurados com igualdade exata ao dia (`parametros_operacionais.sql:195`) | Inserir após limiar pode não gerar; alterar fim deixa ocorrência anterior; falta reconciliação |
| Documento RH | Geração diária por validade; versão antiga tinha trigger removido | Corpo revisto não filtra saída do colaborador; alteração/remoção da fonte precisa reconciliar pendentes |
| Resolver | `fn_resolver_alerta` guarda autor/data; repetição de resolvido é no-op | Resolver não altera fonte; não deve ser substituto de registar consulta/renovar contrato |
| Destinatários | Administrativo e regras de obra/financeiro; viatura tem fluxo próprio | Confirmar empresa, utilizadores ativos, cron e ocorrência efetiva no catálogo real |

Não foi executada função geradora para “ver se funciona”. A branch Medicina preserva resolvidos e trata reativação com nova ocorrência; esse trabalho não resolve EPI, contrato e documentos. Não reintroduzir o trigger antigo que apagava/recriava avisos de documentos.

## 11. Histórico e auditoria

- Cadastro tem antes/depois, origem e autor em `rh_cadastro_auditoria`, mas não existe leitura desse histórico na ficha nem consumidor frontend dessa tabela.
- O log genérico guarda alterações por campo e INSERT/DELETE. Isso permite investigação técnica, mas não equivale a renovação de contrato, nova entrega ou consulta atual.
- `settings.js:261` carrega só os últimos 200 eventos antes de filtrar; eventos mais antigos ficam invisíveis mesmo quando se escolhe uma data antiga. RH não dispõe de histórico individual acessível por esse mecanismo.
- A auditoria genérica não remove NIF/contactos/observações; remove credenciais. Confirmar minimização e acesso ao log, sem alargar NISS por acidente.
- Ponto tem autor inicial/último e log previsto; não tem motivo de retificação nem revisão de concorrência.
- Quadro tem movimentos próprios. DELETE+POST regista duas operações, não uma transferência atómica.
- Medicina controlada e viatura são referências reutilizáveis para eventos, motivo, request_id e revisão; não generalizar copiando permissões sem preflight.
- Falta verificar triggers ativos em todas as tabelas e autoria de registos antigos. Não atribuir autor fictício a dados legados.

## 12. Mobile/tablet

Verificação **estática**, sem alegar execução visual real:

- Cadastro: `.rh-field-grid` passa de duas para uma coluna abaixo de 600 px (`styles.css:1042–1053`); há teste DOM e browser sintético existente.
- Ponto: três blocos até 1450 px e uma coluna abaixo de 900 px (`:1124–1125`). Entre 900 e 1100 px os mínimos de 180+180+420 px, gaps, sidebar e margens podem exceder a área disponível. Precisa de medição real em 1024/1280 px.
- Ímanes do quadro: 27×27 px (`:1260`), pequenos para uso repetido com toque. Há alternativa selecionar pessoa e depois célula; ainda exige precisão.
- Mapa de férias: mínimo `230 + dias×31 px`, isto é, 1191 px para 31 dias; scroll horizontal intencional, não presumir bug. Necessita nome fixo, indicação de scroll e foco na data atual.
- Horas extra mantém duas colunas abaixo de 1100 px; nomes longos/seletores exigem teste em 390 px.
- Vários formulários e ações vivem em cartões longos ou `<details>`; erro deve aparecer junto da ação e foco deve ir para o campo inválido. Nem todos os caminhos o fazem.
- Calendários usam `toISOString()` para “hoje”; perto da meia-noite de Lisboa podem usar o dia UTC anterior. Testar transição de dia e horário de verão com relógio controlado.
- Nenhum fluxo recebeu classificação “mobile aprovado” só por ter media query. Teclado virtual, orientação, zoom, alvos de toque e leitor de ecrã permanecem por validar.

## 13. Dados reais e anomalias

**Não existem novas contagens verificadas nesta auditoria.** Não foi obtida execução de SELECT no dashboard. O relatório não converte hipóteses em anomalias reais.

| Dado | Estado da evidência | Ação de RH/técnica necessária |
|---|---|---|
| 35 registos de Medicina, novo registo de 30/09/2026 17:38:45+00, não duplicado | R: confirmação manual do utilizador na tarefa anterior | Nova leitura no precheck quando autorizado; próxima consulta NULL é válida |
| 47 contratos sem tipo | R: contexto fornecido; não recontado | RH confirma tipo pelos documentos. Importação parcial foi desenhada para não inventar tipo |
| Dashboard mostrava resultado de uma consulta anterior com uma pessoa e total 1 | Observação de UI, sem reexecutar | Não usar como fotografia completa ou como prova de catálogo |
| NIF/NISS/código RH duplicados, vazios críticos | V | Agrupar identificadores não vazios por empresa; nomes iguais não provam duplicado |
| Contratos múltiplos ativos, fim anterior ao início, tipo desconhecido | V | Contar por pessoa; classificar pendência documental versus violação |
| Pessoas sem Medicina/EPI/documento/alocação | V | Separar ativos, inativos, recém-admitidos e histórico; ausência de linha não prova ausência de execução física |
| Inativos ainda atribuídos a viaturas/obras; datas futuras/impossíveis | V | Comparar datas efetivas, não apagar histórico |
| Alertas órfãos, duplicados, pendentes com origem alterada, sem autor | V | Validar vínculo por tipo, estado, ocorrência e origem; não regenerar nem resolver nesta auditoria |
| Objetos Storage sem metadados e caminhos sem objeto | V | Inventário autorizado só de metadados; não abrir documentos pessoais desnecessários |

### Separação obrigatória

**Falhas estruturais:** fluxos ausentes, helper de inativos, transações partidas, falta de revisão, rendering inseguro e divergência de alocação são problemas de aplicação comprovados no código.

**Dados para RH confirmar:** os 47 tipos, datas de execução/consulta/entrega, aptidão, autorização/pagamento, razões de ausência e duplicados aparentes. Não corrigir esses dados automaticamente nem preencher com data de log ou data prevista.

### Leitura real ainda necessária para fechar a auditoria

1. Catálogo `pg_class/pg_attribute/pg_constraint/pg_indexes/pg_trigger/pg_policies`, ACL por tabela/coluna/função e `pg_get_functiondef` dos objetos deste inventário; incluir todas as sobrecargas.
2. Contagens agregadas das anomalias acima, sem exportar NIF/NISS/documentos pessoais para este relatório versionado.
3. Regras efetivas de Storage, bucket público/privado, SELECT/INSERT/UPDATE/DELETE e origem dos caminhos.
4. Estado dos jobs relevantes e últimas execuções, somente leitura. Não chamar a rotina para testar.
5. Sessão real de Belmira para abrir/fechar formulários e consultar históricos, sem Guardar, confirmar importação, resolver alerta ou apagar.

## 14. Testes existentes e execução desta auditoria

Executado no commit de produção indicado, sem alteração de testes: **35 ficheiros, 90 testes; 87 aprovados, 2 falhas preexistentes, 1 omitido**.

As duas falhas:

- `foreman-global-workforce-vacations.test.mjs`: exige que Encarregado perca o quadro e usa uma lista antiga de vistas/abas. Contradiz a restauração em `96ad5f8` e os testes novos do quadro operacional.
- `rh-work-finance-crossing.test.mjs`: falha em `!foreman.views.includes('workforce')`, pela mesma decisão antiga.

Omitido: caso opcional de Excel real de 47 linhas, por ausência de `RH_XLSX`. Não foram usados dados pessoais reais em substituição.

A primeira execução tinha uma terceira falha, exclusivamente de ambiente: `xlsx.full.min.js` não estava no diretório das dependências PGlite/jsdom. Foi reutilizado o ficheiro já existente em `%TEMP%/primeline-medicina-test-deps/xlsx.full.min.js`, através de um resolvedor temporário de testes. Nenhuma dependência foi instalada nem ficheiro funcional alterado. A repetição passou esse teste.

### Inventário e qualidade

| Testes | Tipo / cobertura | Avaliação |
|---|---|---|
| `rh-cadastro.test.mjs` | Parsing, PGlite, importação/lote/versão/permissões, DOM com API simulada | Boa cobertura do cadastro; helpers de autorização sintéticos e não RLS real completa |
| `rh-cadastro-browser.mjs` | Browser isolado, API simulada, desktop/mobile, Excel | Existe; não executado nesta auditoria; não certifica sessão de Belmira |
| `supabase-collaborators.test.mjs` | Mock fetch, opt-out explícito de inativos | Passa o helper, mas não testa o consumidor que esquece a opção |
| `collaborator-complete-fields`, `collaborator-lifecycle`, `collaborator-rh-conformity`, `active-collaborators-admission` | Predominantemente texto/regex de SQL/JS | Parcial; não demonstra ciclo de vida completo |
| `absences-workflow`, `overtime-workflow`, `employment-contract-alerts` | Contratos textuais de fluxo/SQL | Parcial; não testa renovação, pagamento, anexos órfãos ou concorrência |
| `workforce-admin-only`, `workforce-operational-report`, `workforce-movements-permissions`, `workforce-foremen-multiple-works` | Matriz/SQL/consumidores por inspeção | Passam, mas não provam atomicidade, isolamento real ou Escritório |
| `workforce-vacations`, `workforce-allocation-scroll`, `workforce-absence-visual`, `workforce-holidays-visual` | Presença de handlers/CSS/expressões | Parcial; nome “visual” não significa navegador real |
| `foreman-global-workforce-vacations`, `rh-work-finance-crossing` | Asserções antigas | Desatualizados, falhas reproduzidas; não corrigidos |
| `access-control`, `adjunto-access-parity`, `finance-operational-access`, `session-isolation` | Funções/matriz e inspeção | Não substituem testes authenticated contra RLS/RPC reais |
| `audit-log`, `audit-view`, `alert-priority-email`, `alert-resolver-user-fk`, `alerts-expiry-resolution` | Presença de SQL/UI e contratos | Falta prova de catálogo ativo, reconciliação e pesquisa histórica completa |
| `documents-center`, `restricted-deletion-paths` | Texto/fluxos | Falta falha parcial Storage/BD, correção de metadados e inativos |
| `vehicle-assignment-client`, `vehicle-validity`, `vehicle-deadlines`, `vehicles-module` | Contrato cliente, funções e inspeção | Executados; não cobrem o formulário antigo de Equipa ponta a ponta |
| `vehicle-assignment.test.mjs`, `vehicle-assignment-concurrency.test.mjs`, browsers de viaturas | PGlite/PostgreSQL nativo/browser | Existem; não repetidos nesta auditoria documental. Resultados anteriores não são nova execução |
| Ponto individual | Só referências em testes de quadro/relatório encontradas | **Ausência de suite funcional dedicada** para listar/guardar/validar, concorrência e retificação |
| Medicina controlada | 37 testes locais, incluindo sessões concorrentes, na branch separada | Passaram na tarefa anterior; não executados novamente nem integrados aqui |

Lista exata dos 35 ficheiros executados: `absences-workflow`, `access-control`, `active-collaborators-admission`, `adjunto-access-parity`, `alert-priority-email`, `alert-resolver-user-fk`, `alerts-expiry-resolution`, `audit-log`, `audit-view`, `collaborator-complete-fields`, `collaborator-lifecycle`, `collaborator-rh-conformity`, `documents-center`, `employment-contract-alerts`, `finance-operational-access`, `foreman-global-workforce-vacations`, `global-scroll-safeguard`, `overtime-workflow`, `restricted-deletion-paths`, `rh-cadastro`, `rh-work-finance-crossing`, `session-isolation`, `supabase-collaborators`, `vehicle-assignment-client`, `vehicle-deadlines`, `vehicle-validity`, `vehicles-module`, `workforce-absence-visual`, `workforce-admin-only`, `workforce-allocation-scroll`, `workforce-foremen-multiple-works`, `workforce-holidays-visual`, `workforce-movements-permissions`, `workforce-operational-report`, `workforce-vacations` (todos em `tests/`, sufixo `.test.mjs`).

Provas adicionais, somente em memória: helper de Escritório com RH devolveu `false`; consumidor de inativos não fornece opt-out; template de horas extra interpretou `<b data-audit-probe>` como elemento DOM. Não foram adicionados testes ao repositório nesta tarefa.

## 15. Matriz permanente de regressão proposta

| Área | Já coberto de forma útil | Automatizar antes da aceitação | Validação humana restante |
|---|---|---|---|
| Cadastro | Criar/editar/importar, rollback de lote, NISS e versão | Inativo carregado, edição histórica, request repetido, API direta negada, empresa B | Conteúdo obrigatório, termos e permissões de RH |
| Contratos | Correção do ativo e importação parcial | Renovar/encerrar, unicidade concorrente, alerta após mudar data, tipo desconhecido | Tipo/datas efetivas e critérios de renovação |
| Medicina | Backend separado já testado | UI com mocks de sucesso/erro/stale/replay; atual/histórico; inativo; integração autorizada | Significado de aptidão e próxima consulta, documento correto |
| EPI | Inserção inicial | Nova entrega/correção/anulação, validade e auditoria, sem apagar histórico | Catálogo, periodicidade e comprovação de entrega |
| Documentos | Helpers/fluxos básicos | Upload falha após bytes; DELETE parcial; retry; metadados; empresa; inativo; vínculo à consulta | Legibilidade, classificação e política de retenção |
| Quadro | Regras textuais e UI | Escritório, mesma pessoa dois operadores, falha após delete, movimento reversível, múltiplas obras | Semântica diária versus continuidade |
| Ponto | Exportador referido | Listar/guardar/validar; revisões; sobreposição concorrente; ausência posterior; data passada; inativo; obra fechada | Janela de retificação e quem decide |
| Férias | Editor e mapa | Alteração atómica, feriado/fim de semana, exclusão, inativo, conflito ponto | Aprovação/saldos/dias aplicáveis |
| Ausências | Estados e comentário | Anexo falhado, trocar pessoa/data, cancelar, concorrência, mínimo visível a Encarregado | Classificação/justificação e remuneração |
| Horas extra | Entrada e checks textuais | Correção/aprovação/pagamento/reversão; repetição; horas máximas; empresa | Autoridade de aprovação e prova de pagamento |
| Viaturas | Cliente e backend já existentes | Ligação à ficha, formulário Equipa, saída com várias viaturas, responsável inativo | Aceitação da desatribuição antes de saída |
| Alertas | Resolver e índice previstos | Origem muda/desaparece, duplicado, reativação, resolvido não reabre, parâmetros | Quais avisos exigem ação e destinatário |
| Segurança/UX | Matriz e CSS | Conteúdo HTML hostil, accessibilidade, 390/768/1024/1366 px, sessão expirada, listas paginadas | Teste de toque em obra, compreensão pela Belmira |

## 16. Ficha central recomendada

**Equipa → Colaboradores → abrir ficha** deve ser o acesso central tanto a ativos como a inativos. O botão Editar pode abrir a mesma ficha em modo de edição, sem misturar correções de cadastro com novos eventos.

| Secção | Classificação | Conteúdo/ações |
|---|---|---|
| Cabeçalho | 2 | Nome, estado efetivo, código RH, empresa, pendências; Inativar/Reativar como ações explícitas |
| Cadastro | 1 | Identificação, contactos, função/nível, valor/hora, admissão/nascimento, NIF/NISS, conformidade e notas, conforme papel |
| Contratos | 2 | Ativo + anteriores; Corrigir, Novo/Renovar, Encerrar com motivo e datas |
| Medicina | 2 | Consulta atual e histórico; Nova consulta, Corrigir, Anular usando backend preparado; vínculo à ficha de aptidão |
| EPI | 2 | Entregas e validade por tipo; Nova entrega e correção auditada |
| Documentos | 2 | Upload/download, metadados e relação com eventos; versão/substituição e eliminação autorizada |
| Atividade | 3 | Obra atual/por data, ponto, férias/ausências, horas extra, viatura; links preservam pessoa/data |
| Histórico | 2 | Eventos de RH legíveis, com autor/motivo/data; não despejo indiscriminado de JSON |
| Login e permissões | 3 ou 4 | RH vê apenas associação autorizada; criar conta/gerir permissões fica em Definições/Gestão |
| NISS, contactos privados, valor/hora, motivos pessoais | 4 para técnicos | Encarregado recebe projeção operacional mínima, nunca o formulário administrativo completo |

1 = editável diretamente; 2 = visível com ação específica; 3 = resumo/link operacional; 4 = não expor nesse perfil. `permite_multiplas_obras` deve ter ação autorizada explícita, não ser deduzido de nome. Empresa não deve ser um seletor livre que reatribui históricos.

## 17. Priorização, impacto e dependências

| Prioridade | Itens | Utilizadores/impacto | Exige alteração de BD? | Decisão humana |
|---|---|---|---|---|
| P0 | RH-03 troca não atómica; RH-08 HTML não escapado | RH/operacionais; perda de alocação ou conteúdo executável | Troca atómica: sim; escape: não | Sem decisão para escape; semântica da troca sim |
| P0 condicionado à instalação/exposição | RH-16/17/23 isolamento/DML; RH-19 concorrência | Empresas e pessoas afetadas; acesso cruzado/corrupção | Confirmar catálogo; provavelmente sim | Delimitação de poderes e empresa |
| P1 | RH-01/02/04/05/06/07, RH-09/10, RH-15, RH-18/20/21/22/24/25 | Fluxos essenciais de RH e encarregados | Misto; ver secções 20/21 | Contrato, ponto, HE e eventos de correção |
| P2 | RH-11/12/13/14/26; auditoria inacessível; mobile e paginação | RH, gestão e encarregados; decisões com informação incompleta | Algumas leituras/pesquisas podem exigir RPC | Saída futura, antecedências e minimização |
| P3 | Links entre módulos, foco de erro, filtros guardados, resumo de viatura | Conveniência e descoberta das ações | Geralmente não | Layout e linguagem |

Riscos P0 potenciais não foram explorados na produção. A recomendação é testar num ambiente sintético/staging e consultar o catálogo, não experimentar escritas sobre pessoas reais.

## 18. Pacotes de implementação propostos

1. **Segurança e integridade imediatas:** escape de HTML; confirmar RLS/grants/empresa; troca de alocação atómica; provas de concorrência.
2. **Ficha e inativos:** corrigir opt-out, abrir histórico sem reativar, links para documentos/viatura, estados e mensagens de erro.
3. **Alocação e ponto:** decidir modelo temporal único; RPCs seguras, revisão e retificação, exportação coerente, ausência/ponto coordenados.
4. **Medicina:** concluir autorização de aplicação do backend já preparado, depois UI e leitura de consulta corrente. Não redesenhar RPCs existentes.
5. **Contratos:** renovar/encerrar/corrigir; tratar pendências confirmadas pelo RH; reconciliar alertas e unicidade.
6. **EPI e documentos:** ações de entrega/validade/histórico, vínculos documentais, correções de metadados e recuperação de falhas Storage.
7. **Férias/ausências/HE:** operações atómicas, cancelamento/correção, aprovação/pagamento, mínimo de informação por perfil.
8. **Auditoria, alertas e UX:** pesquisa por pessoa e período, reconciliadores restantes, paginação, toque/tablet e suite permanente.

Cada pacote deve ter preflight do schema real e autorização própria antes de SQL. Não agrupar tudo numa migration genérica de RH.

## 19. Ordem recomendada

1. Completar a leitura real pendente e validar as regras de empresa/perfil sem escrita.
2. Corrigir RH-08 e os bloqueios frontend RH-01/RH-02; testar sem alterar dados reais.
3. Tratar RH-03 e a divergência quadro/ponto antes de testes de movimentação em produção.
4. Levar a Medicina preparada à etapa de aplicação apenas após precheck/backup e autorização específicos; depois integrar a UI.
5. Ficha histórica, contratos, EPI e restantes ações essenciais.
6. Alertas não médicos, auditoria, mobile e aceitação dirigida pelos responsáveis.

## 20. Correções possíveis sem migration

- Escape das interpolações, opt-out correto de inativos, ordem do helper de autorização de Escritório.
- Abrir ficha histórica e documentos, incluir resumo/link da viatura, reutilizar consulta RH que aceita UUID inativo.
- KPI de contrato incompleto, erro explícito por fonte e paginação das leituras onde o contrato atual já permite.
- Substituir o formulário antigo de viatura pelo componente controlado existente.
- Consumir o parâmetro de antecedência por leitura já autorizada, se disponível; não expor configurações privadas só para isso.
- Layout, alvos de toque, foco, mensagem de gravação parcial e testes de consumidores reais.
- Atualizar testes antigos conforme decisão de produto já implementada. **Não foi feito nesta auditoria.**

Integração frontend de Medicina é sem nova conceção de schema, mas depende da aplicação autorizada da branch preparada; não chamar RPC inexistente simulando sucesso.

## 21. O que exige alteração de BD ou preflight específico

- Escrita atómica de alocação/férias; guardas coordenadas de concorrência.
- Isolamento por empresa, projeções mínimas e retirada de DML direto que contorne workflows.
- Retificação de ponto com revisão/autor/motivo e decisões de justificação protegidas.
- Renovação/encerramento contratual, constraints após diagnóstico de duplicados, reconciliação de alertas.
- EPI com eventos de entrega/correção, autoria e histórico.
- Vínculos documentais com consulta/contrato, integridade de entidade/empresa e tratamento de eliminação/retificação.
- Aprovação/pagamento/cancelamento de horas extra e ausências quando o modelo atual não os representa.
- RPC de auditoria legível por pessoa/empresa/período, sem revelar NISS a perfis técnicos.

Não é autorização de execução nem desenho final de migration. Reutilizar primeiro constraints e funções efetivamente instaladas, ainda por levantar.

## 22. O que precisa de validação humana/RH

- Tipos e datas dos 47 contratos; que operações são renovação versus correção.
- Critério de consulta válida, aptidão e periodicidade; próxima data NULL não equivale a erro nem a prazo infinito confirmado.
- Catálogo/periodicidade de EPI e comprovativos de entrega.
- Semântica de alocação (diária ou permanente), múltiplas obras e quem autoriza exceções.
- Quem pode retificar ponto, até quando, e o que acontece a períodos já usados em custos/pagamentos.
- Aprovação/saldo de férias, feriados municipais aplicáveis e ausências remuneradas.
- Autorização de horas extra, pagamento, estorno e ligação financeira.
- Data de saída futura, reativação, retenção documental e acesso ao histórico de inativos.
- Campos privados permitidos por perfil e conteúdo mínimo que o Encarregado pode consultar.

## 23. Testes finais a executar pelos responsáveis

Em ambiente de teste ou com dados sintéticos autorizados; produção apenas mediante plano próprio:

- **Belmira:** localizar pessoa ativa/inativa, completar cadastro, distinguir corrigir/renovar, consultar histórico e documentos sem reativar; interpretar pendências; recuperar de erro de gravação sem duplicar.
- **Encarregado:** localizar equipa correta no dia/obra, compreender falta pendente versus validada, testar toque/scroll no tablet e confirmar que não vê dados privados indevidos.
- **Gerência/Gestão:** aprovar permissões, importação e regras de reversão; confirmar autores/histórico; aceitar bloqueio de saída com viaturas.
- **RH:** conferir tipo contratual, aptidão e comprovativos reais. Esta verificação documental não pode ser substituída por testes automáticos.
- **Financeiro/RH:** confirmar significado de horas extra pagas e do relatório de ponto, sem assumir que lançar horas gera pagamento.

Sessão real de Belmira, fluxo visual completo, mobile físico, cron instalado e comportamento real das policies continuam **não validados nesta auditoria**.

## 24. Testes que podem deixar de depender de verificação manual

Automatizar: CRUD autorizado por papel/empresa; restrição API direta; preservação/limpeza de campos; inativos; payloads; estado de botões; preview sem escrita; lote atómico; idempotência; concorrência; revisão obsoleta; calendário com relógio fixo; transições contratuais; alertas com origem alterada; falha de Storage; ausência posterior ao ponto; consulta histórica; limites de paginação; escape de conteúdo; renderização em vários tamanhos.

Manter humano: confirmação dos factos documentais, atribuição de poderes de negócio, clareza da linguagem e ergonomia no dispositivo real. “Teste passou” não comprova que os dados reais estão corretos.

### Fecho

Nenhuma implementação funcional, alteração de dados, migration, deploy ou integração da branch Medicina nesta tarefa. O único artefacto a versionar é este relatório. A inspeção de diferenças confirma que nenhum ficheiro funcional foi alterado. A auditoria encontrou problemas adicionais aos antecipados no pedido, mas **não certifica o estado real da BD enquanto as verificações V não forem concluídas**.

## Anexo A — matriz detalhada de campos e ações

G = Gestão da Plataforma; Ger = Gerência; A = Administrativo; RH = esses três perfis. C/E/correção abaixo descrevem a UI atual, exceto onde se indica explicitamente backend preparado. V = não verificado na sessão/BD real. “Log previsto” exige confirmação do trigger ativo; não é garantia de instalação.

### Cadastro

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Cadastro | Nome | colaboradores.nome | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Obrigatório; HTML inseguro em HE | RH-08: escape em todos os consumidores | P0 |
| Cadastro | Função/categoria | colaboradores.funcao | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Texto livre; critérios operacionais derivados de texto | Validar classificação com RH sem mudar nomes históricos | P2 |
| Cadastro | Nível | colaboradores.nivel | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Sem catálogo de níveis | Definir se texto livre é suficiente | P3 |
| Cadastro | Valor/hora | colaboradores.valor_hora | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Sem vigência temporal; não equivale a salário/pagamento | Definir histórico de preço e efeito em custos | P2 |
| Cadastro | NIF | colaboradores.nif | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Formato 9 dígitos; via direta/duplicação por empresa V | RH-16; confirmar necessidade de dígito de controlo | P1 |
| Cadastro | Email | colaboradores.email | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Validado na RPC; exposição por API V | Projeção mínima por perfil | P2 |
| Cadastro | Contacto | colaboradores.contacto | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Sem validação semântica estruturada | Confirmar formato/uso internacional | P3 |
| Cadastro | Morada | colaboradores.morada | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Informação privada em colaboradores | Verificar grants de coluna | P1 |
| Cadastro | Nascimento | colaboradores.data_nascimento | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Aniversário UI | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Valida relação com admissão; visível no aniversário | Minimizar exposição; testar calendário | P2 |
| Cadastro | Admissão | colaboradores.data_admissao | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Primeira consulta | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Obrigatória; alimenta primeira consulta | Auditar correção e reconciliar dependências | P1 |
| Cadastro | Código RH | colaboradores.codigo_rh | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Duplicado verificado só na RPC; não aparece na lista | Pesquisa e integridade por empresa | P2 |
| Cadastro | Observações | colaboradores.observacoes | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Texto livre pode conter dados desnecessários | Orientar conteúdo, proteger leitura | P2 |
| Cadastro | Registo trabalhador confirmado | colaboradores.registo_trabalhador_ok | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Boolean opcional sem comprovativo/data | Não confundir com conformidade documental automática | P2 |
| Cadastro | Seguro confirmado | colaboradores.seguro_ok | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Boolean sem validade ou apólice | Clarificar e ligar documento se aprovado | P2 |
| Cadastro | Inscrição SS confirmada | colaboradores.seguranca_social_ok | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Limpar opcional; não apagar pessoa | Sim por RH | Antes/depois; não temporal | RH + log previsto | Não específico | RH (G/Ger/A); API V | RPC sim; UI bloqueada RH-01/07 | CSS adapta; visual V | Separado corretamente de NISS | Preservar separação; sem preenchimento inferido | P3 |
| Cadastro | NISS | colaboradores_rh_privado.niss | Script/ref.; real V | Ficha e Excel | Sim | Sim | Sim | Pode limpar | Só RH | Antes/depois privado | rh_cadastro_auditoria | Não | RH (G/Ger/A); API V | RPC sim; UI RH-01/07 | CSS adapta; visual V | Não confundir com seguranca_social_ok; unicidade V | Preservar grants privados | P1 |
| Cadastro | Empresa | colaboradores.empresa_id | Script/ref.; real V | Não na ficha | Sessão | Não UI | Sem fluxo | Não | Não livremente | Log previsto | Log | Não | Gestão; decisão | V | V | Reatribuição afeta todos os vínculos | Operação própria se necessária | P1 |
| Cadastro | Conta/login associada | utilizadores.auth_user_id; vínculo pessoa V | Script/ref.; real V | Definições, não ficha | Fora do cadastro | Gestão separada | Parcial | Desativação de conta separada | Não pelo cadastro geral | Log utilizadores | Prevista | Não | Gestão | V | V | Não foi provada FK pessoa-conta no catálogo | Resumo/link e preflight de associação | P2 |
| Cadastro | Permite múltiplas obras | colaboradores.permite_multiplas_obras | Script/ref.; real V | Consumido, sem campo | Default/backfill antigo | Não UI | Não UI | Não UI | Ação autorizada | Log previsto | Log | Não | RH (G/Ger/A); API V | Sem UI | CSS adapta; visual V | Campo fora da whitelist RH; classificação também por função | Definir ação e retirar dependência de nomes | P1 |
| Cadastro | Saída/inativar | colaboradores.data_saida | Script/ref.; real V | Editar ativo | Sim | Sim | Sim para ativo | Inativa sem apagar | Ação específica | Dados preservados | RH/log | Limpeza legada parcial | RH (G/Ger/A); API V | Depois fica sem ficha | CSS adapta; visual V | Data futura inativa já; viatura pode bloquear | RH-26; ligação para desatribuir viatura | P1 |
| Cadastro | Reativar | fn_atualizar_colaborador_ciclo_vida | Script/ref.; real V | Painel Inativos | Não aplicável | Ação | Ação | Não aplicável | Ação específica | Preserva dados; não histórico de vínculos | Log previsto | Regera legado | RH (G/Ger/A); API V | Bug: painel recebe ativos | CSS adapta; visual V | RH-01; sobrecargas sem empresa RH-17 | Corrigir consumidor; preservar guardas | P1 |
| Cadastro | Importar Excel | fn_rh_importar | Script/ref.; real V | Botão Gestão | Só existentes | Sim, parcial | Sim | Não inativa/não apaga | Gestão | Antes/depois por pessoa | RH | Contrato não reconciliado | G apenas | RPC inclui; modelo pode incluir | CSS adapta; visual V | Sem criação, sem limpar por vazio; ficheiro contém dados privados | Manter avisos e testar consumidores | P2 |

### Contrato

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Contrato | Tipo | colaboradores_contratos.tipo_contrato | Script/ref.; real V | Ativo e histórico da ficha | Sim | Só ativo | Sim | Não fluxo de encerramento | Correção com motivo; renovação separada | Linha antiga no log; histórico de contratos lido | RH/log | Fim contratual | RH (G/Ger/A); API V | UI sem acesso; RPC consulta | CSS adapta; visual V | 47 sem tipo: R, não recontado | RH-11/21; validar documentos | P1 |
| Contrato | Início | colaboradores_contratos.data_inicio | Script/ref.; real V | Ativo e histórico da ficha | Sim | Só ativo | Sim | Não fluxo de encerramento | Correção com motivo; renovação separada | Linha antiga no log; histórico de contratos lido | RH/log | Fim contratual | RH (G/Ger/A); API V | UI sem acesso; RPC consulta | CSS adapta; visual V | Sem reconciliação após correção | RH-11/21; validar documentos | P1 |
| Contrato | Fim previsto | colaboradores_contratos.data_fim_prevista | Script/ref.; real V | Ativo e histórico da ficha | Sim | Só ativo | Sim | Não fluxo de encerramento | Correção com motivo; renovação separada | Linha antiga no log; histórico de contratos lido | RH/log | Fim contratual | RH (G/Ger/A); API V | UI sem acesso; RPC consulta | CSS adapta; visual V | Sem reconciliação após correção | RH-11/21; validar documentos | P1 |
| Contrato | Estado e renovação | colaboradores_contratos.estado | Script/ref.; real V | Estado visível | Ativo via cadastro | Sem botão | Não | Sem encerrar/renovar | Ação específica | Só se novos vínculos forem criados | Log previsto | Fim contratual | RH (G/Ger/A); API V | UI não | CSS adapta; visual V | Estados existem sem workflow | Novo vínculo e transição auditada | P1 |
| Contrato | Contrato ativo único | colaboradores_contratos | Script/ref.; real V | Um ativo; múltiplos bloqueiam | RPC verifica | Bloqueia se vários | Sem resolução UI | Não | Não campo livre | Histórico listado | RH/log | Tipo vazio fora do KPI | RH (G/Ger/A); API V | RPC consulta | CSS adapta; visual V | Sem UNIQUE parcial encontrado; API V | Preflight e resolução de duplicados | P1 |
| Contrato | PDF e vínculo | documentos entidade colaborador | Script/ref.; real V | Documentos separado | Upload | Não metadados UI | Reenviar/apagar | DELETE documento | Ação específica | Sem versão documental RH | Log previsto | Validade documento | RH (G/Ger/A); API V | UI não | CSS adapta; visual V | Sem contrato_id estruturado | Relacionar evento e ficheiro sem duplicar | P2 |

### Medicina

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Medicina | Data realizada | medicina_trabalho.data_ultima_consulta | Script/ref.; real V | Lista global | Só criação pessoa | Não UI | Não UI | Não UI | Ação específica | Linhas existem; sem navegação por pessoa | Legado V; branch sim | Primeira/vencimento | RH ler; Encarregado limitado | Filtrado no frontend | CSS adapta; visual V | Backend controlado preparado; consumidor legado | Integrar RPCs da branch após autorização | P1 |
| Medicina | Próxima consulta | medicina_trabalho.data_proxima_consulta | Script/ref.; real V | Lista global | Não UI | Não UI | Não UI | Não UI | Ação específica | Linhas existem; sem navegação por pessoa | Legado V; branch sim | Primeira/vencimento | RH ler; Encarregado limitado | Filtrado no frontend | CSS adapta; visual V | Backend controlado preparado; consumidor legado | Integrar RPCs da branch após autorização | P1 |
| Medicina | Resultado/aptidão | medicina_trabalho.resultado | Script/ref.; real V | Lista global | Texto inicial automático | Não UI | Não UI | Não UI | Ação específica | Linhas existem; sem navegação por pessoa | Legado V; branch sim | Primeira/vencimento | RH ler; Encarregado limitado | Filtrado no frontend | CSS adapta; visual V | Backend controlado preparado; consumidor legado | Integrar RPCs da branch após autorização | P1 |
| Medicina | Nova/corrigir/anular | RPCs fn_medicina_* na branch | Script/ref.; real V | Não produção | Backend preparado | Backend preparado | Com motivo/revisão preparado | Anulação preparada | Ação específica | Eventos/autor preparados | medicina_operacoes preparada | Reconciliação preparada | RH escrita; Enc leitura | Backend permite histórico | UI por construir | Não aplicada nem integrada | Não refazer backend; não usar PATCH | P1 |
| Medicina | Consulta atual/histórico | medicina_trabalho; RPC branch | Script/ref.; real V | Lista sem separação atual | Não aplicável | Não UI | Não UI | Não UI | Não campo livre | Atual determinística na branch | Branch | Legado conta linhas | RH/Enc | Não UI | CSS adapta; visual V | Várias consultas contam como pessoas/avisos | Consumir atual/histórico da RPC | P1 |
| Medicina | Ficha de aptidão | documentos.tipo_documento=ficha_aptidao | Script/ref.; real V | Arquivo da pessoa | Upload | Não metadados UI | Reenvio | Apagar | Ação específica | Sem versionamento por consulta | Log documento previsto | Validade separada | RH (G/Ger/A); API V | Não UI | CSS adapta; visual V | Sem consulta_id; não extrair dados clínicos | Vínculo e projeção autorizada | P2 |

### EPI

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EPI | Tipo EPI | epis.tipo_epi | Script/ref.; real V | Segurança da obra | Entrega inicial fixa | Não | Não | Não | Evento/correção | Registos existem; sem ação contínua | Não comprovada | Se validade preenchida | RH (G/Ger/A); API V | Filtro ativos Segurança | CSS adapta; visual V | Entrega inicial sem validade; não existe editor RH | Workflow de entrega/correção | P1 |
| EPI | Data entrega | epis.data_entrega | Script/ref.; real V | Segurança da obra | Só criação pessoa | Não | Não | Não | Evento/correção | Registos existem; sem ação contínua | Não comprovada | Se validade preenchida | RH (G/Ger/A); API V | Filtro ativos Segurança | CSS adapta; visual V | Entrega inicial sem validade; não existe editor RH | Workflow de entrega/correção | P1 |
| EPI | Validade | epis.data_validade | Script/ref.; real V | Segurança da obra | Não UI | Não | Não | Não | Evento/correção | Registos existem; sem ação contínua | Não comprovada | Se validade preenchida | RH (G/Ger/A); API V | Filtro ativos Segurança | CSS adapta; visual V | Entrega inicial sem validade; não existe editor RH | Workflow de entrega/correção | P1 |
| EPI | Nova entrega e comprovativo | epis + documentos sem vínculo | Script/ref.; real V | Não | Não para existente | Não | Não | Não | Ação específica | Não consumível na ficha | V | Histórico pode alertar | RH (G/Ger/A); API V | Não UI | Não UI | Sem autor/itens/ligação documental comprovados | Preflight EPI e requisitos RH | P1 |

### Documentos RH

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Documentos RH | Ficheiro/nome | documentos.nome_arquivo,url_arquivo | Script/ref.; real V | Arquivo | Upload | Não | Só apagar/reenviar | Apagar com confirmação | Metadados corrigíveis com motivo | Log não preserva bytes apagados | Prevista no script de eliminações | Validade diária | RH (G/Ger/A); API V | UI não | CSS adapta; visual V | RH-10; falta edição, vínculo e retenção | Metadados seguros; recuperação falhas | P1 |
| Documentos RH | Tipo | documentos.tipo_documento | Script/ref.; real V | Texto livre | Sim | Não | Só apagar/reenviar | Apagar com confirmação | Metadados corrigíveis com motivo | Log não preserva bytes apagados | Prevista no script de eliminações | Validade diária | RH (G/Ger/A); API V | UI não | CSS adapta; visual V | RH-10; falta edição, vínculo e retenção | Metadados seguros; recuperação falhas | P1 |
| Documentos RH | Emissão | documentos.data_emissao | Script/ref.; real V | Upload/lista | Sim | Não | Só apagar/reenviar | Apagar com confirmação | Metadados corrigíveis com motivo | Log não preserva bytes apagados | Prevista no script de eliminações | Validade diária | RH (G/Ger/A); API V | UI não | CSS adapta; visual V | RH-10; falta edição, vínculo e retenção | Metadados seguros; recuperação falhas | P1 |
| Documentos RH | Validade | documentos.data_validade | Script/ref.; real V | Upload/lista | Sim | Não | Só apagar/reenviar | Apagar com confirmação | Metadados corrigíveis com motivo | Log não preserva bytes apagados | Prevista no script de eliminações | Validade diária | RH (G/Ger/A); API V | UI não | CSS adapta; visual V | RH-10; falta edição, vínculo e retenção | Metadados seguros; recuperação falhas | P1 |
| Documentos RH | Download | storage documentos | Script/ref.; real V | Botão | Não aplicável | Não aplicável | Não aplicável | Não aplicável | Não | Não há histórico de acesso demonstrado | V | Não | RH (G/Ger/A); API V | Backend V; UI não | CSS adapta; visual V | Bytes não verificados; só caminho | Validar permissionamento e arquivo | P2 |
| Documentos RH | Apagar | fn_apagar_documento_entidade + Storage | Script/ref.; real V | Botão confirmado | Não aplicável | Não aplicável | Não aplicável | Sim em dois passos | Ação específica | Metadados log; bytes não | Prevista | Reconciliação V | RH (G/Ger/A); API V | Não UI | CSS adapta; visual V | Metadados apagados antes dos bytes | Operação recuperável; empresa e retenção | P1 |

### Alocação

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Alocação | Obra/local | quadro_pessoal_alocacao.obra_id,tipo_alocacao,descricao_livre | Script/ref.; real V | Quadro | Sim | Sim | Sim sem revisão | DELETE | Ação de movimento | Movimentos próprios | Log/movimentos | Ausência bloqueia | RH; Diretor/Enc própria obra | Ativos UI | CSS adapta; visual V | RH-02/03/04: atomicidade e modelo temporal | RPC atómica e regra única de data | P1 |
| Alocação | Data/semana | quadro_pessoal_alocacao.data,semana_inicio | Script/ref.; real V | Quadro | Sim | Sim | Sim sem revisão | DELETE | Ação de movimento | Movimentos próprios | Log/movimentos | Ausência bloqueia | RH; Diretor/Enc própria obra | Ativos UI | CSS adapta; visual V | RH-02/03/04: atomicidade e modelo temporal | RPC atómica e regra única de data | P1 |
| Alocação | Período | quadro_pessoal_alocacao.periodo | Script/ref.; real V | Quadro | Sim | Sim | Sim sem revisão | DELETE | Ação de movimento | Movimentos próprios | Log/movimentos | Ausência bloqueia | RH; Diretor/Enc própria obra | Ativos UI | CSS adapta; visual V | RH-02/03/04: atomicidade e modelo temporal | RPC atómica e regra única de data | P1 |
| Alocação | Autor/histórico | criado_por; quadro_pessoal_movimentos | Script/ref.; real V | Movimentos | Automático/cliente | Não ação livre | Não | DELETE da alocação gera movimento | Não | Sim nos scripts | Sim | Não | RH/gestor de obra | UI limitado | CSS adapta; visual V | DML altera criado_por; movimento guarda autor separado | Usar autoria servidor e preservar original | P2 |
| Alocação | Pessoa sem obra/múltiplas | alocacao + permite_multiplas_obras | Script/ref.; real V | Ímanes disponíveis | Inicial Escritório sim | Movimento Escritório falha | Sem ação de flag | Remover pode revelar evento antigo no ponto | Ação específica | Movimentos | Prevista | Não | RH/operacionais | Não | CSS adapta; visual V | Ponto escolhe última obra por período | Decidir cobertura simultânea e horários reais | P1 |

### Ponto

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ponto | Data/obra | ponto_pessoal_obra.data,obra_id | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Estado | ponto_pessoal_obra.estado | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Entrada manhã | ponto_pessoal_obra.entrada_manha | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Saída manhã | ponto_pessoal_obra.saida_manha | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Entrada tarde | ponto_pessoal_obra.entrada_tarde | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Saída tarde | ponto_pessoal_obra.saida_tarde | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Observação | ponto_pessoal_obra.observacao | Script/ref.; real V | Ponto por dia/obra | RPC | RPC upsert | Sem motivo/revisão | Sem anular | Correção controlada | Log previsto; linha atual sobrescrita | Autores + log | Não específico | RH/Enc obra | Lista exclui; escrita não testa saída | CSS adapta; visual V | RH-18/19/20: concorrência e histórico | Revisão, período e guardas | P1 |
| Ponto | Horas/períodos | horas,periodos_alocados | Script/ref.; real V | Total e horários | Calculado | Via horários | Via horários | Sem anular | Não direto | Log | Prevista | Não | RH/Enc | Relatório sim | CSS adapta; visual V | Alocação carregada por continuidade; total default antes de gravar | Distinguir proposto/registado; regra temporal | P1 |
| Ponto | Validar/rejeitar justificação | justificacao_estado | Script/ref.; real V | Botões RH quando pendente | Gerado | RPC decisão | Sem motivo obrigatório | Pode redecidir por API | Ação específica | Log; último autor | Prevista | Não | RH | Lista não | CSS adapta; visual V | RPC não exige pendente; regravar repõe pendente | Transição protegida/revisão | P1 |
| Ponto | Autores/datas | registado_por,atualizado_por,criado_em,atualizado_em | Script/ref.; real V | Não na linha UI | Servidor | Servidor | Não | Não | Não | Parcial mais log | Sim previsto | Não | RH auditoria | Relatório não mostra | V | Sem histórico navegável | Resumo e histórico autorizado | P2 |
| Ponto | Relatório mensal | fn_relatorio_mensal_ponto | Script/ref.; real V | Excel/CSV | Exportar | Não | Origem | Não | Não | Lê pontos históricos | Exportação V | Não | RH | Sim no SQL | CSS adapta; visual V | Classifica falta pelo estado inicial; função da pessoa atual | Distinguir decisão final e vigência | P2 |

### Férias

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Férias | Dias de férias | ausencias tipo ferias | Script/ref.; real V | Editor segunda–sexta | POST | POST+DELETE | POST+DELETE | DELETE | Ação específica | Log previsto; cancelamento físico | Prevista | Não | RH gere; técnicos leem | Ativos no mapa | CSS adapta; visual V | Sem workflow de pedido/aprovação; dias laborais fixos | Decisão RH e alteração atómica | P2 |
| Férias | Mapa mensal | ausencias tipo ferias | Script/ref.; real V | Mapa global | Não aplicável | Não | Não | Não | Não | Log previsto; cancelamento físico | Prevista | Não | RH gere; técnicos leem | Ativos no mapa | CSS adapta; visual V | Sem workflow de pedido/aprovação; dias laborais fixos | Decisão RH e alteração atómica | P2 |
| Férias | Aprovação/saldo | ausencias tipo ferias | Script/ref.; real V | Não | Não | Não | Não | Não | Ação específica | Log previsto; cancelamento físico | Prevista | Não | RH gere; técnicos leem | Ativos no mapa | CSS adapta; visual V | Sem workflow de pedido/aprovação; dias laborais fixos | Decisão RH e alteração atómica | P2 |
| Férias | Feriados | feriados_empresa | Script/ref.; real V | Mapa/configuração | Definições | Definições | Definições | V | Ação específica | Log previsto; cancelamento físico | Prevista | Não | RH gere; técnicos leem | Ativos no mapa | CSS adapta; visual V | Sem workflow de pedido/aprovação; dias laborais fixos | Decisão RH e alteração atómica | P2 |

### Ausências

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ausências | Pessoa | ausencias.colaborador_id | Script/ref.; real V | Equipa semanal | Sim | PATCH | Sem revisão | Sem cancelar na UI | Ação específica | Log, não eventos de negócio | Prevista | Não específico | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | RH-22: identidade mutável/anexo e efeitos cruzados | Correção auditada; cancelar; coordenar ponto | P1 |
| Ausências | Data | ausencias.data | Script/ref.; real V | Equipa semanal | Sim | PATCH | Sem revisão | Sem cancelar na UI | Ação específica | Log, não eventos de negócio | Prevista | Não específico | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | RH-22: identidade mutável/anexo e efeitos cruzados | Correção auditada; cancelar; coordenar ponto | P1 |
| Ausências | Tipo | ausencias.tipo | Script/ref.; real V | Equipa semanal | Sim | PATCH | Sem revisão | Sem cancelar na UI | Ação específica | Log, não eventos de negócio | Prevista | Não específico | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | RH-22: identidade mutável/anexo e efeitos cruzados | Correção auditada; cancelar; coordenar ponto | P1 |
| Ausências | Estado/justificação | ausencias.estado | Script/ref.; real V | Equipa semanal | Sim | PATCH | Sem revisão | Sem cancelar na UI | Ação específica | Log, não eventos de negócio | Prevista | Não específico | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | RH-22: identidade mutável/anexo e efeitos cruzados | Correção auditada; cancelar; coordenar ponto | P1 |
| Ausências | Comentário | ausencias.comentario | Script/ref.; real V | Equipa semanal | Sim | PATCH | Sem revisão | Sem cancelar na UI | Ação específica | Log, não eventos de negócio | Prevista | Não específico | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | RH-22: identidade mutável/anexo e efeitos cruzados | Correção auditada; cancelar; coordenar ponto | P1 |
| Ausências | Comprovativo | ausencias_anexos | Script/ref.; real V | Criar/justificar/download | Upload | Não | Sem fluxo | Sem botão | Documento com relação estável | Sem versão | Anexo log previsto | Não | RH (G/Ger/A); API V | Não UI | CSS adapta; visual V | Falha upload após gravar; anexo segue UUID alterado | Recuperação de falha e identidade | P1 |

### Horas extra

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Horas extra | Pessoa | horas_extraordinarias.colaborador_id | Script/ref.; real V | Criar/listar pendentes | Sim | Não UI | Não UI | Não UI | Correção/decisão própria | Log previsto | Prevista | Indicador por pagar | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | Autorizar não é ação do responsável; sem correção | Workflow controlado e histórico | P1 |
| Horas extra | Obra | horas_extraordinarias.obra_id | Script/ref.; real V | Criar/listar pendentes | Sim | Não UI | Não UI | Não UI | Correção/decisão própria | Log previsto | Prevista | Indicador por pagar | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | Autorizar não é ação do responsável; sem correção | Workflow controlado e histórico | P1 |
| Horas extra | Data | horas_extraordinarias.data | Script/ref.; real V | Criar/listar pendentes | Sim | Não UI | Não UI | Não UI | Correção/decisão própria | Log previsto | Prevista | Indicador por pagar | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | Autorizar não é ação do responsável; sem correção | Workflow controlado e histórico | P1 |
| Horas extra | Horas | horas_extraordinarias.horas | Script/ref.; real V | Criar/listar pendentes | Sim | Não UI | Não UI | Não UI | Correção/decisão própria | Log previsto | Prevista | Indicador por pagar | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | Autorizar não é ação do responsável; sem correção | Workflow controlado e histórico | P1 |
| Horas extra | Motivo | horas_extraordinarias.motivo | Script/ref.; real V | Criar/listar pendentes | Sim | Não UI | Não UI | Não UI | Correção/decisão própria | Log previsto | Prevista | Indicador por pagar | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | Autorizar não é ação do responsável; sem correção | Workflow controlado e histórico | P1 |
| Horas extra | Autorizado por | horas_extraordinarias.autorizado_por | Script/ref.; real V | Criar/listar pendentes | Sim | Não UI | Não UI | Não UI | Correção/decisão própria | Log previsto | Prevista | Indicador por pagar | RH (G/Ger/A); API V | Filtradas | CSS adapta; visual V | Autorizar não é ação do responsável; sem correção | Workflow controlado e histórico | P1 |
| Horas extra | Pagamento/estado | horas_extraordinarias.estado_pagamento | Script/ref.; real V | Só por pagar | Default | Não UI | Não UI | Não UI | Ação específica | Prevista, não comprovada | Log/trigger previstos | Pendentes UI | RH; Financeiro sem vista Equipa | Não UI | CSS adapta; visual V | Sem marcar pago/ver histórico; sem prova de pagamento | Definir poderes e vínculo económico | P1 |

### Viatura × pessoa

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Viatura × pessoa | Responsável atual/sem atribuição | viaturas.colaborador_atribuido_id | Script/ref.; real V | Módulo Viaturas | RPC | RPC | RPC | Desatribuir | Ação específica | Histórico controlado | Sim previsto | Retarget previsto | Gestores autorizados | Resolver nome inativo; novo destino ativo | CSS adapta; visual V | Formulário antigo Equipa faz PATCH | RH-15; reutilizar componente | P1 |
| Viatura × pessoa | Histórico/request/revisão | viaturas_atribuicoes_historico | Script/ref.; real V | Módulo Viaturas | RPC | Não direto | Novo evento | Não apagar | Não direto | Sim | Sim | Resolvidos preservados | Gestores/leitores autorizados | Sim no módulo | CSS adapta; visual V | Sem link/resumo na ficha RH | Resumo com navegação | P3 |
| Viatura × pessoa | Saída com viatura atribuída | Guarda sobre colaboradores | Script/ref.; real V | Erro de bloqueio | Não aplicável | Desatribuir antes | Não aplicável | Saída depois | Ação específica | Preservado | Prevista | Não | RH | Não sair indevidamente | CSS adapta; visual V | Sem encaminhamento claro na ficha | Mostrar viaturas e ação em módulo próprio | P2 |

### Alertas

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Alertas | primeira_consulta_medicina | alertas; rotinas de origem | Script/ref.; real V | Sino/dashboard | Rotina | Não origem por alerta | Resolver não corrige origem | Resolver | Ação de origem | Resolvidos preservados conforme versão | Autor resolução | Sim | Por papel/obra; empresa V | Varia por origem | CSS adapta; visual V | Reconciliação pendente; Medicina preparada | Reconciliar sem apagar/reabrir indevidamente | P1 |
| Alertas | consulta_medicina | alertas; rotinas de origem | Script/ref.; real V | Sino/dashboard | Rotina | Não origem por alerta | Resolver não corrige origem | Resolver | Ação de origem | Resolvidos preservados conforme versão | Autor resolução | Sim | Por papel/obra; empresa V | Varia por origem | CSS adapta; visual V | Reconciliação pendente; Medicina preparada | Reconciliar sem apagar/reabrir indevidamente | P1 |
| Alertas | validade_epi | alertas; rotinas de origem | Script/ref.; real V | Sino/dashboard | Rotina | Não origem por alerta | Resolver não corrige origem | Resolver | Ação de origem | Resolvidos preservados conforme versão | Autor resolução | Sim | Por papel/obra; empresa V | Varia por origem | CSS adapta; visual V | Reconciliação pendente; Medicina preparada | Reconciliar sem apagar/reabrir indevidamente | P1 |
| Alertas | fim_contrato_rh | alertas; rotinas de origem | Script/ref.; real V | Sino/dashboard | Rotina | Não origem por alerta | Resolver não corrige origem | Resolver | Ação de origem | Resolvidos preservados conforme versão | Autor resolução | Sim | Por papel/obra; empresa V | Varia por origem | CSS adapta; visual V | Reconciliação pendente; Medicina preparada | Reconciliar sem apagar/reabrir indevidamente | P1 |
| Alertas | validade_documento | alertas; rotinas de origem | Script/ref.; real V | Sino/dashboard | Rotina | Não origem por alerta | Resolver não corrige origem | Resolver | Ação de origem | Resolvidos preservados conforme versão | Autor resolução | Sim | Por papel/obra; empresa V | Varia por origem | CSS adapta; visual V | Reconciliação pendente; Medicina preparada | Reconciliar sem apagar/reabrir indevidamente | P1 |

### Auditoria

| ÁREA | DADO / AÇÃO | FONTE NA BD | EXISTE NA BD? | APARECE NA UI? | PODE SER CRIADO? | PODE SER EDITADO? | PODE SER CORRIGIDO? | PODE SER ANULADO/ENCERRADO? | DEVERIA SER EDITÁVEL? | HISTÓRICO PRESERVADO? | AUDITORIA? | ALERTA? | PERMISSÕES | FUNCIONA PARA INATIVO? | FUNCIONA MOBILE? | PROBLEMA IDENTIFICADO | CORREÇÃO RECOMENDADA | PRIORIDADE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Auditoria | Antes/depois RH | rh_cadastro_auditoria | Script/ref.; real V | Não | Automático | Não | Não | Não | Não | Sim privado | Sim | Não | RPC futura mínima | Dados existem; UI não | Não UI | Tabela sem consumidor de histórico | Leitura por pessoa/empresa sem fuga NISS | P2 |
| Auditoria | Log geral | log_auditoria | Script/ref.; real V | Definições Gestão | Triggers | Não | Não | Não | Não | Sim se trigger ativo | Autor pode ser NULL legado | Não | Gestão/Gerência conforme helper | Filtro local não resolve histórico antigo | CSS adapta; visual V | Só 200 eventos antes de filtrar | Paginar/filtrar servidor e link da pessoa | P2 |
