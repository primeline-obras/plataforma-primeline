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
