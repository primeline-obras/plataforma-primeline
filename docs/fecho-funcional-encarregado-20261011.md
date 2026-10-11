# Fecho funcional do Encarregado — 11/10/2026

## Decisão e base

Pacote local único, baseado em `cb6c91fea07d1e86dabdd6e34c2c2b4d222085f8`, na branch `fix/encarregado-fecho-final-20261011`. A proposta visual foi aprovada expressamente pela Jordane. Nenhuma execução SQL real, alteração de dados reais, merge em main, publicação, deploy ou Fase B nesta tarefa.

## Diagnóstico e resultado

| Área | Antes | Resultado implementado |
|---|---|---|
| Folha | Entrada/saída coletiva ligadas ao relógio e excesso de ações | Adicionar pessoa e Registar Dia Normal como as duas ações principais; edição no cartão e Cancelar sem guardar |
| Dia Normal | Dependência do calendário de HE e bloqueio pela hora atual | Usa a jornada formal configurada; confirmação de pessoas, obra, data e intervalos completos; datas futuras continuam recusadas |
| Dias especiais | Possibilidade de confundir jornada padrão com horas factuais | Sábado/domingo/feriado conhecido não recebem Dia Normal; horários reais e revisão especial preservados |
| Encarregado | Próprio ausente da Folha | Cartão `ENCARREGADO · VOCÊ`, ligado exclusivamente pela identidade RH existente e única, sem criar permanência própria |
| Multiobra | Correção isolada por obra podia causar sobreposição ou perda de factos | Plano atómico por local/período, revisão de todos os targets antes de escrever, ajuda temporária sem transferência de equipa |
| Retirada/transferência | Existência de ponto bloqueava alteração de permanência | Permanência pode terminar/transferir; horas, histórico, ausências e regras de conflito permanecem preservados |
| Externos | Inclusão ligada ao registo de horas de um dia | Identidade e permanência próprias; fornecedor e função; inclusão sem inventar horas; retirada explícita, dois períodos e total visível |
| Plano de Ação | Botão principal desproporcional no cartão | `REPORTAR CONCLUSÃO` secundário, alvo mínimo de 44px; reporte continua a aguardar o Diretor |
| Planeamento | Pesos resolvidos competiam com a tabela | 100% oculto; somente exceções abaixo da tabela; acesso a custos permanece intacto |
| Agenda | Duplicação e perfil técnico mostrado como cargo | Deduplicação por identidade; cargo formal preferido; conta técnica sem pessoa RH excluída; diretório da empresa preservado |
| Quadro | Regra antiga ainda habilitava edição ao Encarregado | Consulta mantida; editor/ímanes de alteração indisponíveis ao Encarregado; equipa gerida na Folha |

### Regras preservadas

- Tenant, âmbito de obra, utilizador ativo, autoria, auditoria, revisão e idempotência continuam obrigatórios.
- As escritas novas usam as RPCs V2 existentes. Não há DML direto na Folha pelo frontend.
- Hoje/ontem: regras de correção existentes. Datas anteriores: Administrativo/Gestão autorizado com motivo; nenhuma ampliação de permissões aos perfis técnicos.
- Horas em obra e Escritório dos perfis Diretor/Adjunto/Preparador preservadas. A consulta pessoal destes perfis não tenta ler terceiros.
- Multiobra revalida todos os locais mesmo em replay; lock comum do Quadro/Folha e lock pessoa/dia, isolamento READ COMMITTED. Revisões de locais esvaziados ficam guardadas para impedir reutilização da revisão 0.
- Horas antigas com mais de dois intervalos internos não são truncadas. A limitação de dois períodos aplica-se ao editor externo.
- Externo 10:00–16:00 contabiliza 360 minutos; não cria pagamento, vencimento ou cadastro Primeline. Dia Normal inclui externos elegíveis com a mesma jornada formal e confirmação.
- Retirar alguém não cria falta, ausência, saída de relógio ou horas. Factos já registados continuam consultáveis no Histórico da Obra.
- Foram corrigidos os valores de movimento usados pela nova definição (`retirada` / `alterada`) para respeitar a constraint instalada; a estrutura legada não foi relaxada.
- Writer de Ponto legado continua CLOSED. Nenhum marcador B ou mudança de fase está incluído.

## Configuração factual: nenhum horário inventado

08–12 / 13–17 é a jornada usada nas fixtures e no protótipo. A produção usa exclusivamente `folha_horarios.intervals` já configurado. Quando falta configuração, aparece `JORNADA NORMAL POR CONFIGURAR`; registo factual continua disponível, e o preenchimento automático não inventa uma jornada. Antes do rollout deve ser verificada a configuração formal da obra e a ligação única do Encarregado ao seu colaborador RH. Identidades, delegações e cargos não são inferidos.

## Scripts de rollout

Todos os scripts são novos e independentes dos ficheiros de rollout anteriormente publicados:

1. `supabase/encarregado_fecho_final_precheck.sql` — READ ONLY; resultado `ENCARREGADO_FINAL_PRECHECK_OK`. Exige owner/baseline de dez funções e writer legado CLOSED. Divergência: parar.
2. `supabase/encarregado_fecho_final_backup.sql` — backup privado de definições/owners/ACL, dez tabelas operacionais e duas tabelas privadas; resultado `ENCARREGADO_FINAL_BACKUP_OK`. Não substitui backup pré-existente.
3. `supabase/encarregado_fecho_final.sql` — instalação transacional. Reconfirma fingerprints e igualdade dos dados com o backup antes de qualquer alteração estrutural. Cria `folha_externos_permanencias`, `folha_privado.externos_revisoes`, `folha_privado.periodos_revisoes` e helpers privados; substitui definições V2/Agenda. Não insere nem corrige factos operacionais.
4. `supabase/encarregado_fecho_final_postcheck.sql` — READ ONLY; resultado `ENCARREGADO_FINAL_POSTCHECK_OK`. Confirma funções, helper de períodos derivado, ACL/RLS, estruturas vazias, legado CLOSED e igualdade integral dos dados preservados.
5. `supabase/encarregado_fecho_final_rollback.sql` — disponível apenas para decisão explícita; nunca executar automaticamente. Restaura as definições/owners/ACL originais e remove as estruturas novas somente se não houver dados/utilização posterior ou divergência dos snapshots. Backup privado preservado.

**Ordem futura:** PRECHECK → BACKUP → MIGRATION → POSTCHECK → integração frontend autorizada → deploy → comparação de assets → smoke autenticado de leitura Gestão/Encarregado. Qualquer erro: parar; confirmar rollback da transação antes de prosseguir. Não fazer Fase B. Os scripts não são executados automaticamente pela aplicação nem pelo deploy.

## Testes e evidência local

O runner `tests/encarregado-fecho-final-run.mjs` executa a matriz de unidades/PostgreSQL e dez suites de browser. O PostgreSQL é efémero, ligado exclusivamente a 127.0.0.1; os browsers usam mocks sintéticos e interceptam tráfego externo. Isto não constitui UAT nem prova do catálogo instalado em produção.

Cobertura funcional: duas ações principais; jornada completa; exceção individual; sábado; ponto próprio; multiobra próprio/equipa; Escritório; deslocação integral e revisão monotónica; primeiro horário somente noutra obra autorizada; ajuda temporária; transferência/retirada com horas; externos persistentes/removíveis/Dia Normal/6h; concorrência; replay; tenant; ator inativo; revisão stale sem escrita parcial; backup obsoleto abortado antes de DDL; instalação/postcheck/rollback vazio/reinstalação; rollback com utilização recusado; Agenda; Quadro em consulta e projeção de permanências; sessão; RH; Medicina; Planeamento/custos; Financeiro; RNC; Viaturas.

Testes históricos foram atualizados somente onde o contrato aprovado mudou: remoção do relógio coletivo, `periods_save`, tarefas no Plano de Ação, Quadro em consulta para Encarregado e mocks do mapa V2 de férias. Factos manuais de suites históricas usam ontem para continuar dentro da janela real; testes retroativos e negativos mantêm datas explícitas. Não se substitui o relógio de PostgreSQL.

### Resultado da matriz completa

- Unidades e PostgreSQL: **431 PASS / 0 FAIL / 3 SKIP**.
- Dez suites de browser: **PASS**, incluindo 170 verificações da nova suite consolidada.
- As três exclusões históricas continuam SKIP: migração/cadastro/lote RH; formulário RH ao guardar; aviso contratual RH. Não são contadas como aprovações.
- Instalação, postcheck, rollback vazio e reinstalação: PASS local. Backup obsoleto e rollback após utilização: recusados como previsto.
- Concorrência, replay, tenant, janela de correção, revisão stale e conservação dos factos: PASS.
- `git diff --check`: PASS.

A entrega exige repetir este mesmo runner numa segunda worktree limpa no SHA final, após commit e push. A confirmação do SHA e do resultado dessa repetição acompanha a entrega; não requer alterações ao produto.

### Reprodução local

Definir `QUADRO_PG_BIN` para uma distribuição PostgreSQL 17 completa com `initdb`/servidor, `QUADRO_TEST_DEPS` e `NODE_PATH` para as dependências sintéticas existentes, `PLANNING_PLAYWRIGHT` para o módulo Playwright e `PLANNING_CHROMIUM_EXE` para Chrome. As suites antigas de browser também usam Edge instalado. Executar `node tests/encarregado-fecho-final-run.mjs`.

Logs/resultados são escritos numa pasta temporária fora de Git. `ENCARREGADO_SHOTS` permite escolher a pasta de screenshots fora do repositório. Nenhuma credencial é necessária.

## Revisão visual

Chrome, touch habilitado: 768×1024, 1024×768, 820×1180, 375×812 e 1440×900. Capturas da Folha/equipa vazia, confirmação, editor, próprio, multiobra, externos, retirada, Plano, Planeamento e Agenda. Quadro em consulta capturado em tablet. Imagens inspecionadas quanto a proporção, corte, hierarquia, texto, alinhamento e ação contextual.

Galeria local de evidência sintética: `encarregado-final-implementado/index.html` na pasta de visualizações da tarefa; reproduzível pelo runner. O editor permanece junto à pessoa; o botão de tarefa cabe no cartão; a tabela domina o Planeamento; confirmação apresenta todos os afetados. Histórico é da obra, com as horas por pessoa, sem nova UX de auditoria individual.

## Limites e próximo gate

GO local para preparar um único rollout. Não se declara catálogo real reconfirmado nesta tarefa. A autorização de publicação/SQL real continua pendente. A jornada formal e as ligações RH existentes precisam ser confirmadas por consulta READ ONLY autorizada de configuração e pelo smoke real; o precheck verifica o catálogo e não configura esses dados; nenhuma foi preenchida nesta implementação. As regras de HE/Vencimentos que já estavam condicionadas permanecem condicionadas. Não foi feita alteração em Medicina, contratos, Financeiro, perfis reais ou Fase B.


## Dívida futura preservada

Calendário do Plano de Ação com ampliação por dia não foi implementado; permanece melhoria futura. O Quadro conserva o desenho atual, com scroll horizontal e consulta, sem redesign completo. HE monetária, exportadores e Financeiro de externos permanecem fora deste pacote.

## Ficheiros do pacote

- `index.html`
- `src/action-plan.js`
- `src/app.js`
- `src/attendance-client.js`
- `src/attendance-domain.js`
- `src/attendance-management.js`
- `src/attendance-sheet.css`
- `src/attendance-sheet.js`
- `src/calendar.js`
- `src/planning.js`
- `tests/attendance-adm-rules-browser.mjs`
- `tests/attendance-backend-v2.test.mjs`
- `tests/attendance-consolidation-browser.mjs`
- `tests/attendance-domain.test.mjs`
- `tests/attendance-sheet-browser.mjs`
- `tests/attendance-visible-state-browser.mjs`
- `tests/encarregado-tablet-ux-browser.mjs`
- `tests/folha-equipa-operacional.test.mjs`
- `tests/session-boundary-browser.mjs`
- `tests/workforce-admin-only.test.mjs`
- `tests/workforce-controlled-browser.mjs`
- `docs/fecho-funcional-encarregado-20261011.md`
- `supabase/encarregado_fecho_final.sql`
- `supabase/encarregado_fecho_final_backup.sql`
- `supabase/encarregado_fecho_final_postcheck.sql`
- `supabase/encarregado_fecho_final_precheck.sql`
- `supabase/encarregado_fecho_final_rollback.sql`
- `tests/encarregado-fecho-final-browser.mjs`
- `tests/encarregado-fecho-final-run.mjs`
- `tests/encarregado-fecho-final.test.mjs`
