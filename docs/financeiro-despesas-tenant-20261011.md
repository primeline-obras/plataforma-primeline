# Despesas Gerais / Débitos Diretos — pacote local

Base: `1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0`.
Branch: `fix/despesas-gerais-tenant-20261011`.
Não executar estes scripts em produção sem autorização específica posterior.

## Diagnóstico factual e causa

A consulta READ ONLY devolvida por Jordane, em 11/10/2026 às 16:17:31 UTC, confirmou **0 débitos e 0 lançamentos**. Classificação real: A = 0, B = 0, C = 0. Não há backfill de dados reais a realizar neste checkpoint.

As duas tabelas não possuem `empresa_id`. `debitos_diretos` tem FK opcional para `obras` e FK opcional de autor para `utilizadores`; não tem fornecedor ou conta. O autor não prova o tenant. O lançamento tem FK obrigatória para o débito, única por débito/data. O `ON DELETE CASCADE` dessa FK já existe; o pacote não cria um novo cascade.

Owner `postgres`, RLS habilitada, sem FORCE RLS. Policies permissivas: INSERT por `fn_e_administrativo() OR fn_e_financeiro()`; SELECT pelos mesmos helpers ou por obra visível. Isso não limita as leituras financeiras dos perfis administrativos à empresa. Grants atuais: authenticated SELECT/INSERT, service_role ALL; nenhum UPDATE/DELETE genérico authenticated. As ACLs de coluna são nulas. Ambos os audit triggers estão habilitados e chamam `fn_registar_log_auditoria('id')`.

O ramo antigo de despesas gerais foi fechado porque uma linha sem obra não tinha relação inequívoca com empresa. O pacote **mantém esse bloqueio na RPC antiga**, que continua a importar somente obras autorizadas. Cria um caminho Financeiro separado com preview, token, confirmação e auditoria.

Seis helpers e respectivos hashes/ACLs foram confirmados no diagnóstico real. A consulta ampla não incluiu a definição de `fn_importar_mapa_financeiro_xlsx`; a consulta específica foi enviada para confirmação. O precheck exige explicitamente o hash da definição auditada e aborta se ela faltar ou divergir. Não considerar essa dependência confirmada no catálogo real antes do resultado específico/precheck autorizado.

### Consumidores preservados

- `app.js`: listagem de débitos/lançamentos, criação manual, lançamento real e cash flow por obra. Não alterado.
- `financial-map.js`: agregação anual das três categorias e importação. Único ficheiro existente de frontend alterado.
- `direct-debits.js`: ocorrências recorrentes/previsões. Não alterado.
- `consolidated-view.js` e `production-dashboard.js`: leituras financeiras/custos por obra. Não alterados.
- `settings.js`: nomes de tabelas na auditoria. Não alterado.
- Importador XLSX compartilhado: não alterado; outros módulos continuam no caminho anterior.

Não foi encontrada RPC dedicada anterior de apagar/cancelar débitos no catálogo capturado. A nova reversão aplica-se exclusivamente às operações deste importador, não a débitos manuais ou importações antigas.

## Modelo

1. `empresa_id` nas duas tabelas, com FKs para empresas e FK composta filho/pai/empresa.
2. Backfill A apenas: obra existente com empresa existente; lançamento herda empresa do pai. B: sem obra; C: relação inexistente ou empresa não identificável. B/C conservam os campos antigos e ficam com empresa NULL, invisíveis à aplicação e sem possibilidade de alteração pelo novo caminho.
3. Checks NOT VALID preservam B/C históricos, mas exigem empresa em qualquer linha nova/atualizada. A guarda atribui empresa pelo ator autenticado, valida relação da obra/pai e recusa empresa/autor forjados.
4. Policies restritivas somadas às policies existentes. SELECT/INSERT authenticated preservados; nenhum UPDATE/DELETE genérico concedido. Retirados os grants diretos de anon/service_role nestas duas tabelas.
5. Reutilização de `fn_economico_ator_atual` e `fn_financeiro_autorizar_obra`; ambos permanecem byte a byte definidos como antes. Sessão com múltiplas identidades ativas é recusada.
6. Schema financeiro privado para grupos canónicos, operações e chave de HMAC. Sem acesso PUBLIC/anon/authenticated/service_role. Nenhuma arquitectura global de tenant é introduzida.

## Semântica

O débito é uma previsão recorrente e os lançamentos são valores realizados por data. Não é uma ordem bancária, pagamento ou fatura. O Mapa Financeiro usa as categorias Remunerações e Encargos (Sede), Despesas Sede e Despesas Armazém. Para novas importações, cada grupo canónico tem previsão zero e lançamentos mensais reais: sem nova previsão duplicada.

Não se adopta nem consolida um débito individual por descrição ou nome. Se existir um débito individual da mesma categoria no tenant, o preview recusa e exige reconciliação explícita. Nenhum dado ambíguo é inventado para desbloquear esse caso.

## Permissões preservadas

| Perfil | Leitura de débitos | Criar débito/lançamento manual | Importar/confirmar novo fluxo | Substituição e reversão da nova importação | UPDATE/DELETE genérico |
|---|---|---|---|---|---|
| Gestão da Plataforma | própria empresa | própria empresa | sim | confirmação explícita/auditoria | não |
| Gerência | própria empresa | própria empresa | sim, contrato financeiro existente | confirmação explícita/auditoria | não |
| Administrativo | própria empresa | própria empresa | não; recusa atual do importador preservada | não | não |
| Financeiro | própria empresa | própria empresa | sim | confirmação explícita/auditoria | não |
| Diretor/Adjunto/Preparador | somente obra legitimamente visível | não | não | não | não |
| Encarregado | sem dados financeiros | não | não | não | não |

A navegação global não muda. Administrativo mantém o Mapa Financeiro oculto conforme a configuração atual. Gestão continua com capacidade funcional, sem bypass de tenant, ator ativo, confirmação, concorrência e auditoria.

## Importação e UX

- Uma folha “Mapa Financeiro”, cabeçalho Obra e JAN–DEZ. Número de obra único ou um dos três rótulos de despesas. Até 5 MB, 1–1000 linhas e valores fixos; fórmulas/textos monetários arbitrários recusados.
- Campos mensais numéricos ou vazios, zero preservado. Número decimal português/inglês validado estritamente. Linhas desconhecidas não são descartadas silenciosamente.
- Preview servidor sem escrita de factos: contagens válidas/ inválidas/duplicadas, erros por linha, destino e valores mensais na UI.
- Qualquer linha inválida impede o ficheiro inteiro. Duplicados no próprio ficheiro exigem consolidação; valores já iguais são preservados sem duplicar factos.
- Substituir valores diferentes exige escolha explícita, novo preview e confirmação. Sem escolha, recusa.
- Token HMAC-SHA256 vinculado a ator, empresa, request, payload e snapshot. Implementação RFC 2104 conferida com Node crypto. Confirmação serializada; alterações posteriores invalidam preview.
- Retry ambíguo usa o mesmo request/payload/token. Replay devolve resultado e não repete escrita. Payload diferente no mesmo request, outro ator/tenant ou operação revertida são recusados.
- Importação mista validada integralmente antes de delegar as linhas de obra à RPC antiga, na mesma transação. Nenhuma escrita parcial nem log de importação em caso de recusa.
- Reversão da nova importação: motivo, novo request, preview/confirmar, comparação exacta de after-images e ausência de filhos posteriores. Recusa qualquer drift. Restaura valores anteriores ou remove exclusivamente objectos criados pela importação. Mantém operação original, motivo, ator e logs.
- Cancelar preview não grava. Respostas tardias são descartadas e o diálogo fecha em troca de identidade. A fronteira global de sessão permanece intacta.

Screenshots sintéticas de desktop em `docs/evidencias/financeiro-despesas-20261011/`: preview, confirmação, resultado e erros. Inspecionadas visualmente; sem corte, sobreposição ou confirmação oculta. Valores e rótulos em português. Não são capturas de dados reais.

## Scripts e futuro rollout

1. `supabase/financeiro_debitos_tenant_20261011_precheck.sql` — READ ONLY. Exige owner, colunas/tipos/defaults, RLS, policies, grants, constraints, triggers e hashes/ACL/owner/search_path dos helpers. Qualquer divergência aborta. Não instala nem reconcilia.
2. `supabase/financeiro_debitos_tenant_20261011_backup.sql` — backup privado específico, bloqueio das duas tabelas, dados e ACLs, sem substituir backup prévio.
3. `supabase/financeiro_debitos_tenant_20261011.sql` — transacional; repete catálogo/precheck e igualdade do backup antes da alteração. Somente tabelas financeiras relacionadas e novos objectos privados/públicos deste pacote.
4. `supabase/financeiro_debitos_tenant_20261011_postcheck.sql` — READ ONLY imediatamente após migration, antes de liberar escritas: dados históricos iguais, backfill A apenas, ACL/RLS/auditoria/RPCs privados e helpers inalterados.
5. `supabase/financeiro_debitos_tenant_20261011_rollback.sql` — apenas preparado/manual. Recusa novas operações ou dados diferentes; restaura instalação sem CASCADE e mantém backup/auditoria. Não usar depois de novas importações; para estas existe reversão lógica própria.

Ordem futura, somente após autorização: PRECHECK → BACKUP → MIGRATION → POSTCHECK → publicação autorizada do frontend → smoke financeiro autenticado sem factos fictícios. STOP em qualquer erro; rollback nunca automático. Não há Fase B neste pacote.

## Testes

Matriz A–Q coberta com dados sintéticos:

- A/B: leitura e escrita cross-company, actor/empresa/obra/pai forjados, obra cujo tenant muda após preview.
- C/D/E/F: importação válida/mista, inválida integral, duplicados de ficheiro/BD, replay, payload alterado, requests concorrentes iguais/distintos.
- G–K: ativo/inativo, Gestão, Administrativo, Financeiro, Gerência, Diretor/Adjunto/Encarregado; leitura existente e recusa/importação conforme contrato.
- L/M/O: A por FK, B sem obra e C com empresa ausente preservados; igualdade integral dos campos anteriores.
- N/P: rollback de instalação, recusa após novos factos, RLS, policies, grants, owners/search_path, ACL privada, drift do postcheck, auditoria e reversão.
- Q: diff protegido contra main + suite funcional PostgreSQL existente do Encarregado. Folha, equipa, externos, jornadas, links RH, Quadro/Agenda/Planeamento e access-control não alterados.

Execuções locais: pacote 38 PASS / 0 FAIL / 0 SKIP; autorização financeira SQL/PostgREST existente 122 PASS; unidades/regressões existentes 67 PASS; Encarregado PostgreSQL 23 PASS. Total efectivo: 250 PASS / 0 FAIL / 0 SKIP, mais 10 grupos browser Financeiro. O SKIP inicial do Encarregado por ambiente ausente foi substituído pela execução efectiva de 23 testes com ambiente configurado.

Comandos: definir `QUADRO_PG_BIN` (PostgreSQL 17.6), `QUADRO_TEST_DEPS` (`pg`), `QUADRO_POSTGREST` (regressão REST), `PLANNING_PLAYWRIGHT`. Executar as suites do pacote, `financeiro-cross-tenant.test.mjs`, regressões financeiras/sessão e `encarregado-fecho-final.test.mjs`. `FINANCE_SCREENSHOT_DIR` é opcional e recebe somente dados sintéticos.

O gerador `tests/financeiro-debitos-package.py` mantém scripts e contrato reproduzíveis a partir do catálogo commitado. Não contém credenciais nem ligações remotas.

`ENCARREGADO_IMPACT = NONE`

## Limites e riscos

- Pacote testado localmente; nenhum desbloqueio, alteração de dados, SQL de escrita, permissão, deploy ou merge real.
- Catálogo pode mudar antes do rollout: o precheck exacto é obrigatório e aborta drift. A confirmação específica da RPC antiga ainda precisa ser recebida; não afirmar prontidão de produção antes dela/precheck real autorizado.
- Backfill não infere empresa para gerais/órfãos. Se surgirem B/C, ficam bloqueados para decisão humana.
- Reversão recusa actividade posterior; rollback de instalação não apaga novas importações. É necessário planear janela de rollout sem escritas financeiras entre backup e postcheck.
- Sem nova automatização bancária, pagamento/fatura, exportador, Fase B ou alteração operacional dos Encarregados.
- A segunda worktree deve repetir o pacote e regressões no commit final publicado, sem artefactos locais não commitados. SHA e resultado são entregues no checkpoint final.
