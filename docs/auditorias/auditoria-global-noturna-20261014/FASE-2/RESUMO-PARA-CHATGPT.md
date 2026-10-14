# Resumo para ChatGPT — Auditoria noturna Fase 2

## Conclusão

Fase 2 concluída localmente, produto inalterado. Os três P1 estão aprofundados e preparados para futura correção controlada; **continuam abertos**. Nenhum SQL real, Supabase, push, merge, deploy, alteração de permissões ou dados pessoais reais foi usado.

Base auditada: `439b1e3b900a8d5b919062cf8efd1f05868e494a`, branch `codex/auditoria-global-noturna-20261014`. Produto funcional `2ae1f8a194f23d77bf0692d0a6d586566227298c`. SHA final consultável com git rev-parse HEAD; RETOMA identifica o commit final e a sequência sem criar autorreferência impossível.

## Principais descobertas

1. **HTML P1 ampliado:** oito renderizadores afetados entre provas preservadas e novas. Novos: fila de faturas, pagas, autos, detalhe da obra e toast. Documentos, comentários do histórico financeiro e drawer de alertas ficaram protegidos nos controlos. Escapar saída preserva texto legítimo; não exige alterar regra de negócio.
2. **Faturas não atómicas:** cliente persiste cabeçalho antes de autos/PDF/metadata; falhas deixam estados parciais e timeout/retry não recupera operação. Fornecedor também mantém cabeçalho sem artigos e limpa formulário quando os artigos falham (N2-FIN-01).
3. **Recebimentos:** RPC parcial/ledger já existe no SQL do hotfix, mas a UI chama a antiga. Não propor outro ledger antes de auditar/integrar o existente.
4. **Mistura de writers (N2-FIN-02):** parcial 100 + antiga 900 cria documento 900/pago com ledger 100. Contrato incompatível, reproduzido em PostgreSQL sintético.
5. **Caixa mensal (N2-FIN-03):** parcelas outubro100/novembro900 viram outubro0/novembro1000 no helper que usa acumulado/data final. Consumir movimentos por data.
6. **HR38 preservado:** custo-padrão separado de RH aprovado em princípio; fonte/aprovador/vigência e apresentação sem referência precisam decisão. Não alteradas permissões HR29 nem imposto limiar de trabalhadores.

## Evidências

- **37 PASS / 0 FAIL / 0 SKIP** nas duas suites novas. Reprodução que passa é prova de falha, não fecho.
- 236 PASS anteriores preservados; não reexecutados.
- Browser origem null, rede bloqueada, zero requests. PostgreSQL17.6 local com duas conexões e helpers de autorização sintéticos. Não prova catálogo/ACL/Auth hospedado.
- 56 JS /183 sinks lexicais /1.206 candidatos, com limites de análise explícitos; não garantia semântica exaustiva.
- `VERIFICACAO-PACOTE.json` regista separadamente integridade de originais/produto, CSV e completude documental.

## Backlog e decisões

Todos os **34 IDs** mantidos no CSV com critérios específicos, testes, dependências, independência e risco. Descobertas N2 são extensões relacionadas, não renumeração. Ordem completa no plano.

Todas as **20 questões** revistas: 10 bloqueantes para suas frentes, 6 podem aguardar, 2 resolvidas quanto ao núcleo técnico/regra, 2 carecem de evidência. Q18 Gestão superutilizador já está decidida; Gerência separada. Q20 manifest é engenharia; SQL real continua exigindo autorização. Q19 núcleo recovery é técnico, mas retenção/PDF obrigatório precisam regra.

Decisões prioritárias: Q01–03 custos-padrão; Q04–05 recebimentos/indicadores; Q10/Q08 fonte/base fiscal; Q07 revogação TEE. Preços do Encarregado/administração direta128 são futuras frentes, sem concessão de acesso implícita.

## Propostas e próximos passos

Autorizar separadamente correção contextual HTML; manifest/baselines; transação de fatura/linhas e pending/finalize de Storage; integração das duas APIs de recebimento e movimentos nos consumidores. Não reconstruir parcelas históricas ou apagar órfãos sem proveniência. Reutilizar pacotes DD-TENANT/Fase B preparados, não instalar nesta missão.

**NO-GO para publicação; GO para revisão das decisões e preparação de tarefas de correção.** Nenhuma alteração funcional foi implementada. FP28/29 continuam standby.
