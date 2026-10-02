# Correção dos três P1 — Pacote 1 Quadro

02/10/2026. Branch `feat/quadro-controlado-20261001`. Base da correção: `d01f60737fdf9aded6a1dbb8d992d6dcbbf0de36`. Auditoria de origem: `47fcda710e5a6d48d8853be924632f84c9797114`, branch `audit/quadro-controlado-pacote1-final-20261002`.

## Resultado

**GO LOCAL para nova auditoria independente.** Três P1 corrigidos e testados. Nenhum P0/P1 adicional confirmado nos ensaios locais. Não equivale a autorização para A/B real ou publicação. P2/P3 anteriores permanecem documentados abaixo.

Nenhuma chamada ao Supabase real, Chrome pessoal, produção/Cloudflare, execução SQL real, alteração de dados reais, merge ou deploy. Commit/push apenas deste candidato. O SHA final consta do commit que contém o relatório e da resposta de entrega.

## P1-01 — pós-check B

`quadro_controlado_fase_b_postcheck.sql` agora compara o catálogo ATUAL com a estrutura A validada e somente as diferenças B previstas. `quadro_controlado_postcheck.sql` é byte-equivalente ao pós-check B.

### Referência e identidade

- `quadro_controlado_fase_b_backup.sql` exige a prova privada de A antes de copiar o catálogo para `primeline_backup.quadro_fase_b_estrutura_20261001`.
- Referência criada antes de B, owner postgres e sem grants para aplicação; não contém dados de colaboradores/alocações, apenas metadados/definições.
- A referência nunca é reconstruída do estado B que se pretende validar. Novos backups não sobrescrevem cópias anteriores.
- B/forward-fix B recusam executar sem essa referência. Mantêm os guards, políticas e operações anteriores.
- Esperado B: alterar apenas os dois corpos que B efetivamente substitui (guard e RPC antiga), ACL da RPC antiga/leitor, ACL/colunas das duas tabelas finais e as duas policies B.
- Os dois hashes de definição B são referências fixas obtidas da definição aprovada em PostgreSQL 17.6: guard `f7fbf510c09f43ce052e4500d02d067b`; RPC antiga `182ccfb29a42f69b7b2523d0a704610b`.
- Demais funções críticas devem conservar a definição integral da A validada, não apenas assinatura/owner/search_path.
- Catálogo atual recalculado em cada execução; comparação integral JSON e hash MD5 diagnóstico (`POSTCHECK_B_IDENTIDADE_ATUAL`). O hash não substitui a comparação nem a autorização owner e não é apresentado como assinatura criptográfica.
- Nomes normalizados em vez de OIDs de roles/tipos; CR removido na comparação das definições; search_path canónico explicitamente aplicado em backup e no bloco de verificação.
- Trata-se de check da instalação/release. Nova alteração legítima de funções/objetos referenciados exige revisão; não “refrescar” referência a partir de um B com drift para obter aprovação.

### Objetos verificados

Funções public fn_quadro_*, fn_rh_*, overloads de criação, movimentos, consumidores Ponto/permissões, funções ligadas aos triggers; funções com referência de alocação, SQL dinâmico EXECUTE ou parâmetro regclass; todos os helpers de primeline_quadro_rollout. Definição/corpo, owner, SD, config/search_path e ACL normalizada são comparados. Assim, novo helper dinâmico também altera a identidade mesmo quando não contém DML nominal de Quadro.

Oito tabelas: alocações, movimentos, permit legado, revisões, operações, permit interno, controlo e validações privadas. Owner, RLS/force-RLS, ACL, colunas/tipos/defaults/NOT NULL/grants, constraints/validação e índices entram no catálogo. Inclui o índice global de alertas como objeto preservado, sem o alterar. Policies e schema privado entram na identidade; referência de backup exige owner/ACL privados.

Sete triggers explicitamente obrigatórios em public.quadro_pessoal_alocacao:

1. trg_00_quadro_lock_escrita_v1;
2. trg_00_quadro_proteger_escrita;
3. trg_auditoria_quadro_pessoal_alocacao;
4. trg_bloquear_quadro_pessoal_ausencia;
5. trg_quadro_notificar_movimentacao_encarregado;
6. trg_quadro_pessoal_movimentos;
7. trg_validar_conflito_quadro_pessoal.

Cada um: existência, enabled O, tabela, definição completa (timing, eventos, row/statement, UPDATE OF, argumentos e função). O conjunto de triggers também é comparado ao backup: extras/ausentes/binding alterado são drift. Triggers de movimentos capturados entram igualmente na identidade.

### Negativas PostgreSQL 17.6

`tests/workforce-controlled.test.mjs`: instalação íntegra PASS e alias igual; remoção de histórico ou qualquer dos outros seis triggers FAIL; disabled FAIL; timing/eventos/função chamada alterados FAIL; notifier no-op FAIL; corpo de histórico/guard/v1/contexto/núcleo/helper privado mantendo assinatura FAIL; ACL/policy/role inesperada FAIL; grant na referência FAIL; constraint/coluna privada alterada FAIL; helper ausente FAIL; novo SECURITY DEFINER dinâmico FAIL.

Cada alteração é sintética dentro de transação revertida. Depois da reversão o pós-check íntegro volta a passar. Os novos testes incluem 26 cenários negativos e uma verificação positiva/alias; a suite completa tem 130 resultados Node com os grupos-pai incluídos.

## P1-02 — estado visual em finally

Handler real de clique em #team-board:

- retorna sem marcar outra célula quando workforceSaving já está ativo;
- acrescenta saving apenas ao iniciar a tentativa;
- try/finally envolve a chamada e a preparação do destino;
- finally remove saving mesmo se a chamada falhar ou retornar cedo;
- mantém a flag lógica/cliente existentes e não acrescenta retry automático.

`tests/workforce-p1-browser.mjs` opera por mouse/tap no handler, sem hook de save. Em cada viewport testa preview/confirm recusados, ABSENCE_CONFLICT, LEGACY_CONFLICT, permissão, STALE com reload de contexto, rede em preview/confirm, resposta inválida em ambos e exceção inesperada. Estado anterior permanece intacto; classe removida/pointer-events restaurado; segundo clique manual confirma normalmente. Duplo clique e clique noutra célula durante operação ativa produzem uma confirmação e nenhuma célula fica bloqueada.

Também simula resposta perdida depois de confirmação no servidor fictício: UI não assume sucesso, não repete RPC e classe é removida. Reload é consulta/recuperação; não se presume rollback servidor. Backend/mocks são separados: o mock do browser não pretende emular toda a persistência SQL entre reloads.

## P1-03 — geometria e scroll

Somente estilos de #team-board em workforce-calendar.css:

- largura mínima da grelha 1600px, primeira coluna 240px e cada semana pelo menos 340px;
- sete colunas reais por semana e labels;
- dias com pelo menos 48px, sem conteúdo a extravasar para vizinho;
- overflow-x:auto real no board, dentro do painel atual;
- alinhamento das labels sem margens laterais que deslocavam os centros;
- nenhum z-index/pointer-events que encaminhe o clique a outro dia.

Cache-busting mínimo: workforce-calendar v7→v8 e app v172→v173. Styles global, regras de tarefas/Ponto/períodos/alocação e módulos alheios inalterados.

### Evidência física offline

| Viewport | Board visível | ScrollWidth | Largura mínima medida | Mouse + tap | Datas enviadas |
| --- | ---: | ---: | ---: | --- | --- |
| 1440×1000 | 1071px | 1600px | 48,42px | PASS | Exatamente as clicadas |
| 820×1180 | 451px | 1600px | 48,42px | PASS | Exatamente as clicadas |
| 390×844 | 329px | 1600px | 48,42px | PASS | Exatamente as clicadas |

Nove dias por viewport: primeiro/meio/último em três semanas (21/24/27 setembro, 05/08/11 outubro, 12/15/18 outubro). Cada alvo: boundingBox, elementFromPoint, label visível do dia, sete colunas e data no payload; sem force-click. Inclui wheel horizontal, íman, período manhã, mover, retirar, conflito/mensagem, erro+retry, terminar/cancelar e reload. Split/merge integral é comprovado separadamente em PostgreSQL; o browser verifica a intenção/payload de período sem duplicar o motor SQL.

Screenshots inspecionados e regeneráveis: `%TEMP%\primeline-quadro-p1-browser\quadro-p1-desktop.png`, `quadro-p1-tablet.png`, `quadro-p1-mobile.png`.

Limites UX: no scroll, a coluna de obra sai do ecrã como numa tabela não congelada; é preciso consultá-la antes/deslizar de volta. Cabeçalho geral mobile continua compacto, herdado. Não há certificação de dispositivo físico/Chrome autenticado. Não alterei o layout geral nem acrescentei uma vista nova fora destes P1.

## Testes e regressões finais

| Execução final | Total Node | Pass | Fail | Skip |
| --- | ---: | ---: | ---: | ---: |
| Quadro/RH/Medicina/Viaturas/Planeamento/Ponto-Férias/wrapper/acesso, incluindo as duas pré-varreduras novas | 439 | 438 | 0 | 1 |
| Alertas/Agenda/documentos/reuniões/Horas Extra legado | 24 | 23 | 1 | 0 |
| Total, sem duplicar reruns | **463** | **461** | **1** | **1** |

Contagens incluem grupos-pai Node. Skip: Excel externo RH_XLSX opcional, não aprovado. Falha Agenda: assertions antigas styles v98/app v145; já falhava na base, não é regressão e não foi corrigida/relaxada.

9 browsers offline concluídos: novo workforce-p1-browser mais os oito originais workforce-controlled, rh-frontend, medicine, planning, planning-selection, vehicle-assignment, vehicle-validity e rh-cadastro. **Medicina original passou sem editar.** RH original usou bootstrap Windows temporário e dependências existentes, sem alterar teste/produção.

PG 17.6 real local: operações A/B, alertas, gate/roles/RLS/tenant, idempotência e concorrência; testes novos reconstituem constraints/FKs e triggers capturados. Suites próprias Medicina/Viaturas igualmente locais. PGlite/clientes/static e browser API simulada são identificados como tal, não como BD real.

Logs `%TEMP%`: quadro-p1-all-final.log, quadro-p1-structure-final.log, quadro-p1-prevarredura.log, quadro-p1-browser-final.log, quadro-p1-alerts-regression.log e oito logs de browsers. Não versionados, sem dados reais.

## Pré-varredura adversarial completa

Não parei nos primeiros achados. `workforce-p1-audit.test.mjs` e `workforce-p1-concurrency.test.mjs` retomam os ataques independentes contra os ficheiros corrigidos. 45+19 resultados, novamente sem skips/falhas, incluídos no total acima.

- Postchecks/triggers/notifier: os dois falsos positivos originais agora são recusados; negativos extras e identidade íntegra passam.
- Segurança/gate: PUBLIC/anon/authenticated/service_role sem acesso privado; GUC/payload/marker inválidos não autorizam B; owner/ACL/SD/search_path/tenant/autor/replay revistos.
- Writers: novo frontend somente RPC; DML/API antiga compatíveis A e fechados B; RH pelo núcleo comum; SQL histórico não reaplicado. Nova referência estrutural é apenas writer owner de metadados de backup, não writer de alocação.
- Rollout: antigo+antigo/A funcional, novo+A/B funcional no contrato; antigo+B fechado; pedido antigo em espera durante B recusado; preview A confirma em B quando ainda válido.
- Revisões/vazio/idempotência: preservadas, concorrentes detetados, sem alerta/histórico extra no replay.
- Locks: pessoas diferentes serializam; mesma revisão uma confirma/segunda STALE; legado x novo, RH x movimento e rename x move mantêm controlo; timeout/rollback libertam locks; rollout timeout deixa A/prova intactos.
- RH/importação: com/sem alocação/data histórica/escritório/obra, tenant/ausência/conflito, falha após pessoa/contrato e erro no meio de lote atómicos. Importação atual trata IDs existentes; não inventei criação por importação.
- Backup/rollback/forward-fix: dados/histórico/revisões/alertas conservados; novo objeto de referência privado preservado; repetição backup recusa; P2 de rotação continua.
- Ponto: definições legadas iguais, nenhuma cobertura 03–14/10/backfill; **DÍVIDA TRANSITÓRIA INTENCIONAL — REMOVER NO PACOTE 2**.
- Tablet/mobile: alvo físico coincide com dia/payload, erros recuperam e operação ativa não duplica. Nova validação não usa hooks de save.

**Novos P0/P1 encontrados: nenhum confirmado nos ensaios locais.** Não alego prova formal de todos os schedules, catálogo real atual ou propagação em produção.

## P2/P3 preservados

1. Replay próprio após perda de papel/âmbito devolve receipt original (sem nova escrita/cross-tenant); política por decidir.
2. Alertas antigos preservados após remover a alocação, navegação/resolução por definir.
3. Ausência posterior pode coexistir com alocação; duas ordens concorrentes testadas. Invariável inversa fora deste pacote.
4. Transação explícita multi-op RH x Quadro pode formar deadlock 40P01; uma chamada normal RH por transação passa. Padronizar ordem antes de novos batches.
5. Rollback A→forward-fix A preserva dados, mas retorno B requer rotação autorizada de backups com nomes fixos. Requisito recuperação totalmente automática continua não satisfeito.
6. RH novo sem idempotência geral; sem retry cego após resposta perdida.
7. Regra de obra encerrada a confirmar; nenhuma regra nova imposta.
8. Rollback A restaura notifier baseline e pode restaurar risco 23505 antigo; forward-fix reinstala correção.
9. Lock global/contensão/starvation sob carga real não certificadas.
10. Falha preexistente Agenda; fixture Excel externo pendente.
11. P3: manutenção de definições completas duplicadas e evolução UX fora dos três P1.

## Validação real pendente / próximos gates

Nova auditoria independente do SHA entregue; catálogo/ACL/triggers/writers/defaults/índice reais; prechecks/fotografia e backup privado/exportação; estratégia de rotação; autorização separada para aplicar A/B; frontend autenticado por perfil em dispositivo real; propagação/cache/abas antigas; recipients/visibilidade dos alertas; carga/locks e recuperação operacional.

A nova referência B é obtida somente pelo backup B correto em A validada. Se já existirem backups anteriores sem esta estrutura, **parar e planear arquivo/rotação autorizados**; não apagar backups nem fabricar referência de B. Esta tarefa não aplicou qualquer SQL real.

## Ficheiros desta correção

- src/app.js — finally e bloqueio de clique durante gravação;
- src/workforce-calendar.css — grelha/scroll/targets somente Quadro;
- index.html — duas versões;
- supabase/quadro_controlado_fase_b_backup.sql — referência privada de catálogo A;
- supabase/quadro_controlado_fase_b.sql e fase_b_forward_fix.sql — precondição referência;
- supabase/quadro_controlado_fase_b_postcheck.sql e quadro_controlado_postcheck.sql — pós-check estrutural/alias;
- tests/workforce-controlled.test.mjs — negativos de drift;
- tests/workforce-p1-audit.test.mjs, workforce-p1-concurrency.test.mjs, workforce-p1-browser.mjs;
- docs/quadro-controlado-pacote1-20261001.md e este relatório.

Sem alteração de regras de alocação, funções A/forward-fix A, Ponto, RH, notifier, índice de alertas, Medicina, Viaturas ou Planeamento. Apenas os checks/scripts auxiliares de B foram reforçados no backend.
