# Auditoria independente final — Pacote 1 Quadro controlado

02/10/2026. Exclusivamente local/efémero/offline. Não usei Supabase real, Chrome autenticado, produção ou Cloudflare.

## A. Identificação e decisão

Candidato: `feat/quadro-controlado-20261001`, **d01f60737fdf9aded6a1dbb8d992d6dcbbf0de36**. Base indicada: **9e0e6c40b439160201289823db8cfee0b9adad02**, sem certificação de que continue a ser a produção atual.

Branch independente: `audit/quadro-controlado-pacote1-final-20261002`, criada exatamente no SHA candidato. Worktree: `C:\Users\Cristiana\Documents\plataforma-primeline-quadro-audit-final`. A entrega acrescenta apenas este relatório e três testes. O SHA final da auditoria consta do commit desta branch e da resposta final.

**NO-GO para fechar/publicar o Pacote 1. Três P1 confirmados**, descritos abaixo. O candidato não foi corrigido.

| Decisão local | Resultado | Limite |
| --- | --- | --- |
| S. Backend Fase A isolado | GO local condicionado | Compatibilidade/gate/operações normais passaram; exige precheck/backup reais e aceitação dos P2; não autoriza frontend nem aplicação |
| T. Frontend | NO-GO | P1-02/03 |
| U. Fase B | NO-GO | P1-01 e frontend sem aprovação; não marcar prova privada B |

## B. P0

Nenhum P0 novo confirmado nos cenários executados. Não encontrei bypass autenticado do gate, escrita cross-tenant ou DML direto funcional em B. Não é prova de inexistência universal de vulnerabilidades nem do catálogo real atual.

## C. P1 confirmados

### P1-01 — pós-check B aceita instalação funcionalmente incompleta

**Fonte:** `supabase/quadro_controlado_fase_b_postcheck.sql:14`, `:28`, `:56`.

O check de triggers procura apenas os existentes desativados; não exige o conjunto esperado. As funções são verificadas por owner/SECURITY DEFINER/search_path/ACL, sem exigir o corpo esperado. O final compara identidade armazenada no controlo/marcador, sem recalcular identidade estrutural B atual.

**Reprodução PostgreSQL 17.6, sintética, com rollback:**

1. Instalar A, marcar como owner, backup B, instalar B, executar pós-check.
2. Remover `trg_quadro_pessoal_movimentos` de `public.quadro_pessoal_alocacao`.
3. Pós-check B completo **aprova**.
4. Alocação legítima de Encarregado confirma (`committed=true`), mas existem **zero movimentos históricos para a pessoa**. Revisão/alertas existem.
5. Reverter a unidade; em outra, trocar somente o corpo de `fn_quadro_notificar_controlado_v1(uuid,date,uuid,uuid,uuid)` por `BEGIN RETURN; END`, preservando assinatura/owner/ACL/SD/search_path.
6. Pós-check B **aprova** novamente e operação confirma com **zero alertas**.

Dois testes `FINDING P1` em `audit-quadro-final.test.mjs` reproduzem os casos. O agente que remove objetos é owner local: **não** demonstrei exploit de authenticated. O defeito é a falsa aprovação de drift/DDL parcial pelo pós-check obrigatório.

**Recomendação não implementada:** exigir presença/definição/função/estado de todos os triggers, constraints e funções esperados; identidade B calculada a partir do catálogo atual; testes negativos por objeto ausente/adulterado. Rever também o alias `quadro_controlado_postcheck.sql`.

### P1-02 — célula fica bloqueada depois de erro

**Fonte:** handler `#team-board` em `src/app.js:4007`, `saveWorkforceAllocation()` aproximadamente `:2437`; `.workforce-day-cell.saving` em `src/styles.css:1266`.

Handler acrescenta `saving`; erro apenas mostra mensagem, e finally limpa `workforceSaving`, não a classe. CSS conserva `pointer-events:none`.

**Prova física Playwright desktop:** selecionar íman, clicar célula; preview devolve ABSENCE_CONFLICT; não há confirmação, mensagem correta, mas célula permanece `saving=true` e `pointerEvents=none`. Retirar falha simulada e tentar clicar normalmente dá timeout. Terminar/reabrir edição recupera mediante renderização.

Suite anterior chama `quadroTest.save` diretamente em erros, contornando o handler. Novo teste executa clique real.

**Recomendação não implementada:** limpar estado visual transitório em finally do caminho real, inclusive erro de preview/confirm/rede/retorno antecipado; manter bloqueio de duplo envio e ausência de retry automático; testar nova tentativa por clique.

### P1-03 — tablet/mobile enviam dia diferente do alvo visual

**Fonte:** `src/styles.css:1234`, `:1248–1253`, painéis overflow oculto em `:953`/`:1586`. Quatro semanas comprimidas; conteúdos internos conservam 27px; grelha semanal configura cinco colunas para sete dias renderizados.

**Prova:** scrollIntoViewIfNeeded, boundingBox, elementFromPoint no centro do alvo, mouse.click nesse centro; sem force-click e sem invocar save por hook.

| Viewport | Alvo w2 | Largura | Hit-test / data enviada na confirmação simulada |
| --- | --- | --- | --- |
| 1440×1000 desktop | 05/10/2026 | 33,1px | 05/10/2026 |
| 820×1180 tablet | 05/10/2026 | 11,7px | **06/10/2026** |
| 390×844 mobile | 05/10/2026 | 7,3px | **07/10/2026** |

Screenshots inspecionados confirmam sobreposição. CSS herdado da base, não alteração nova atribuída ao candidato; ainda impede o requisito funcional deste frontend. Backend valida a data recebida, não a intenção visual.

**Recomendação não implementada:** largura mínima legível por dia com scroll horizontal efetivo ou vista própria por dia/semana; impedir conteúdo de intercetar vizinho; alinhar sete colunas; repetir mouse/touch. Não aprovar usando force-click.

## D. P2/P3

| ID | Evidência e limite | Seguimento |
| --- | --- | --- |
| P2-01 | Replay próprio devolve receipt após perda de papel/âmbito; autor ativo/mesma empresa/token/payload originais; sem nova escrita nem cross-author | Decidir política de receipts versus revogação |
| P2-02 | Remover alocação preserva alertas antigos com entidade_id já sem linha; histórico preservado | Definir navegação/resolução explícita |
| P2-03 | Ausência posterior pode coexistir com alocação; duas ligações, FKs/constraints/triggers capturados: ausência espera lock FK e confirma após alocação | Invariável inversa no escritor de ausências, evolução separada |
| P2-04 | Transação explícita com duas chamadas RH x Quadro produz 40P01: RH segura empresa/pessoa; Quadro segura global e espera pessoa; segundo RH cria/aloca e espera global | Não demonstrado no fluxo atual de uma RPC por transação; uniformizar locks antes de generalizar batches/Pacote 2 |
| P2-05 | rollback A→forward-fix A: B recusa backup de instalação anterior; repetir backup B dá 42P07 por nomes fixos | A recupera e dados ficam intactos. Retorno B requer rotação/arquivo autorizado; **FAIL do requisito sem edição manual**, seguro por recusa |
| P2-06 | Criação de colaborador RH não ganhou idempotência geral; perda de resposta não admite retry cego | Preservação do contrato; desenho separado |
| P2-07 | Backend aceita obra encerrada, opções UI filtradas; proibição nova não especificada | Confirmar regra antes de impô-la |
| P2-08 | Rollback A restaura notifier antigo e risco antigo de 23505 | Limite explícito de baseline; forward-fix reinstala correção |
| P2-09 | Lock global serializa inclusive pessoas diferentes; carga/starvation não certificadas | Medir e rever dimensão antes de ampliar |
| P2-10 | Teste Agenda exige styles v98/app v145; base já tem styles v104/app posterior | Falha preexistente, não prova regressão Agenda; não alterado |
| P3-01 | Definições completas duplicadas A/forward-fix e B/forward-fix | Verificação automatizada de equivalência futura |

## E. Achados históricos

| Achado | PASS/FAIL atual | Evidência |
| --- | --- | --- |
| DELETE→POST não atómico | PASS controlado | Falha após DELETE de merge reverte alocações/histórico/revisão/alertas/auditoria/ledger |
| Temporalidade divergente novo Quadro | PASS | Data explícita, nenhum dia seguinte criado |
| Gerência com poder indevido | PASS | API nova e DML legado A recusados; RH legítimo preservado |
| Revisão perdida no vazio | PASS | Última manhã/tarde/inteiro removida, reload/replay/duas sessões conservam revisão |
| Notificações ausentes | PASS normal; FAIL pós-check | Recipients/chaves passam; P1-01 aceita notifier/histórico ausente |
| Backup incompleto | PASS local para objetos inventariados | Metadata/fotografia/controlo; catálogo real ainda pendente |
| Postcheck incompleto | **FAIL P1-01** | Deteta grants/helper/policy, não trigger removido/corpo no-op |
| Rollout incompatível | PASS segurança normal; FAIL UX | Matriz abaixo, sem fallback DML novo; P1-02/03 |
| Ponto sem cobertura explícita | **FAIL cobertura, intencional** | Consumidores antigos iguais ao backup e herança preservada |
| GUC gate inseguro | PASS | GUC/payload não substituem prova owner privada |
| Colisão 23505 | PASS local | Índice real, recipients múltiplos, replay/split/merge/rollback/concurrency |

## F. Alertas

Repeti suites existentes e acrescentei cálculo independente JS/crypto da chave, sem usar algoritmo SQL para obter esperado. Array canónico: namespace `quadro_movimento_alerta_v1`, empresa, identidade estável da operação request_id, pessoa, data, origem, destino, destinatário. Não depende de UUID recém-gerado de alocação nem timestamp; request_id identifica a operação e não é regenerado no replay/notifier.

- Savepoint/rollback e repetir mesma operação: IDs de alocação diferentes, mesmas chaves.
- Recipients distintos: chaves distintas, conferidas individualmente pelo cálculo independente.
- Eventos sucessivos: chaves distintas; empresa/obra integram a identidade. Não alego ausência matemática absoluta de colisão de hash.
- Preview/replay/rollback sem alerta extra persistido.
- Dois Administrativos, Diretor, vários Diretores/Encarregado origem, recipients ativos com login da empresa e autor excluído: PG A/B passou.
- Adicionar/mover/split/merge: avisos corretos; remover preserva anteriores; rename/escritório mantêm condições atuais, sem inventar domínio novo.
- RPC legada A: vários recipients e eventos sucessivos sem 23505.
- `alertas_ocorrencia_unica_idx`: definição igual à fixture real capturada antes/depois A/B; default ocorrencia_chave NULL preservado; nenhum índice global alterado.
- Medicina/Viaturas: suites próprias e browsers repetidos. Agenda/documentos/reuniões: 22 passes e falha preexistente de versões hardcoded.

## G. Rollout/cache

| Combinação | Prova local | Resultado |
| --- | --- | --- |
| Antigo+antigo | Funções capturadas e DML legítimo PG | Funcional baseline |
| Antigo+A | INSERT/PATCH/DELETE/RPC antiga/revisão/alertas | Compatibilidade preservada |
| Novo+A | v1/context/preview/confirm e browser offline | Backend funcional; ressalvas UX |
| Novo+B | Hardening/RH/roles/v1/context | Backend funcional; ressalvas P1 |
| Antigo+B | DML/RPC recusados PG e app base servido offline | Bloqueio seguro, sem corrupção |

Aba/cache antigo: servidor serve app da base em memória, sem editar ficheiro; tentativa legada recusada e snapshot simulado intacto. DML antigo já enviado/bloqueado durante DDL B é recusado depois do COMMIT. Preview v1 em A confirma em B quando pedido/revisão continuam válidos.

Novo frontend com contexto RPC ausente: edição fechada, sem DML fallback. Resposta inválida/committed false/rede perdida e STALE exercitados; sem retry automático com nova revisão. Perda de resposta não implica rollback servidor; reload consulta estado.

Cache-busting app v172 e cliente workforce-allocation v1 revistos. Falta de assets/módulos não autoriza B. Propagação real/CDN/abas reais e todas as combinações de frontend parcialmente propagado: **VALIDAÇÃO REAL PENDENTE**; ausência de backend/app antigo offline não certifica cada combinação de assets.

## H. Gate privado

primeline_quadro_rollout: owner/RLS/ACL privados; PUBLIC sem EXECUTE/helpers/privilégios concedidos. anon/authenticated/service_role testados por SELECT/INSERT/UPDATE/DELETE/helpers/script de marcação, recusados. Bypass RLS não substitui grants.

GUC/payload falso, marker ausente, contract/release/instalação/data/identidade inválidos, grant A/helper privado divergente: B recusa. Owner marca corretamente; consumo transacional, falha posterior reverte. Repetição sem nova validação, reutilização pós-rollback e substituição na mesma tentativa recusadas. P1-01 não é bypass do gate A: é falsa certificação da instalação atual B.

## I. SECURITY DEFINER / tenant

Owner postgres, search_path `public, pg_temp`, tabelas sensíveis qualificadas, grants/ausência de CREATE public para aplicação revistos/testados. Núcleo aplicar/renomear/criar não exposto como RPC normal; endpoints/leitura necessários apenas.

Passaram pessoa/obra de outro tenant, perfil inativo, Encarregado sem responsabilidade/retirando origem alheia, UUID inexistente, spoof de request/payload e outro autor/empresa; inputs incompletos/NULL não deixam escrita parcial. Helpers privados/service_role não ganharam acesso novo.

Limite: catálogo capturado e helpers periféricos declaradamente stubados; não é restauro integral de BD nem teste Supabase/PostgREST/extensions atuais. RLS/catálogo atual: pendentes.

## J. Escritores — nova varredura

DML nominal e EXECUTE/format/regclass revistos; regex de writer não usada como prova universal.

| Destino/caminho | A | B |
| --- | --- | --- |
| Frontend atual workforce-allocation.js | Só v1 | Igual, sem DML direto |
| Frontend antigo | DML/RPC legítimos sob guards legados | Grants/execute revogados/recusa |
| fn_quadro_aplicar_interno | DML alocação, permit, revisão | Núcleo controlado único para novo Quadro/RH |
| fn_quadro_operar antigo | Escritor legado direto ainda legítimo, locks/permit/revisão | Corpo de recusa |
| Dois overloads fn_criar_colaborador_com_alocacao | Construtor privado→mesmo núcleo | Legítimos após fechar DML |
| fn_rh_guardar/fn_rh_importar→fn_rh_guardar_interno | Criação via wrappers/núcleo; updates/import preservados | Igual |
| fn_registar_movimento_quadro | Movimento e revisão de DML legado | Histórico do núcleo, revisão controlada uma vez |
| fn_quadro_operar_v1/renomeação | Ledger quadro_operacoes e núcleo | Igual |
| Inicialização A/forward-fix A | Seed/bump revisões, não alocações novas | Não writer operacional B |
| quadro_escrita_interna/quadro_pessoal_rpc_permit | Permits transacionais novo/legado | Núcleo; GUC não falsifica permit |
| primeline_quadro_rollout controlo/validacoes | Owner instalação/prova/invalidação | Owner consumo/rollback, aplicação sem acesso |
| Notifiers/auditoria | Alertas/log na transação | Preservados, índice global intacto |

Históricos a não reaplicar: `colaboradores_crud_alocacao_inicial.sql`, `colaboradores_campos_completos.sql` redefinem criação antiga com INSERT; `quadro_pessoal_alocacao_diaria.sql` é backfill. Monolíticos descontinuados falham explicitamente. Dinâmico de backup/rollback/grants é DDL/metadados, não segundo frontend writer.

Helper indireto `fn_mgo_inserir_json_compativel(regclass,jsonb)` de `supabase/mapa_gestao_obras.sql`: INSERT dinâmico genérico; captura ACL privada postgres, sem execute aplicação; callers encontrados usam tabelas constantes de Mapa, não Quadro. Guard B exige permit para alocação. Regex nominal não o descobre. ACL/callers realmente instalados devem ser reconfirmados.

Revisões/operações/permits privadas, histórico protegido. Captura anterior não prova ausência de writers reais posteriores: **VALIDAÇÃO REAL PENDENTE**.

## K/M. Temporalidade, períodos, permissões, Ponto

Novo Quadro só data explícita; criar em 05/10 e consultar 06–14/10 não gera continuidade. Responsabilidade por obra não vira presença. Não criou cobertura 03–14/10 nem alterou estados/horas/justificações do Ponto.

**DÍVIDA TRANSITÓRIA INTENCIONAL — REMOVER NO PACOTE 2:** Ponto ainda herda temporalidade; listar/guardar Ponto iguais ao backup, não redefinidos. PASS preservação, não aprovação de temporalidade corrigida Ponto.

PG A/B: dia inteiro→manhã/tarde→inteiro, manhã/manhã, tarde/tarde, metades em obras distintas, obra+escritório/garantia/pontual e permite_multiplas_obras false/true. Flag não autoriza simultaneidade; split/substituição controlados. Conflitos legados mantidos e recusados, sem limpeza silenciosa.

| Perfil | Regra confirmada |
| --- | --- |
| Administrativo | Gestão própria empresa |
| Gestão | Global da empresa, autor/origem auditados, sem cross-tenant |
| Gerência | Consulta/RH legítimos; sem nova movimentação global; UI sem editar |
| Diretor/Adjunto | Leitura autorizada, sem mover; UI sem editar |
| Preparador | Sem novos poderes Quadro |
| Encarregado | Origem/destino no âmbito; escritório/rename global recusados |
| Inativo/outra empresa | Recusado |

UI por runtime offline/código; backend por roles/auth sintéticos PG. Não houve login real.

## L. Revisão/idempotência/RH

Estado normal/vazio, retirar última manhã/tarde/inteiro, reload, A→B→A, duas abas/sessões: revisão separada da última alocação. Request simultâneo igual confirma uma vez; payload diferente IDEMPOTENCY_CONFLICT; outro autor/tenant recusado; replay não duplica histórico/alerta/revisão. Escrita antiga A invalida preview novo.

Erro depois de DELETE de merge reverte snapshot completo. RH A/B cria com obra/escritório/sem alocação/data histórica; origem cadastro_rh/autor/contrato/data explícita. Falha após INSERT pessoa ou contrato reverte integralmente. Ausência/conflito/empresa divergente não deixa pessoa parcial.

Importação atual trata IDs existentes, não criação genérica de pessoas novas. Testes com/sem informação de alocação preservam alocações; erro na segunda linha reverte primeira. Não inventei funcionalidade de importação não oferecida pelo contrato. Depois de B cadastro permanece atómico pelo mesmo núcleo.

## J2. Locks e concorrência PG real local

PostgreSQL **17.6**, duas ligações app independentes + inspeção owner. Testes novos incluem constraints/FKs capturados e triggers de ausência normalização/auditoria; clusters 127.0.0.1 parados no finally.

| Schedule | Resultado/tempo |
| --- | --- |
| Pessoas diferentes A/B | Serialização global, 79–97ms incluindo pausa deliberada 60ms |
| Mesma pessoa/revisão | Uma confirma, outra STALE, 63–74ms |
| RPC antiga x nova A | Espera e preview antigo recusado, ~63ms |
| Cadastro novo RH x Quadro outra pessoa | Espera, completa atomicamente, 102–110ms |
| Renomear x mover | Segunda detecta revisão, 64–67ms |
| Ausência primeiro | FK lock e depois ABSENCE_CONFLICT |
| Alocação primeiro | Ausência posterior confirma, P2-03 |
| lock_timeout 100ms | 55P03 em 102–104ms; rollback liberta e próxima operação funciona |
| DML legado durante B | Revalidação após DDL: recusa, zero linha |
| B sob app em transação | timeout 250ms, 57014 em 262ms; rollback conserva A/prova não consumida; retry após libertação instala |
| RH multi-op explícito x Quadro | 40P01 reproduzido, P2-04, vítima revertida |

Núcleo lock tabela/global→pessoa→dia; RH existente usa empresa/pessoa antes de outras operações. Ensaios finitos não provam ausência universal de deadlock/starvation nem carga real.

## N/O. Backup/precheck/postcheck/rollback/forward-fix

Revistos/executados scripts integrais precheck, backup A, A/postcheck/rollback/forward-fix, marcador privado, B precheck/backup/migration/postcheck/rollback/forward-fix e aliases.

Backup cobre fotografia e objetos alterados inventariados: fontes/owner/ACL/search_path, policies/grants tabela/coluna, triggers/constraints/sequências; B inclui controlo privado/estrutura A relevante. Tabelas novas preservadas não são restauradas a zero. Alertas/auditoria operacionais não são apagados por restauro de foto.

Backup duas vezes recusa sem sobrescrever; instalação sem backup recusa. Grant/helper/policy permissiva detetados. **Pós-check B FAIL P1-01.** Fotografia local 227 alocações/98 movimentos/conflitos preservados: números sintéticos, não contagens reais.

Repetidos com operações: A→rollback A, A+cliente→rollback A, A→B→rollback B, rollback B→nova prova→forward-fix B e rollback A→forward-fix A. Dados/histórico/revisões/alertas preservados; grants previstos; Arollback fecha v1/restaura baseline; FFA invalida previews; Brollback invalida prova/aumenta tentativa; FFB requer nova prova.

**FAIL recuperação totalmente automática:** rollback A/FFA recupera A, mas Bbackup antigo pertence a instalação diferente e backup novo por mesmo nome recusa. P2-05; não apaguei/renomeei backups para contornar proteção.

## P/R. Regressões e contagens desta execução

| Execução | Total Node | Pass | Fail | Skip |
| --- | ---: | ---: | ---: | ---: |
| 36 suites existentes Quadro/RH/Ponto-Férias/Medicina/Viaturas/Planeamento/wrapper/acesso | 348 | 347 | 0 | 1 |
| Novo audit-quadro-final.test.mjs, PG | 45 | 45 | 0 | 0 |
| Novo audit-quadro-final-concurrency.test.mjs, PG | 19 | 19 | 0 | 0 |
| Alertas/Agenda/documentos/reuniões adicionais | 23 | 22 | 1 | 0 |
| Horas Extra legado, overtime-workflow (regressão estática adicional) | 1 | 1 | 0 | 0 |
| **Total reportado Node** | **436** | **434** | **1** | **1** |

Inclui testes-pai dos grupos PG. Skip: Excel externo opcional RH_XLSX, **não aprovado**. Falha Agenda preexistente de versões, não ocultada. Novos testes `FINDING` passam quando reproduzem defeito: **PASS de caracterização não equivale a produto aprovado**.

Separação: PG17.6 real Quadro/gate/RH/RLS/concorrência/alertas e suites próprias Medicina/atribuição Viaturas; PGlite nas suites que usam esse runtime RH/validades/Planeamento; static/mocks de clientes/acesso/wrapper/documentos não são BD real.

8 browsers originais offline repetidos com sucesso: workforce-controlled-browser, rh-frontend-browser, medicine-browser, planning-browser, planning-selection-browser, vehicle-assignment-browser, vehicle-validity-browser, rh-cadastro-browser. 1 browser independente terminou como caracterização, confirmando P1 e não certificando UX.

Medicina ORIGINAL do candidato passou sem editar. Diff à base: apenas stub adicional de contexto Quadro, sem remoção de asserts Medicina. Não alego byte-identidade com fixture antiga. RH Windows usou bootstrap temporário externo sem editar teste original.

Logs `%TEMP%`: quadro-final-regression.log, quadro-final-independent.log, quadro-final-independent-concurrency.log, quadro-final-alerts-regression.log, quadro-final-browser-independent.log, quadro-final-added-final.log (repetição final dos 64 adicionais), quadro-final-overtime-regression.log e logs dos oito browsers. Sem dados reais, não versionados.

## Q. UX

Desktop real offline: íman, período, alocar/mover/retirar, duplo clique em operação pendente, terminar/cancelar, conflito, ausência, STALE com reload contexto sem retry, rede perdida/reload. Split/merge completo validado em PG; mock browser não emula integralmente SQL.

Tablet/mobile: hit-test/clique envia dia errado; restantes fluxos **não aprovados** nesses viewports. Forçar clique esconderia defeito. Touch físico pendente depois de corrigir; geometria já bloqueia operação segura de Encarregado.

Screenshots inspecionados em `%TEMP%\primeline-quadro-final-audit-browser\audit-final-desktop.png`, `audit-final-tablet.png`, `audit-final-mobile.png`. Toda rede não-local intercetada; nenhum perfil pessoal.

## V. VALIDAÇÃO REAL PENDENTE

1. Corrigir/retestar P1-01/02/03 em novo candidato separado; esta auditoria não corrige.
2. Confirmar base/main/candidato atuais antes de aplicação.
3. Catálogo real completo: writers/dinâmicos/callers, triggers/ordem, índice/defaults, owner/ACL/RLS/schema/coluna/sequência; não reutilizar captura como prova atual.
4. Foto/precheck real alocações/movimentos/conflitos/ausências/responsáveis/RH/Ponto, sem PII em Git.
5. Backup privado + exportação externa verificável; rotação/nomes existentes e recuperação futura B.
6. Autorização separada para A e pre/postcheck real, sem backfill automático.
7. UI autenticada por perfil em desktop/tablet/mobile corrigidos, alertas/histórico/autor/data/ausências/Ponto.
8. Propagação/cache/CDN/abas antigas/ficheiros parciais reais; prova privada B só owner após validação verdadeira.
9. Contenção/carga/concorrência com escritores reais, sem prometer fairness.
10. B separadamente autorizada, pós-check corrigido, RH/importação e antigo bloqueado.
11. RH_XLSX específico se necessário; skip não cobre.
12. Decidir P2 e Pacote 2: herança Ponto, ausência inversa, receipts, locks/recuperação; não redesenhados aqui.

## Reexecução adicional

```powershell
$env:QUADRO_PG_BIN="$env:TEMP\primeline-viaturas-test\node_modules\@embedded-postgres\windows-x64\native\bin"
$env:QUADRO_TEST_DEPS="$env:TEMP\primeline-viaturas-test\node_modules"
& 'C:\Program Files\nodejs\node.exe' --test tests/audit-quadro-final.test.mjs tests/audit-quadro-final-concurrency.test.mjs
$env:PLANNING_PLAYWRIGHT='C:\Users\Cristiana\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules\playwright'
$env:RH_SCREENSHOTS=Join-Path $env:TEMP 'primeline-quadro-final-audit-browser'
& 'C:\Program Files\nodejs\node.exe' tests/audit-quadro-final-browser.mjs
git diff --check
```

Runtimes preexistentes externos. Sem configuração PG os grupos reportam skip, não aprovação. Nenhum SQL real executado. Commit/push apenas relatório e três testes na branch independente; candidato/main intactos. SHA remoto/limpeza/diff-check final confirmados na resposta. Nenhuma ação desta tarefa ficou à espera de permissão.