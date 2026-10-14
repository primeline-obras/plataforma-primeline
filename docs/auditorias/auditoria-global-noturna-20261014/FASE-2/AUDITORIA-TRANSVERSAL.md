# Auditoria transversal — Fase 2

## Critério de classificação

CONFIRMADO LOCAL = código executado com dados sintéticos ou regra explícita observada no corpo. HIPÓTESE = mecanismo possível sem caso executado completo/sem dados reais. PREPARADO = pacote de outra branch; não instalado nesta missão. Nada neste documento é confirmação de catálogo/produção.

Os 34 IDs originais continuam no CSV, sem renumeração. Descobertas novas são extensões/filhos, não substituem o backlog original.

## Novos achados comprovados

| ID | Gravidade proposta | Prova e condição | Relação / impacto | Próxima correção controlada |
| --- | --- | --- | --- | --- |
| N2-FIN-01 | P1, integridade | Handler real de fornecedor guarda cabeçalho em faturas; POST faturas_itens falha; mesmo assim marca saved=true e limpa formulário | Filho N-FIN-01; aprovação/preços podem operar sobre documento sem artigos esperados. Não foi demonstrado fluxo real de aprovação desse documento | Transação de cabeçalho+itens; manter exceção de duplicado aprovada; recuperação explícita |
| N2-FIN-02 | P1, integridade monetária | Parcial 100 pela RPC com ledger +900 pela RPC antiga → valor_recebido 900/pago e ledger 100 | Filho N-FIN-05; APIs coexistentes não têm uma fonte coerente do dinheiro recebido | Integrar contrato existente, impedir sobrescrita e fechar caminho antigo compativelmente |
| N2-FIN-03 | P1, relatório financeiro | Duas parcelas 100 outubro +900 novembro → cabeçalho acumulado 1000/data novembro → helper caixa atribui 1000 novembro | Filho N-FIN-05; calendário de recebimentos distorcido mesmo com parcelas corretas | Consumir movimentos por data; inventário de legado; não preencher ledger por inferência |
| N-SEC-01 ampliado | P1, segurança | Novos renderers paidFinanceRow/renderInvoices/renderMeasurementsTab/renderWorkDetail/toast executam marcador | Família já existente; inclui mensagens e leitura após pagamento, não apenas três telas originais | Correção contextual de saída e regressão dos oito renderizadores |

As três provas financeiras usam objetos sintéticos. N2-FIN-02/03 dependem da disponibilidade da RPC parcial descrita no Git; não se afirma que um utilizador real tenha acionado essas combinações. A gravidade proposta aplica-se ao contrato preparado, e a causa merece ser fechada antes da futura publicação desses fluxos.

## Outros escritores e documentos

| Fluxo | Sequência observada | Classificação | Limite / proposta |
| --- | --- | --- | --- |
| Faturação cliente | Cabeçalho → links → upload → documentos → UI | CONFIRMADO HTTP/VM, N-FIN-01 | Três sistemas: BD, Storage, cache. Transação BD não abrange bytes |
| Fatura fornecedor nova | PDF → cabeçalho → artigos | CONFIRMADO no código; falha dos artigos reproduzida | Upload antes de cabeçalho pode deixar bytes; não comprovado órfão real |
| Edição fornecedor | fn_editar_fatura_pendente recebe campos e artigos | RPC centralizada já existente | Não impor outra API antes de auditar esta; autorização/atomicidade completa não reexecutada nesta fase |
| Vínculo fornecedor/subempreitada | RPC fn_vincular_fatura_subempreitada | Fonte explícita de vínculo | Validar fornecedor/obra/empresa na mesma transação; não associação por nome |
| Anexos fornecedor | loop upload + insert faturas_anexos, app:5827/5871 | ORDEM CONFIRMADA; erro do segundo pode deixar primeiro gravado | Parcialidade de anexos é aceitável somente com relatório de itens concluídos/pendentes; não apagar os anteriores silenciosamente |
| Documentos de obra | upload + POST documentos_obra, documents:219–227 | ORDEM CONFIRMADA; associação falhada tratada como erro | N-DOC-01; intenção/finalização/recovery com entidade e tenant |
| Comprovativo de ausência | upload + POST ausencias_anexos, app:2678+ | ORDEM CONFIRMADA | Facto de ausência e documento têm autorização própria; não transformar upload falhado em falta/horas |
| RNC/evidências | operação e anexos por APIs do módulo | RISCO DE PARCIALIDADE A INVESTIGAR | Não há caso completo de falha reproduzido nesta fase |
| Agenda | RPC fn_guardar_compromisso recebe participantes | Não demonstrada nova falha de atomicidade | Não equiparar toda UI com vários dados a vários commits; ler corpo/ACL específico antes de propor alteração |

## Estados financeiros, integração e histórico

1. `renderMeasurementsTab` confia em estado pago OR saldo recebido>=valor. A Visão Geral Financeiro calcula saldo monetário e continua a mostrar por receber. **Divergência entre consumidores confirmada no código**, não defeito em toda vista.
2. `actualCashFlowByMonth` é helper genérico: faturas de material na chamada real são filtradas pago em production-dashboard:1107. O fallback data_fatura não prova que a query atual inclua materiais não pagos. Evitar falso positivo.
3. DUPLO MATERIAL N-FIN-04 continua hipótese de fontes reais: dois valores iguais não provam mesmo facto. Exigir ID de origem, FK, categoria, estado e reconciliação.
4. `totalClientBilling` inclui draft e adiantamento. Medido/faturado/recebido são contratos diferentes; Q05 precisa fechar a semântica. Não reescrever salário ou avaliação diária para resolver um indicador de obra.
5. Reaplicação do SQL histórico de faturação pode interpretar qualquer data_recebimento como integral. N-SEC-02/03: manifest e fingerprints de função/policy/column grants, não execução por ordem alfabética.
6. RPC parcial já tem lock, request e expected total; documentar o que existe antes de propor ledger novo. Imutabilidade de movimentos é intenção do comentário/corpo INSERT; **grants/policies que impedem UPDATE/DELETE real não foram provados** nesta fase.
7. Histórico separado por etapas pode registar operações incompletas, mas isso é evidência legítima de tentativa, não lixo a apagar. Operação composta deve identificar sucesso/falha/recuperação pelo mesmo ID sem eliminar trilho.
8. Frontend `openPaymentDialog` ignora o corpo de sucesso da RPC e aplica estado próprio. `advanceInvoiceFlow` também sobrepõe estado pretendido depois de Object.assign; nenhuma divergência concreta adicional foi reproduzida ali. Tratar como candidato a regressão, não P1 confirmado.

## Autorização económica

- As duas RPCs examinadas têm sessão ativa, papel financeiro e autorização da obra no hotfix do Git; callbacks de testes monetários são stubs. Não reapresentar essa suite como auditoria cross-tenant.
- Leitura de custos técnicos agregados HR-29 é regra aprovada; HR-38 é inferência já provada na auditoria anterior. Limite mínimo/ocultação temporal não foram aprovados e não foram aplicados.
- Empresa fixa nos payloads de documentos continua N-ADM-09; RLS pode recusar. Não há prova nova de escrita/consulta cruzada.
- Policies true em scripts antigos são risco de manutenção, não políticas atuais confirmadas. Nenhuma consulta ao Supabase ocorreu.
- Gestão é superutilizador funcional, mantendo tenant/auditoria/concorrência. Gerência é avaliada separadamente. N-ADM-07 já tem regra suficiente para preparar correção UI; não precisa rediscutir a Gestão.
- DD-TENANT e Fase B continuam pacotes distintos preparados. Nada os instalou/reabriu nesta auditoria. Precheck DD real PASS é evidência histórica fornecida pela utilizadora, não gate executado agora.

## Conteúdo livre e renderização

O inventário lexical cobre também ficheiros PDF/Excel/importadores/legado. Renderização HTML pode pertencer a browser, exportação ou string de consulta; cada contexto deve ser separado. Foram inspecionados documentos de obra, histórico financeiro e do Quadro, comentários de ausências, drawer de alertas, RNC e Agenda.

**Protegidos nos controlos:** documento, observação de histórico, título/descrição de alerta e caracteres legítimos. **Candidatos ainda não certificados:** teamData.error cru; título de férias sem escape; estados/classes fora de enums; exportações e todos os 1.206 candidatos não seguidos por taint completo. RNC/Agenda usam esc nos textos principais, mas isto não certifica todos estados/atributos. Não prometer um scan exaustivo semanticamente a partir de regex.

## Propostas independentes que podem avançar depois de autorização

- Escaping contextual / toast textual: prioridade imediata, não muda regras de acesso.
- Manifest de scripts e dependências: prioridade anterior a qualquer instalação, não consome gate real.
- Data civil Lisbon e paginação/completude: correções técnicas próprias, sem FP28/29.
- Núcleo transacional de faturas: coordenar documento e contrato; não misturar backfill.
- Recebimentos: uma única fonte, adaptação de consumidores e fechamento compatível do writer antigo; decisões Q04/Q05 antes da alteração funcional.

Não houve evidência nova de P0, nem certificação de ausência de P0/P1 nas áreas não exercitadas. **Produto preservado; falhas conhecidas continuam abertas.**
