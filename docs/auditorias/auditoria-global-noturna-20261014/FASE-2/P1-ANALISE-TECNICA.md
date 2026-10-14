# P1 — Análise técnica aprofundada

## Âmbito e estado

Auditoria de código e execução sintética sobre o produto do checkpoint `439b1e3b900a8d5b919062cf8efd1f05868e494a`, branch `codex/auditoria-global-noturna-20261014`. A base funcional continua `2ae1f8a194f23d77bf0692d0a6d586566227298c`. Os dez documentos da Fase 1 foram lidos; resultados e 34 IDs preservados. Nenhuma correção funcional, SQL hospedado ou alteração de permissões foi executada. As propostas abaixo precisam de tarefa de correção autorizada.

Os 236 PASS anteriores não foram repetidos nem tratados como prova de segurança. Nesta fase os testes de reprodução passam quando demonstram uma falha. A produção, os dados reais, o CSP hospedado e o catálogo atualmente instalado não foram consultados.

## 1. N-SEC-01 — Texto interpretado como HTML executável — P1

### Causa e inventário

Templates de estrutura e dados não confiáveis são concatenados antes de `innerHTML`. O campo não precisa conter código JavaScript como valor funcional; a interpretação do texto como marcação cria elementos com handlers. Autorização de leitura não torna o texto seguro.

A varredura lexical abrange os **56 ficheiros JS**, encontra **183 ocorrências de sinks** e gera **1.206 interpolações candidatas** em `HTML-SINKS.csv`, `HTML-INTERPOLACOES.csv` e `HTML-INVENTARIO.json`. Estes números são uma fila rastreável de revisão, não 183 vulnerabilidades. O scanner não é um analisador de taint/AST; interpolações aninhadas e contexto de função têm limites explícitos. Não é legítimo afirmar ausência de todos os demais sinks apenas com esta varredura.

### Renderizadores afetados confirmados

| Renderer / ponto | Origem e caminho | Perfis potencialmente expostos segundo frontend | Prova |
| --- | --- | --- | --- |
| `renderWorks`, app:1593 | `obras.nome/cliente` → lista de obras → HTML | Gestão, Gerência, Administrativo, Financeiro, Diretor, Adjunto, Preparador, nas obras que lhes sejam devolvidas | Fase 1: nome executável; cliente é interpolação crua da mesma linha |
| `renderWorkDetail`, app:3805–3809 | `obras.nome/cliente/morada`; `workDetails.error` → detalhe | Mesmos perfis com vista works; Financeiro tem resumo sem edição | Fase 2: quatro campos criam nó e executam handler |
| `renderInvoices`, app:1152 | `fornecedores.nome`, `faturas.numero_doc` → fila de aprovação | Gestão, Gerência, Administrativo, Diretor, Adjunto, Preparador | Fase 2: fornecedor e número executáveis |
| `financeCard`, app:1248 | Mesmos campos → cartão a pagar | Gestão, Gerência, Administrativo (consulta) e Financeiro, conforme dados disponíveis | Fase 1: fornecedor; número usa a mesma saída crua |
| `paidFinanceRow`, app:1269 | Mesmos campos → faturas já pagas | Perfis da vista finance | Fase 2: fornecedor e número executáveis |
| `renderMeasurementsTab`, app:3212/3229/3246 | `faturacao.numero_fatura`, `autos_medicao.numero_auto`, `billingError` → autos da obra | Gestão, Gerência, Administrativo, Diretor, Adjunto, Preparador; Financeiro força summary | Fase 2: três campos executáveis |
| `openPaymentDialog`, app:4677 | Número lançado em submitBilling → diálogo de recebimento | Gestão/Gerência/Financeiro com ação de pagamento permitida | Fase 1: execução browser sintético |
| `toast`, app:1038 | Mensagem, incluindo erros devolvidos por APIs e número de fatura em app:1385 → aviso global | Potencialmente todos os perfis que alcancem uma chamada; não presume acesso direto do Encarregado às faturas | Fase 2: mensagem executável; caminho de origem confirmado por código |

Perfis são alcance de interface, **não prova de grants/RLS instalados**. A passagem por uma query legítima pode levar texto de um utilizador a outro; capacidade concreta de persistir a carga depende das validações reais, não exercitadas nesta missão. O impacto potencial é execução no contexto do utilizador que lê o dado. Não foram usados tokens, exfiltração, persistência real nem rede.

### Conteúdo livre e controlos negativos

- `renderWorkDocumentsTab`: nome, número, revisão e destinatários escapados; ficheiro sintético com marcação ficou literal.
- `invoiceTraceEvents`: observação e autor escapados; controlo browser aprovado. `renderInvoiceTrace` também escapa número/fornecedor/obra por revisão de código.
- `renderNotificationDrawer`, production-dashboard:567: título e descrição escapados; controlo browser aprovado. Não confundir o drawer protegido com o toast inseguro.
- `openWorkforceMovements`, app:2630–2675: nomes, locais, descrições e erro passam por safeText; revisão de código.
- Ausências, app:2219/2222: comentário usa safeText. RNC/Agenda possuem esc nos principais textos; a inspeção não certifica cada atributo de cada estado desses módulos.
- `renderTeam` possui erro cru em app:2151 e título de férias com shortPersonName sem escape em app:2157. São **candidatos estáticos** desta família; não contabilizados como novas provas de execução completas.
- URLs de Storage são construídas em origem configurada e cada segmento é codificado (`supabase-browser.js:183`). Não foi demonstrado envio de token a URL arbitrária neste caminho. Atributos/URLs devem ter validação própria, além de escaping.
- Títulos atribuídos por `textContent`, strings de pesquisa e mensagens já escapadas não são vulnerabilidades por conter `${...}`. Exemplo: app:586/1198/1357.

### Correção proposta e aceitação

1. Usar textContent para nós de texto; nos templates necessários, escapar **cada dado** no ponto de saída. Não escapar o template inteiro, que quebraria `<strong>`, botões e grelhas legítimas.
2. Separar mensagens textuais de markup gerado por icon/estrutura. Toast recebe texto; ícone fica no template de confiança. Proibir API.message como markup.
3. Atributos devem escapar aspas; classes/estados usam enum permitido; URLs têm origem/esquema/path validados. `encodeURIComponent` de uma string não substitui toda a política de URL.
4. Não remover `<>&` do dado armazenado nem alterar nomes/números. Os caracteres legítimos permanecem visíveis, testados por roundtrip.
5. Só adotar sanitizador se existir contrato aprovado de rich text. Nenhum dos campos acima exige HTML de utilizador nesta auditoria.
6. Testar os oito renderizadores, todos os campos identificados, mensagens de erro, aspas/atributos, controlos protegidos e alcance por perfil/obra. CSP pode reduzir impacto, mas não substitui corrigir o sink.

Correção tecnicamente independente das decisões de custos, sem ampliar capacidades. Risco de regressão médio: preservar eventos/data-attributes, estrutura e tablet. **Não implementada.**

## 2. N-FIN-01 — Criação não atómica — P1

### Dois circuitos que não devem ser confundidos

**Cliente** (`faturacao`, `submitBilling`, app:4625–4672): obra/contrato/autos → fatura rascunho → `faturacao_autos_medicao` → upload PDF opcional → `documentos` com entidade faturacao → só então cache/UI/toast. Os links transportam tipo/referência/valor de cada auto. A tabela histórica define PK composta, FK fatura/auto e UNIQUE(auto_medicao_id), `autos_faturacao_workflow.sql:7–15`. A instalação real desse índice não foi confirmada nesta fase.

**Fornecedor** (`faturas`, formulário app:5524–5686): fornecedor/obra/subempreitada/tipo/valor → busca de duplicados → confirmação → PDF antes do cabeçalho → POST faturas → POST faturas_itens → UI considera guardado. Guias e anexos são adicionados posteriormente por upload + metadata. O vínculo à subempreitada é uma RPC própria, app:1109, e integra a aprovação/controlo contratual. `fn_editar_fatura_pendente` já recebe os itens numa RPC; não se conclui que editar e criar tenham a mesma atomicidade.

O P1 original foi demonstrado no **circuito cliente**. A Fase 2 reproduziu a falha dos artigos no **circuito fornecedor** separadamente (N2-FIN-01). Não há fornecedor/subempreitada diretamente no payload de submitBilling; esses vínculos pertencem ao circuito distinto de despesas. Não inventar uma FK comum entre as duas entidades.

### Falhas observadas no handler cliente real, com HTTP simulado

| Falha | Cabeçalhos | Links | Bytes | Metadata | UI |
| --- | ---: | ---: | ---: | ---: | --- |
| INSERT inicial recusado | 0 | 0 | 0 | 0 | Erro; controlo correto |
| Links recusados | 1 | 0 | 0 | 0 | Erro; fatura não aparece no cache |
| Upload falha | 1 | 1 | 0 | 0 | Erro; dados BD já ficaram |
| Metadata falha | 1 | 1 | 1 | 0 | Erro; PDF sem associação |
| Resposta INSERT perdida após commit | 1 | 0 | 0 | 0 | Cliente ignora se persistiu |
| Resposta links perdida após commit | 1 | 1 | 0 | 0 | Cliente trata operação como falha |
| Sucesso completo | 1 | 1 | 1 | 1 | Cache atualizado; controlo correto |

Retry depois de resposta ambígua cria outro cabeçalho na fixture. Duas tentativas concorrentes para o mesmo auto, aplicando na fixture a unicidade definida no repositório, criam dois cabeçalhos e apenas um link: o perdedor fica órfão. Não é uma prova de concorrência HTTP na produção. Triggers de auditoria associados a cada escrita, quando instalados, registam etapas já confirmadas; não tornam os pedidos seguintes parte da transação anterior. Não eliminar história para disfarçar uma falha.

### Proposta controlada

- RPC única para criar cabeçalho e associações BD. Derivar ator/tenant, validar obra/contrato/autos/aprovação na BD, recomputar valores a partir de fontes autorizadas e obter locks numa ordem estável. Não confiar em totais ou empresa do frontend.
- Lock/revisão dos autos e unicidade garantem que duas faturas não os consumam simultaneamente. Conflito deve abortar **também o cabeçalho**.
- request_id associado ao ator/empresa e fingerprint do payload. Mesmo pedido retorna resposta de operação confirmada; conteúdo diferente recusa; timeout consulta estado, não cria novo pedido automaticamente.
- Concorrência também inclui revogação, mudança de obra do alvo e revisão do auto entre preview e confirmar. Validar snapshot na mesma transação; não alterar política de quem pode aprovar.
- Storage é serviço separado: SQL não oferece uma transação que inclua upload externo. Usar intenção de upload identificada → bytes pendentes → finalização metadata vinculada à operação/entidade → estado associado. Recuperar com proveniência; nunca apagar bytes de associação legítima com base apenas em nome/data.
- Definir com Jordane apenas os pontos funcionais necessários: PDF obrigatório ou opcional e política de retenção de pendentes. Atomicidade de cabeçalho/itens é obrigação técnica, não decisão de conceder acesso.
- Para fornecedor, transação cabeçalho+itens e validação de vínculo obra/fornecedor/subempreitada; manter as regras atuais de duplicado que permitem exceção confirmada à Gestão. Não impor unicidade que proíba essa exceção silenciosamente.
- Auditoria da operação e das recuperações, incluindo resposta perdida. Estado parcial explícito e reconciliação administrativa; nenhum apagamento/compensação financeira automático de linhas antigas.

Aceitação: injeção em todas as etapas; zero cabeçalho/link parcial em falha BD; retry/replay sem duplicar; concorrência sem órfãos; bytes recuperáveis; acesso entre tenants recusado; total/aprovação/revisão consistentes. Migration/precheck/backup/postcheck/rollback só numa futura tarefa — nenhum SQL novo de produto foi preparado aqui.

## 3. N-FIN-05 — Recebimentos, estado e consumidores — P1

### Fonte efetiva versus mecanismo já existente

O diálogo app:4690 chama `fn_marcar_faturacao_auto_paga(uuid,date,numeric)`. A definição protegida em `encarregado_escopo_migration.sql:1068–1116` verifica sessão/papel/obra e bloqueia a fatura com FOR UPDATE. Aceita valor >0, exige aprovado/por_pagar, grava valor_recebido com o valor da chamada e marca pago; não verifica integralidade nem grava parcela no ledger. O frontend também põe pago localmente sem usar o registo retornado pela RPC.

**Não falta uma RPC parcial no repositório:** `fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)`, no mesmo ficheiro:1118–1307, já possui ledger `faturacao_recebimentos`, lock, total esperado, request_id e recusa excesso. Parcial mantém por_pagar; integral passa pago. Não existe chamada dessa RPC nos ficheiros src deste checkpoint. A presença no repositório não prova instalação/estado real hoje.

### Resultados sintéticos sobre as definições reais

- RPC antiga: 0, negativo e SQL NULL recusados; 100/1000 marca pago; 1100/1000 é aceite na fixture monetária sem constraint adicional; 1000/1000 fecha corretamente. Nenhuma destas chamadas cria movimento.
- RPC parcial: 100 mantém por_pagar; replay mantém um movimento; payload distinto no mesmo ID recusa; 901 sobre saldo 900 recusa; +900 fecha 1000.
- Concorrência em PostgreSQL: duas parcelas com total esperado 0 → uma aceite e outra STALE_REVISION; total final 100.
- **N2-FIN-02:** parcela 100 pela RPC parcial, depois 900 pela antiga → documento guarda 900 e pago, ledger só contém 100; pedidos somariam 1000. Writers incompatíveis coexistem.
- **N2-FIN-03:** parcelas de 100 em outubro e 900 em novembro → RPC parcial guarda agregado 1000/data novembro; `actualCashFlowByMonth` lê cabeçalhos e mostra outubro 0/novembro 1000, em vez de 100/900.

Os helpers de sessão/obra/papel nos testes monetários são stubs permissivos. Estes testes não certificam autorização, isolamento ou catálogo real. São provas da lógica monetária e do controlo de revisão da definição capturada no Git.

### Consumidores e distinções necessárias

| Consumidor | Fonte/interpretação atual | Consequência / prova |
| --- | --- | --- |
| Autos da obra, app:3227–3257 | paid se estado=pago **OU** recebido>=valor | Com antigo pagamento parcial, mostra PAGO e retira ação de receber restante. Código confirmado; incoerência originada na RPC reproduzida |
| Visão Financeiro, production-dashboard:500–505 | Cliente por receber se valor>valor_recebido; mostra diferença | É controlo útil: ainda mostra saldo 900 mesmo quando outra vista considera pago. Não classificar este cálculo como ocultação automática |
| Caixa mensal, production-dashboard:61–72/1105 | Cabeçalho data_recebimento e total acumulado | N2-FIN-03 reproduz deslocamento entre meses; precisa movimentos individuais |
| KPIs, app:3209–3217 | Faturado acumulado a partir autos+adiantamento; aprovado por faturas; recebido soma cabeçalhos | Já há métricas diferentes com nomes próximos; ligar N-FIN-02, não supor toda métrica errada |
| Mapa/previsão, financial-map e fontes SQL | Projeções/mês/ajustes/fechos não equivalem automaticamente a ledger de recebimentos | Revisão da fonte e compatibilidade necessárias; não demonstrado erro real em todos mapas |
| SQL histórico autos_faturacao_aprovacao_pendente:19–23 | data_recebimento não NULL transforma estado em pago | Reaplicar pode fechar parciais já existentes; risco de manutenção N-SEC-02, não prova de execução real |
| Alertas | Tipos, valores e critérios variam; exemplos de faturacao no fluxo histórico | Não foi provado um alerta específico que perca o saldo. Exigir teste por origem/catálogo; não confundir alertas de fornecedores/subempreitadas com recebimentos cliente |

### Alternativas e recomendação

1. **Só integral temporariamente:** recusar valor diferente do saldo/integral no writer antigo. Reduz incoerência, mas bloqueia necessidades legítimas de parcelas; precisa decisão e não resolve movimentos históricos nem caixa mensal.
2. **Integrar RPC parcial existente (recomendação):** consolidar o contrato, migrar diálogo/consumidores e fechar ou compatibilizar o writer antigo sem bypass. Não criar segunda arquitetura de ledger. Por_pagar com recebido>0 pode representar parcial sem ampliar enum automaticamente; UI pode dizer parcial e saldo explicitamente.
3. **Novos estados/estornos/créditos:** só depois de regras aprovadas. Um estorno é movimento auditado, não delete de recebimento; definir excesso, crédito, moeda, precisão e diferença entre anular fatura e reverter dinheiro.

Validação prévia futura do ledger: unique request, autor/tenant, RLS/grants de leitura/escrita, arredondamento antes da positividade (valores inferiores ao cêntimo são um caso a testar), parâmetros esperados não silenciosamente inferidos e integridade de referências. A suite atual testa idempotência monetária; não aprova automaticamente a implementação para todos perfis.

Referências antigas com valor_recebido sem movimentos precisam inventário e reconciliação humana; **não gerar parcelas históricas por inferência**. Nunca deslocar dinheiro entre meses fechados automaticamente. Aceitação: saldo e estado derivados da mesma fonte; parcelas por data; mistura dos writers incapaz de divergir; todos consumidores e sessão/tenant testados.

## Conclusão

Três P1 preparados para correção futura; nenhum corrigido nesta fase. N-SEC-01 pode ser corrigido tecnicamente sem nova regra de negócio. N-FIN-01 precisa coordenação BD/Storage. N-FIN-05 precisa decisão explícita e integração do mecanismo existente. HR-38 e demais bloqueios preservados. **NO-GO para publicação/correção silenciosa; GO para planear tarefas controladas com os critérios deste pacote.**
