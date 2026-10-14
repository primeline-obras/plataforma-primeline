# Testes adicionais dos P1 — Fase 2

## Resultado e interpretação

Execução final: **37 PASS / 0 FAIL / 0 SKIP**, apenas local.

- `night-phase2-finance.test.mjs`: 21 testes contados pelo node:test, incluindo o grupo PostgreSQL e 10 subtestes. Dez testes HTTP/VM + dez subtestes SQL + um grupo. O grupo não representa uma prova adicional de negócio.
- `night-phase2-html.test.mjs`: 16 testes browser; 12 reproduzem saída insegura, três controlam conteúdo protegido e um confirma apresentação legítima.
- Fase 1: **236 PASS preservados**, não reexecutados. Soma de execuções históricas e novas: 273; não chamar a soma de regressão única da plataforma.
- O inventário e as validações de ficheiros/CSV são verificações adicionais, contadas separadamente em `VERIFICACAO-PACOTE.json`.

**PASS de reprodução não significa produto seguro.** Os campos classification das evidências distinguem falha demonstrada de controlo correto. Nenhum problema de produto foi corrigido.

## Ambiente e independência

Código de funções extraído do src, não uma reimplementação do handler. Browser Edge/Playwright em about:blank, origem null, rede bloqueada; ZERO pedidos nos casos de renderização. A carga cria apenas marcador e handler sintéticos; evento error é disparado deliberadamente, sem endpoint externo, persistência real ou sessão de produção.

PostgreSQL 17.6 local descartável, host 127.0.0.1, porta livre. Definições das duas RPCs extraídas do SQL do hotfix. Tabelas mínimas sintéticas; helpers de autorização stubs permitidos. A concorrência da RPC parcial usa duas conexões reais. Clusters são parados no finally e não foram eliminados. Estes testes não substituem RLS/PostgREST/Auth hospedado.

## Matriz de faturação

| Cenário novo | Prova esperada e observada | Tipo |
| --- | --- | --- |
| INSERT recusado | Zero entidades; botão reativado | Controlo negativo |
| Links recusados | Um cabeçalho, zero links, UI sem cabeçalho | Falha reproduzida |
| Upload recusado | Um cabeçalho e links persistidos | Falha reproduzida |
| Metadata recusada | Cabeçalho, links e blob; zero documentos associados | Falha reproduzida |
| Resposta INSERT perdida | Commit existe; UI erra | Resultado ambíguo reproduzido |
| Resposta links perdida | BD tem links; UI erra | Resultado ambíguo reproduzido |
| Sucesso com PDF | Todas entidades e cache coerentes | Controlo positivo |
| Concorrência mesmo auto | Dois drafts; um link; um draft órfão | Modelo HTTP com índice do Git; não hosted |
| Retry depois de timeout de commit | Segundo draft; primeiro não recuperado | Sem idempotência do handler |
| Fornecedor: falha dos artigos | Cabeçalho existe; zero artigos; formulário limpo | N2-FIN-01 reproduzido no handler real |

Não há compensação executada na plataforma. Counts correspondem a entidades da fixture, sem afirmar que triggers/RLS reais permitam todas estas escritas.

## Matriz de recebimentos

| Cenário | Resultado | Interpretação |
| --- | --- | --- |
| Antiga 0/-1/NULL | Recusados; fatura preservada | Três controlos negativos |
| Antiga 100 de 1000 | pago, recebido=100, zero movimentos | Incoerência |
| Antiga 1000 de 1000 | pago, recebido=1000 | Integral funciona; ledger ausente |
| Antiga 1100 de 1000 | pago, recebido=1100 | Falta de limite no corpo; fixture sem checks adicionais |
| Parcial existente | 100→por_pagar; replay não duplica; alteração ID/excesso recusados; +900→pago | Mecanismo existente útil |
| Duas parcelas concorrentes total esperado 0 | Uma aceita; outra STALE_REVISION; recebido=100 | Lock e revisão aprovados na fixture |
| Parcial 100 + antiga 900 | Documento 900/pago; ledger 100 | N2-FIN-02 |
| Parcial outubro 100 + novembro 900 | Helper caixa retorna 0/1000 | N2-FIN-03 |

## Matriz HTML

Fase 1 preservada: paymentDialog, renderWorks, financeCard. Fase 2:

- paidFinanceRow: fornecedor e número — HTML executável.
- renderInvoices: fornecedor e número — HTML executável.
- toast: mensagem — HTML executável.
- renderMeasurementsTab: número fatura, número auto, billingError — HTML executável.
- renderWorkDetail: nome, cliente, morada, erro — HTML executável.
- invoiceTraceEvents: comentário/autor — texto literal.
- renderWorkDocumentsTab: nome/referência/revisão/destinatários — texto literal.
- renderNotificationDrawer: título/descrição — texto literal.
- safeText: `<>&` e aspas preservados como texto visível.

## Evidências e reprodução

`EVIDENCIAS-FINANCEIRO.json`, `EVIDENCIAS-HTML.json`; scanner em `HTML-INVENTARIO.json` e CSVs. Rodar as suites a partir da worktree da auditoria com as dependências existentes:

```powershell
$env:QUADRO_PG_BIN=Join-Path $env:TEMP 'primeline-doc-guard-pg176\package\native\bin'
$env:QUADRO_TEST_DEPS=Join-Path $env:TEMP 'primeline-medicina-test-deps\runtime\node_modules'
$env:PLANNING_PLAYWRIGHT='C:/Users/conta/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'
$env:PLANNING_CHROMIUM_EXE='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
node --test tests/night-phase2-finance.test.mjs tests/night-phase2-html.test.mjs
```

Executar em ambiente local preparado; não substituir variáveis por endpoints/credenciais reais. Se deps ausentes, o grupo PG declara SKIP; esta execução teve zero SKIP. Browser exige runtime disponível e falha explicitamente se não existir.

Problemas de preparação dos novos testes foram corrigidos nos próprios testes (atribuições de globals e comparação de array entre realms VM). A execução final ficou verde. Não foram enfraquecidas as provas anteriores nem alterado produto.

## Limites

Persistência real de HTML, CSP real, triggers/grants/catalog atual, Auth hosted, duplicados reais, órfãos reais, alertas concretos de cliente, regras fiscais/contratuais e reconciliação histórica não foram demonstrados. A fila lexical não certifica todos os caminhos possíveis. Os testes de concorrência cliente são HTTP simulado; a concorrência parcial é PostgreSQL real sintético. Publicação continua NO-GO.
