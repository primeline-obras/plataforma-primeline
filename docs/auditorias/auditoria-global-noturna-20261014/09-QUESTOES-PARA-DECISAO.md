# Questões reunidas para decisão

Não são pedidos de resposta durante a missão. Nenhuma ausência de resposta foi tratada como autorização. Alternativas abaixo são propostas, não implementação.

| ID | Questão / por que precisa decisão | Alternativas | Recomendação | Dependências |
| --- | --- | --- | --- | --- |
| Q01 | Fonte definitiva da tabela-padrão por função/nível: evita inferência RH sem perder mapa | Orçamento aprovado; tabela empresa; referência comercial externa autorizada | Fonte explicitamente aprovada por empresa, separada da tarifa RH | HR38/40/41/42; ainda não implementar |
| Q02 | Aprovador/vigência da tabela-padrão e função de valorização: cargo formal/login não são iguais | RH/Administrativo; Gestão; responsável financeiro; classificação própria | Aprovação/revisão históricas e função/nível explícitos; nunca inferir | Q01; snapshots |
| Q03 | Que valor e estado técnicos recebem quando falta padrão? | NULL/pendente; faixa; não mostrar custo | NULL/pendente mínimo; sem fallback tarifa RH ou zero | Q01; privacidade |
| Q04 | Recebimentos parciais, excesso, estorno e saldo | Só integral; ledger de prestações; crédito/adiantamento separado | Ledger append-only de recebimentos com saldo/estado derivado, revisão e auditoria; regra de sobrepagamento explícita | N-FIN-05; não escrever valores reais |
| Q05 | Métrica “Faturado”: auto medido, emitido/aprovado ou recebido? | Manter indicador renomeado; decompor fontes | Separar medido/aprovado/faturado/recebido/adiantamento; evitar contar draft como fatura | N-FIN-02; autos/faturas |
| Q06 | Zero efetivo de venda/custo é valor legítimo ou ausência histórica? | Zero legítimo; sentinel legado; não permitido | Valor zero explícito e NULL para desconhecido se funcionalmente permitido; reconciliar legado antes | N-FIN-03; sem backfill automático |
| Q07 | Revogar aprovação de TEE com execução já feita | Apagar tarefa; suspender futura execução; manter com exceção | Preservar factos e sinalizar autorização suspensa; definir execução excecional/regularização | N-FIN-06; obra128 |
| Q08 | Base IVA/moeda/unidade de custo real, margem e caixa | Sem IVA; com IVA; dois indicadores | Separar base de custo/margem e tesouraria; taxa desconhecida não copiar total | N-FIN-08 |
| Q09 | Distribuição mensal de compromissos | Mês início; medições; proporcional; cronograma aprovado | Cronograma explícito por origem; manter mês fechado histórico, sem presumir distribuição uniforme | TEE/SUB/Planeamento |
| Q10 | Fonte contratual vigente por obra | Heurística atual; versão/data explícita | Revisão/vigência/autoria explícitas, fonte única para todos os mapas | N-FIN-07 |
| Q11 | Visibilidade comercial de preços para Encarregado | Só própria obra; histórico same-tenant; preços padrão | Capability read-only específica e DTO mínimo; partilha interobra precisa aprovação | N-FOR-01; RLS atual |
| Q12 | Qual tipo de preço publicado e comparabilidade? | Proposto; adjudicado; faturado; misto com tags | Primeiro histórico identificado; unidade/base/condições/data; sem compra autorizada | N-FOR-03; qualidade |
| Q13 | Quem garante cadastro/prices e tratamento de duplicados? | Automático por nome; revisão humana + prova/FKs | Revisão humana com NIF/ID/relacionamentos; não mesclar por nome sozinho | Dados reais não vistos |
| Q14 | Valor final cliente da administração direta na 128 | Fixo; recurso×preço; custo+regra; unidade | Aplicar apenas regra contratual demonstrada, aprovador/limite/revisão explícitos | 06; Q01/Q04/Q08 |
| Q15 | Consumo material/equipamento e apropriação de horas a TEEs | Copiar ponto; lançar recursos independentes; referenciar facto único | Apropriação de factos existentes sem duplicação; compras/entregas/consumo diferentes | Folha; stock; unidades |
| Q16 | Aprovação comercial vs técnica e faturação por artigo | Uma validação geral; etapas e fingerprints | Etapas distintas, correção invalida etapa dependente; auto não duplica artigo/quantidade | N-FIN-01; obra128 |
| Q17 | Email: necessário canal de entrega agora? | Alertas in-app; SMTP/worker; serviço autorizado | Fechar responsável/destinatários/entrega/auditoria antes de chamar enviar_email de envio | N-ADM-11; sem acesso externo |
| Q18 | RNC Gestão e capacidade da Gerência | Aprovação funcional existente Gestão; redefinir Gerência | Aplicar regra já aprovada superutilizador Gestão, manter tenant; Gerência separada | N-ADM-07; correção futura |
| Q19 | Orfandade bytes/metadata e uploads parcialmente concluídos | Compensação; pending state; reconciliação humana | Estado pendente + ligação confirmada + reconciliador autorizado; não apagar sem prova | Documentos; N-FIN-01 |
| Q20 | Formalizar rollout/compatibilidade e dados históricos | SQL avulso; manifest/stages versionados | Manifest com baseline/hash/dependências; catálogo READ ONLY em tarefa autorizada | N-SEC-02/03; FaseB/Financeiro preparados |

## Questões técnicas sem decisão de negócio nova

Escapar saída HTML (N-SEC-01), data civil Lisbon consistente (N-ADM-08), paginação/resultado parcial, request_id de operação e estados de erro não alteram preços/permissões por si. Ainda assim não são implementados nesta missão, porque foi autorizada análise/documentação/testes exclusivamente. Preparar tarefas focadas com regressões antes de qualquer rollout.

## Decisões já tomadas — não reabrir

Custos-padrão independentes de RH aprovados em princípio; RH individual confidencial; Administrativo autorizado pode aprovar valor individual. Cargos contratuais e perfis operacionais separados. Folha V2/equipa persistente/external/multiobra já desenvolvidos; Gestão de Horas nova já desenvolvida localmente. FP-28/29 standby. Sem HE monetária, sem exportador salarial novo, sem calendário clicável Plano de Ação, sem redesign Quadro, sem FaseB real nesta missão.
