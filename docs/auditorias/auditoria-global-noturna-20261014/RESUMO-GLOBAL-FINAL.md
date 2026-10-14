# Primeline GO — resumo global da auditoria noturna

## Resultado e âmbito

Fases 1/2 preservadas; entregas das Fases 3–7 preparadas, com **cobertura funcional parcial explicitamente medida**. A missão não certifica toda a plataforma ou produção.

Produto, SQL funcional e permissões inalterados. Sem SQL hospedado, push, merge, deploy, Cloudflare, credenciais ou dados pessoais reais.

Branch: codex/auditoria-global-noturna-20261014.
Base: f72686cfdc4f61514a86851aa18de7976242ca56.
Checkpoints locais: 767d301 → 1eab4b6 → 21b2f89 → consolidação final.
SHA final na entrega/HEAD. Worktree conferida no encerramento; repositório principal preservado.

## Verificado e limites dos denominadores

- 38 áreas revistas por lacunas específicas; os dez eixos não representam 380 provas aprovadas.
- 20 percursos/casos end-to-end com writers, leitores e fronteiras de fixtures identificados.
- 32 operações críticas/256 pares de perfil: 32 capabilities frontend executadas, 21 pares com prova DB, 203 pares backend apenas revistos estaticamente.
- 520 candidatos data-* e 218 referências API não equivalem a operações completas.
- 30 relações de fontes de verdade; 575 declarações SQL, 1.713 chamadas qualificadas, 2.020 candidatos DDL e 136 nomes repetidos em 370 ocorrências de conflito. Não representam o catálogo instalado nem toda sintaxe SQL.

## Novos problemas comprovados

1. **TEMP-P3-C01 — P2 proposto:** trocar da obra A para B durante o carregamento de Compras pode manter consultas de A sob contexto B. Função real procurement.load executada em VM. Sem bypass entre empresas demonstrado.
2. **TEMP-P3-C02 — P2 proposto, N-FOR-05/02:** um item cujo cabeçalho de fatura não é devolvido aparece sem aviso de origem incompleta. Ausência sintética; causa real por RLS/paginação não investigada.

Sem códigos oficiais novos do Backlog Mestre.

## Problemas anteriores aprofundados

P1 de HTML, faturação não atómica, recebimentos, filhos N2 e HR-38 permanecem abertos. Novo efeito nos consumidores: receber 100 de 1.000 mostra PAGO e retira a ação de receber o restante, enquanto a Visão Geral ainda calcula saldo 900.

TEE recusado retira previsão mas mantém tarefa, N-FIN-06. SQL histórico permissivo reabriu leitura numa fixture depois da policy segura; rollback restaurou. É prova de ordem local, não exposição atual da produção.

## Comportamentos corretos

Folha/Equipa preservou preview sem escrita, revisão, idempotência, concorrência, tenant e recusa após inativação. FALTOU chegou ao mapa/classificação/história mensal sem horas inventadas. Correção de 480 para 240 minutos chegou à conferência sem criar Vencimentos.

Cadastro RH real criou contrato, alocação explícita e auditoria. Lote com segunda linha inválida fez rollback da primeira alteração e auditoria. Mesmo conteúdo não duplicou audit. Oito perfis RH distinguidos.

Reporte Encarregado não conclui oficialmente. Diretor/Adjunto validam; Preparador não confirmou. O trigger tarefa_concluida liga a conclusão autorizada no Planeamento à confirmação e resolução de alertas: ausência de literal task_confirm não prova backend órfão. Meses fechados preservados; cotação, adjudicado, desvio e margem distintos.

## Resultados finais

| Bloco | PASS Node | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| Harness RH/tarefas, 7 casos novos | 299 | 0 | 0 |
| Financeiro/consumidores/ordem SQL | 9 | 0 | 0 |
| Compras/sessão/Planeamento | 29 | 0 | 0 |
| Capabilities dos oito perfis | 8 | 0 | 0 |
| Cadastro/import RH | 5 | 0 | 0 |
| **Total destas execuções** | **350** | **0** | **0** |

236 da Fase 1 e 42 da Fase 2 preservados, não somados como cobertura única. Grupos pai incluídos no contador Node. Teste que passa ao demonstrar falha é FALHA/VULNERABILIDADE REPRODUZIDA, nunca aprovação de segurança. Validações posteriores dos artefactos são contadas separadamente.

## Hipóteses e não executado

Metadata órfã numa fixture sem triggers reais é hipótese. Não provados órfãos/duplicados reais, contrato da Obra 128, limites REST, RLS/ACL/owners atuais, CSP, SMTP ou Storage/Auth hospedados.

Não ligados integralmente: adjudicação SQL → documentos → fatura; batch Planeamento → todos indicadores; cadeias completas de Medicina, Viaturas, RNC, Salas, Imóveis e Pedidos. Matrizes identificam 203 pares backend não executados e 38 lacunas específicas.

Não houve bloqueio de proteção essencial às suites locais concluídas. Proibição de produção respeitada, sem contorno. Scanner lexical não prova ausência de outros defeitos; nenhuma exploração HTML nova necessária.

## Decisões e dependências

Q01–20 preservadas: fonte/aprovador/vigência do padrão HR-38; parciais/excesso/estornos e nomes financeiros; zero/NULL, IVA, contrato vigente, distribuição temporal, recusa TEE, recovery/retensão documental e regras da Obra 128.

HR-27/30/31/41 não reabertos. Custo-padrão operacional tem só aprovação de princípio; FP-28/29 em standby.

Refs locais de Débitos/Fase B coincidem com SHAs anteriores, mas possuem respetivamente dois e um commits ausentes desta base. Ver FASE-6/BRANCHES-PREPARADAS.json. Sem integração nem remoto consultado; precheck anterior PASS não autoriza instalação. Testes no outro computador exigem runtimes locais documentados.

## Prioridades e próximo passo

1. Saída HTML e manifesto de scripts numa tarefa autorizada.
2. Atomicidade de faturas e integração de receipts/consumidores após Q04/05.
3. Invalidar carregamento por obra e explicitar proveniência de preços, sem novos acessos.
4. Fechar decisões HR-38 sem expor RH individual ou alterar permissões silenciosamente.
5. Escolher lacunas concretas para novas regressões integradas.

**NO-GO para publicação dos circuitos com P1 aberto.** Provas prontas para revisão e preparação de correções autorizadas.

CONSOLIDACAO-PARA-BACKLOG preserva 34 IDs e cinco extensões temporárias, três anteriores e duas novas: 39 registos, não 39 bugs independentes. Nenhum item histórico apagado ou marcado corrigido automaticamente.
