# Reconstrução urgente — 28/09/2026

Base verificada antes de qualquer edição: branch `urgent/planeamento-operacional-20260928`, SHA `9fc99425a940bc32d59343ee9cd7bde590878d36`, Git limpo.

## Fontes e limites

Contexto e três snapshots fornecidos em Downloads, lidos integralmente. O schema de julho não é fonte atual. Nenhum SQL, deploy, merge ou backfill é autorizado nesta sessão. `instrucoes.txt` limita o repositório a frontend, sem geração de migrações. RPCs novos abaixo são requisitos de backend, não funcionalidades instaladas.

## Auditoria

- `planning.js`: PATCH/reload por tarefa, DELETE de tarefas, importação não atómica e média simples quando faltam pesos.
- `production-dashboard.js`: trata mês passado como fechado e usa fim operacional como contratual.
- `app.js`: criação de faturação e ligações aos autos em pedidos separados; pagamento substitui valor/data e marca integralmente pago.
- `xlsx-operational-import.js`: fase vazia atribui F01; TEEs existentes ficam excluídos por omissão. RPC atual apenas insere, sem revisões.
- `financial-map.js`: previsão baseada em margem/duração, sem decomposição em estágios; consulta transversal com select=*.
- Schema: `fases.peso_percentual` existe; arquivo de tarefas, datas contratuais separadas, reconciliação e movimentos por fatura não constam dos snapshots.
- Triggers de TEE/subempreitada concentram previsão no mês inicial. Trigger de aprovação TEE recalcula venda efetiva independentemente de reconciliação. Não ativar novo motor de gravação enquanto estes efeitos não forem coordenados.

## Itens TEE

Pesquisa em src/tests/supabase: frontend não lê/escreve diretamente `itens_tee` nem `alteracoes_tee_itens`. Os ficheiros `supabase/importacao_xlsx_operacional.sql` e `supabase/tees_aprovacao_cliente_unica.sql` escrevem na segunda tabela. O snapshot confirma que autos referenciam a primeira. Não copiar IDs entre tabelas nem substituir itens medidos.

Estratégia: manter itens importados/revisões separados dos itens medidos; futura correspondência explícita, validada por obra e TEE, com autor/data e identidade das duas tabelas. Não há evidência para converter histórico automaticamente.

## Blocos

- A: helpers e testes de pesos, progresso, datas, arquivo e preview da cascata.
- B: edição em lote e adaptação a RPC transacional; proteção contra saída e conflitos.
- C: Dados da Obra e datas contratuais.
- D: composição contratual e reconciliação explícita.
- E: índice TEE/revisões, sem inferir itens medidos.
- F: movimentos parciais e atualização dos saldos.
- G: estados explícitos por competência.
- H: motor mensal e detalhe das origens.
- I: recálculo após planeamento, preservando histórico.
- J: UI e regressões.

## Dependências de backend

Persistência de arquivo, lote atómico, revisões e parcelas exige evolução do backend. Não substituir atomicidade por vários PATCHs nem simular sucesso quando a RPC faltar. A validação em PostgreSQL permanece não executada por instrução do utilizador. O novo motor não pode somar agregados legados às mesmas origens.

## Estado dos blocos A e B

A: helpers implementados e 12 testes aprovados. Commit `e0cecde`, sincronizado na branch urgente.

B: frontend de lote, preview, arquivo local com motivo, redistribuição explícita, dependências locais, proteção de saída e importação para o lote implementados. Não há DELETE/PATCH de tarefa neste fluxo. 25 testes unitários/regressão e um cenário de navegador offline aprovados. A atomicidade real permanece pendente do backend.

### Protocolo proposto: fn_guardar_planeamento_lote

O cliente envia `p_lote` (version=1, obra_id, changes com apenas campos alterados, expected_items, dependencies, expected_dependencies, archive_reason e approved_cascade). `p_confirmacao=null` pede preview sem mutações. Resposta: version=1, confirmation_token, conflicts e approved_cascade. A confirmação envia exatamente o mesmo lote e o token; só `committed=true` é sucesso.

Requisitos do servidor antes de ativar:

- Autenticação, autorização por obra e validação de todas as referências; nunca confiar nos campos derivados enviados.
- Token vinculado ao utilizador, obra, conteúdo e versões lidas, com expiração; comparação/locks para rejeitar concorrência. Repetição idempotente.
- Validar pesos, datas, ciclos, arquivo e cascata sobre o estado final inteiro; proteger datas manuais. Uma só transação mesmo com processamento interno de 200–500 linhas.
- Arquivo com autor/data/motivo, sem apagar custos ou histórico. Preservar baseline e relações financeiras.
- Coordenar o trigger existente de cascata para não aplicar efeitos fora do preview. Conclusão de custos e atualização de resumos dentro da mesma transação.
- Recalcular períodos afetados e apenas previsão aberta/futura; preservar autos aprovados, meses fechados e movimentos reais. Devolver resumo atualizado.
- Leitura de arquivo deve ser exposta pelo mesmo contrato de backend antes da ativação. O snapshot atual não tem esse campo.

O frontend recusa RPC ausente, resposta incompleta ou cascata diferente. Não afirmar que este protocolo já existe na BD.

## Bloco C — apresentação dos dados da obra

Painel recolhível com início, finais contratuais inicial/atual, final operacional, execução ponderada, prazo consumido e desvios. Resumo da obra e dashboard deixam de usar a previsão operacional como prazo contratual. Prazo desconhecido aparece sem percentagem; prazo ultrapassado mantém valor superior a 100% (a barra é limitada visualmente).

As consultas continuam a usar apenas colunas existentes. Como os snapshots não têm as datas contratuais, estas ficam não configuradas. Edição e persistência dessas datas dependem de extensão do backend; não foram simuladas com campos de baseline nem com a previsão operacional. Pesos globais em falta mostram aviso e execução indeterminada.

## Bloco D — proteção da composição legada

Dashboard, reunião e RSP deixam de somar novamente TEEs aos totais efetivos legados. O mapa distingue TEEs informativos do resultado reconciliado, que permanece vazio. Valores efetivos iguais a zero são preservados; o helper mantém ausência como ausência. Resumo da obra e composição apresentam o aviso de histórico por reconciliar.

Não existe fonte de reconciliação nos snapshots: não se infere esse estado nem se habilita reconciliação local. Contrato original, movimentos de escopo, ajustes financeiros e auditoria de reconciliação precisam de suporte persistente antes de ativar a composição oficial. Nenhum registo histórico foi criado ou alterado, incluindo Obra 120.

## Bloco E — preview TEE e revisões

`tee-index.js` compara números normalizados dentro da obra, produz NOVO/VAI ATUALIZAR/SEM ALTERAÇÃO/BLOQUEADO, preserva células vazias e calcula margem. Importador detalhado usa essa comparação, remove F01 por omissão, deteta duplicados e itens sem cabeçalho, mostra campos alterados e sinaliza aprovados por programar. O formato consolidado autónomo ainda precisa de UI/modelo próprio; o helper comum já está disponível.

Persistência proposta: `fn_importar_tees_revisoes(p_version=1, p_obra_id, p_linhas, p_nome_ficheiro)`. Cada linha contém ID existente, snapshot esperado e mudanças esparsas; itens ausentes preservam os atuais. Exigir autorização por obra, concorrência, snapshot imutável da revisão anterior, histórico com utilizador/data, idempotência e transação única. Só resposta version=1/committed=true confirma sucesso. A RPC não consta dos snapshots e não foi instalada; não há fallback para a importação antiga. Estado operacional precisa de campo próprio, mantendo o mapeamento de aprovação cliente. Não reatribuir IDs de itens medidos nem criar tarefas com datas de envio/resposta.
