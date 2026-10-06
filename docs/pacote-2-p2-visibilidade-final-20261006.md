# Pacote 2 — fecho de visibilidade do legado e das pendências

Data: 06/10/2026. Implementação e validação exclusivamente locais/sintéticas.

## A–B. Base e auditoria preservada

- Base exata: `25303450f2d8afab97cb59ea521fd1d14f0a3c00`, `fix/pacote-2-auditoria-final-20261006`.
- Branch desta correção: `fix/pacote-2-p2-visibilidade-final-20261006`, criada diretamente na base, sem incorporar o commit da auditoria no produto.
- Auditoria preservada, sem alterações: `audit/pacote-2-correcao-final-20261006`, `a2688669d05af2b669fa84a7d8905a55858d64e8`. Push e `ls-remote` confirmaram esse SHA exato antes de iniciar.
- O SHA do commit que contém este relatório identifica a entrega; não se grava um hash autorreferente no próprio ficheiro.

## C–D. Legado-only alcançável e sem conversão

`fn_folha_contexto_v2`, quando há obra selecionada, usa a união de alocações explícitas, folhas V2 e `ponto_pessoal_obra` da obra/data. Cada origem é filtrada pela empresa e pela empresa do colaborador. A autorização da obra é verificada antes da união. Não há herança de última alocação, criação de dados, backfill ou escrita no reader.

O contexto acrescenta somente `legacy: boolean`. Não inclui intervalos, observações, justificações ou linhas completas do ponto antigo. Os detalhes continuam exclusivamente na allowlist auditada de `fn_folha_historico_v2`.

`folha_privado.linha` distingue:

| Evidência | Linha/estado | Escrita/retirada V2 | Resumo diário |
|---|---|---|---|
| Alocação apenas | Comportamento normal | Conforme permissões atuais | Ponto ainda não registado é pendência |
| Folha V2 apenas | Comportamento normal, mesmo sem alocação atual | Conforme permissões atuais | Derivado dos intervalos/carga |
| Legado apenas | REGISTO LEGADO; HISTÓRICO disponível | Bloqueadas | Facto existente; não cria pendência só pela idade/origem |
| Legado + V2 na mesma chave | LEGACY_CONFLICT / Regularização | Bloqueadas | Pendência |
| Legado de outra obra sem alocação/folha na selecionada | Não entra na lista da obra selecionada | Não aplicável | Não acrescenta linha |
| Legado de outra empresa | Não entra | Não aplicável | Não acrescenta linha |

O contador `registered` continua a contar V2 registado; legado é identificado na linha e conta como tratado para `pending/complete`. `revision=0` na linha sem folha significa ausência de revisão V2, nunca revisão do legado. Não é mostrado como revisão do ponto antigo. O histórico legado não recebe campo revision nem editor.

Uma chamada forjada de save/bulk continua recusada antes de criar V2. A guarda existente por pessoa/dia e a coordenação de locks com o writer legado continuam ativas. Não se ampliaram permissões.

Ao abrir HISTÓRICO: HISTÓRICO FOLHA V2 → Sem alterações registadas; REGISTO LEGADO → projeção original somente leitura. Nenhuma informação antiga é convertida em intervalos V2.

## E–F. Justificação pendente e DIA COMPLETO

A fonte é o campo existente `absence.estado`, projetado como `id/data/tipo/estado`; não foi criada outra coluna de estado. `ausente_pendente` passa a produzir o estado derivado de apresentação `absence_pending`.

- Cartão: Ausência · JUSTIFICAÇÃO PENDENTE, com o tipo original também identificado.
- Resumo backend e cliente: pending +1; complete=false; não aparece DIA COMPLETO.
- Ausência justificada/confirmada e férias confirmadas: tratadas, sem pendência fictícia.
- Trabalho + ausência: Regularização permanece; o indicador de justificação pendente não desaparece.
- Nenhum tipo de ausência é transformado automaticamente; não se altera estado na BD.
- Presente/completar/dia normal excluem qualquer ausência. Retirada continua recusada pelo backend e não aparece como ação para estas linhas.
- Legado-only também é excluído de ações coletivas e de retirada, com guardas adicionais no consumidor para não depender apenas da existência do botão.

## G–H. Varredura dos estados backend → cliente → UI

| Campo/situação | Apresentação e comportamento finais |
|---|---|
| absence.tipo | Tipo identificado; férias, falta injustificada e dois tipos de falta justificada não ficam achatados numa etiqueta genérica |
| absence.estado | Justificação pendente explícita; Justificada/Confirmada diferenciadas; pendente conta no resumo |
| Trabalho + ausência | Regularização com o indicador pendente, quando existente |
| conflict | Regularização; causa específica para legado+V2, alocações e guarda do writer legado |
| legacy | REGISTO LEGADO, histórico navegável, sem ações V2 e sem detalhe excessivo |
| overtime.estado | Potencial, validação administrativa pendente, regra financeira pendente e rejeitada conservam etiquetas próprias; superseded não é apresentado como HE atual pelo reader |
| special_day / pending_rule | Dia especial com regra pendente explícito; HE mantém regra pendente, sem cálculo financeiro novo |
| missing / open / regularization | Horas em falta / Em aberto / Regularização; continuam pendências operacionais |
| task report | Reportada vs confirmada continuam distintas; reportes confirmados permanecem mesmo sem tarefa ativa |
| férias administrativas | Lista passa a mostrar também o estado estruturado recebido, incluindo pendente ou confirmada |
| payroll pendências | Contador passa a incluir absences.state=ausente_pendente; estado mostrado em linguagem legível; pendências de dias/legado/dias especiais permanecem distintas |
| permissões e revisões | Preservadas; cliente mantém stale/replay e não inventa autorização/revisão para o legado |

Achados adicionais da mesma classe corrigidos nesta tarefa:

1. Contador de Vencimentos não contava justificação pendente, apesar de receber o estado: agora conta e mostra Justificação pendente.
2. Lista administrativa de Férias não mostrava `estado`: agora preserva essa distinção na apresentação.
3. O writer V2 já recusa ponto legado noutro local no mesmo dia, mas o contexto podia anunciar escrita/retirada disponíveis: `LEGACY_WRITER_BLOCKED` alinha capacidades e mensagem com a guarda existente. Não expõe UUID/obra/detalhes do outro registo, nem acrescenta pessoas só porque têm legado noutra obra.
4. A causa de conflito e o dia especial eram pouco explícitos na apresentação: etiquetas específicas, sem novos poderes ou regras económicas.

Não se encontrou outro estado funcional da classe focada devolvido e perdido, outra linha das três origens autorizadas sem caminho de histórico, pendência tratada como concluída ou estado resolvido tratado como pendente nos cenários preparados. Esta conclusão não é auditoria geral de todo o produto.

## I–J. Testes e regressões

- Execução integrada das 41 suites existentes + casos novos: **579 PASS / 0 FAIL / 3 SKIP**, 582 testes, 192,01 s.
- Core final após acrescentar o caso de writer legado noutro local: **98 PASS / 0 FAIL / 0 SKIP**, 12,01 s. Substitui os 97 casos core da execução integrada. Conjunto de casos distintos executados: **580 PASS / 0 FAIL / 3 SKIP**; não se soma o core completo de novo.
- Três SKIP RH preservados: runtime PostgreSQL cadastro/lote, formulário e aviso contratual. Não contam como PASS.
- Novo browser final: **126 grupos PASS / 0 FAIL**, Encarregado, Diretor, Adjunto e Administrativo; 1440/820/390 px; zero pageErrors; sem overflow horizontal no cenário pendente. Inclui histórico legado, ausência pendente/resolvida, férias, coexistência V2/legado, ausência+trabalho, horas em falta, HE, dia especial, exclusões coletivas e contadores administrativos.
- Browser Folha existente: 57 grupos PASS; consolidação: 51 grupos PASS, seis perfis/três viewports. Reexecutados após o último ajuste de apresentação administrativa.
- Browsers sessão, custos no Planeamento, Medicina, RH frontend, RNC, Viaturas e Quadro: PASS nas suites existentes. Sessão: 7 cenários; custos: 33 casos.
- Matriz A–AN, payload por perfil, quatro readers, replay após redução de papel/responsabilidade, domínios, allowlist/future column, Escritório, coletivo, externos, HE, férias, vencimentos, tarefas, concorrência/idempotência, Quadro, RH, Medicina, Financeiro, Planeamento, RNC, Viaturas e sessão: regressões locais PASS.
- Instalação/postcheck sintéticos, Fase B pós-hotfix e rollbacks locais: PASS. Nenhuma falha de arranque PostgREST na execução final.

Os testes sintéticos adicionados foram corrigidos durante preparação: sintaxe SQL/JSON do novo teste, campos obrigatórios da fixture, contrato de permissões e whitespace do DOM. Essas falhas iniciais não foram contadas como PASS; os resultados acima são das reexecuções finais. Uma substituição local por lote afetou indevidamente app/index durante a edição; foi revertida para os blobs da base e reaplicaram-se apenas os dois incrementos de cache, confirmados no diff antes da entrega.

Logs fora do Git: `%TEMP%/primeline-p2-full.log`, `primeline-p2-final-core.log`, `p2-final-*-browser.log` e `p2-*-browser.log`. Screenshots exclusivamente sintéticos: `%TEMP%/primeline-p2-visible-synthetic` (legado e pendente). Foram inspecionados visualmente o cartão pendente mobile e o histórico legado tablet; layout legível e sem sobreposição.

## K. Scripts

- `folha_ponto_v2.sql`: união autorizada de fontes, flag mínima, distinção legado/conflito, capacidades, resumo e guarda explícita de escrita sobre legado.
- `folha_ponto_v2_postcheck.sql`: guarda estrutural adicional do contrato de visibilidade instalado. Não substitui os testes funcionais.
- Precheck inalterado: as colunas usadas já integram a projeção obrigatória e a ausência de schema esperado aborta. Não há nova coluna/tabela/dependência de produção para acrescentar.
- Backup, gestão SQL e os dois rollbacks permanecem idênticos à base. Nenhum hash de catálogo real foi regenerado para satisfazer testes.
- Cache do frontend: app 182, Folha 5, domínio 4 e gestão da Folha 3. Demais módulos/imports intactos.
- `git diff --check`: PASS.

## L–M. Decisão e limites

**Os dois P2 conhecidos estão fechados localmente. Nenhum P0/P1/P2 conhecido permanece nesta classe após a varredura e os testes. GO LOCAL para reauditoria final focada.**

Não é autorização para rollout. Catálogo real não foi consultado por método bloqueado; não se executou SQL, alteração de dados/perfis, migration, main, deploy ou Fase B na produção. As regras ADM continuam desativadas conforme desenho aprovado. Escritas nos testes ocorreram somente em bases efémeras e mocks sintéticos.
