# PRIMELINE GO — MISSÃO NOTURNA DE VALIDAÇÃO PROFUNDA

## Objetivo

Transformar as descobertas das Fases 1–7 em **provas executáveis de funcionamento e autorização**, privilegiando os 203 pares ação/perfil que ficaram sem execução backend.

Esta missão NÃO é outro levantamento documental.

A entrega principal deve ser composta por testes reais em ambientes sintéticos descartáveis, fixtures reproduzíveis e evidências dos resultados.

Trabalhar autonomamente, sem interromper a utilizadora para decisões.

## 1. Ponto de partida

Repositório: `primeline-obras/plataforma-primeline`

Branch de auditoria:
`codex/auditoria-global-noturna-20261014`

Checkpoint:
`63f98ddff6ca96e0c89dd0d4125d85a4d29f12b3`

Confirmar HEAD, branch, remoto e working tree.

Preservar as Fases 1–7.

Criar uma branch/worktree isolada para esta validação. Não alterar a implementação do produto, a main nem a branch funcional de Gestão de Horas.

Consultar os ficheiros produzidos nas auditorias anteriores, especialmente a matriz de ações/perfis, a lista dos 203 pares não executados e os planos de correção.

## 2. Reconciliação dos 203 pares

Antes dos testes, verificar a natureza de cada par.

Classificar como:

- Aplicável e autorizado.
- Aplicável e proibido.
- Não aplicável àquele perfil.
- Contrato incompleto.
- Dependente de ambiente indisponível.
- Já coberto por prova dinâmica existente.

Não assumir que todos os 203 requerem o mesmo teste nem criar testes artificiais para ações inexistentes.

Para cada combinação aplicável, identificar o contrato backend, a condição de autorização e o comportamento esperado.

## 3. Criar uma suíte parametrizada de validação

Desenvolver infraestrutura LOCAL de testes capaz de percorrer automaticamente a matriz de ações e perfis.

Reutilizar o PostgreSQL/PostgREST sintético já utilizado nas auditorias anteriores, quando adequado.

Utilizar pessoas, empresas, obras, faturas e documentos exclusivamente sintéticos.

Testar, conforme o tipo de operação:

### Leitura autorizada

Verificar que o perfil autorizado recebe apenas o conteúdo permitido e que o DTO não contém campos confidenciais inesperados.

### Leitura proibida

Verificar que um perfil sem autorização não recebe os dados, incluindo consultas de outra obra, empresa ou responsabilidade.

### Escrita autorizada

Executar a operação num ambiente descartável e verificar:

- Estado anterior.
- Escrita efetiva.
- Estado posterior.
- Histórico criado.
- Revisão.
- Resposta da API.
- Consumidores afetados.

### Escrita proibida

Confirmar que a operação é recusada e não produz alterações parciais, incluindo no histórico.

Não utilizar atalhos de permissão ou mocks de autorização para fabricar resultados positivos.

## 4. Cobertura por perfil

Percorrer os perfis reais:

- Gestão da Plataforma.
- Gerência.
- Administrativo.
- Financeiro.
- Diretor de Obra.
- Adjunto.
- Preparador.
- Encarregado.

Incluir também variações relevantes:

- Utilizador inativo.
- Responsabilidade revogada.
- Obra não autorizada.
- Outra empresa.
- Registo inexistente.
- Revisão desatualizada.

Agrupar testes quando vários pares partilharem exatamente o mesmo contrato e a mesma regra, mas preservar evidência identificável para cada combinação coberta.

Não alterar permissões do produto.

## 5. Prioridade de execução

Executar primeiro os pares aplicáveis ligados a:

**Prioridade A — Segurança e financeiro**

Faturas, recebimentos, autos, aprovações, pagamentos, custos, documentos financeiros e alterações económicas.

**Prioridade B — Administrativo/RH**

Cadastro, contratos, documentação, férias, faltas, conferência mensal, permissões e viaturas.

**Prioridade C — Equipa técnica**

Obras, Planeamento, TEE, tarefas, documentos, alertas, preços e subempreitadas.

**Prioridade D — Operação**

Encarregados, equipas, Folha de Ponto, movimentações, registo de destino e consultas.

Não deixar de executar uma prioridade inteira apenas porque um contrato específico esteja bloqueado. Registar a limitação e continuar.

## 6. Auditoria dos consumidores

Depois de executar uma operação, verificar se o respetivo resultado chega aos consumidores relevantes.

Exemplos:

- Recebimento parcial → saldo por receber → Mapa Financeiro.
- Fatura aprovada → histórico → estado financeiro.
- Falta reportada → Mapa de Ausências → conferência RH.
- Transferência de trabalhador → equipa → permissões do Encarregado.
- Tarefa concluída → Planeamento → alertas.
- TEE aprovado → Autos e previsão económica.

Usar os problemas já identificados nas Fases 1–7 como referência, sem repetir investigações desnecessárias.

## 7. Segunda passagem — limites e falhas

Após testar os caminhos principais, repetir os contratos críticos em condições adversas controladas.

Investigar:

- Repetição de pedido.
- Interrupção entre operações.
- Concorrência.
- Dados incompletos.
- Falha de documento associado.
- Perda de autorização.
- Alteração de responsabilidade.
- Alteração da sessão durante o pedido.
- Atualização parcial de entidades relacionadas.

Usar apenas fixtures locais seguras.

Não implementar correções no produto. Quando uma falha for reproduzida, guardar o teste e registar o comportamento esperado para a futura correção.

## 8. Cobertura efetiva

Apresentar números separados:

- Total de pares identificados.
- Pares aplicáveis.
- Pares não aplicáveis, com justificação.
- Pares já comprovados anteriormente.
- Pares executados nesta missão.
- Pares aprovados.
- Pares com falhas funcionais ou de segurança.
- Pares bloqueados pelo ambiente.
- Pares ainda por executar.

Não contar uma inspeção estática como teste backend.

Não contar um teste que reproduz uma vulnerabilidade como aprovação de segurança.

Não somar execuções repetidas para aumentar artificialmente os resultados.

## 9. Continuação autónoma

Se concluir os testes dos pares aplicáveis antes da manhã, continuar automaticamente para uma segunda camada de trabalho:

**A. Cobertura de estados económicos:** criar testes de transição entre previsto, adjudicado, executado, medido, faturado, recebido e pago, com verificação dos consumidores.

**B. Cobertura de integrações:** identificar contratos de ligação que não sejam exercitados por testes de unidade isolados e construir cenários sintéticos de ponta a ponta.

**C. Cobertura de regressões:** transformar falhas comprovadas anteriormente em testes de diagnóstico persistentes, sem alterar o produto.

**D. Integridade de dados:** executar verificações de preservação de histórico, relações, revisões e ausência de dupla contagem em ambientes descartáveis.

**E. Divergência entre branches:** comparar os contratos relevantes da branch funcional de Gestão de Horas, da branch de auditoria e da main, exclusivamente por leitura. Identificar conflitos potenciais de futura integração.

Não repetir testes quando não acrescentarem evidência.

Se todos os trabalhos seguros e pertinentes terminarem, concluir a missão. Não inventar atividades para consumir tempo.

## 10. Limites de segurança

AUTORIZADO:

- Ler o código e documentação disponíveis.
- Criar testes e fixtures sintéticas.
- Executar testes em ambientes descartáveis.
- Criar matrizes e relatórios.
- Fazer commits locais de testes e documentação.

NÃO AUTORIZADO:

- Alterações ao código funcional do produto.
- SQL na base de produção.
- Acesso a dados pessoais reais.
- Alterações de permissões.
- Push.
- Merge.
- Deploy.
- Operações no Cloudflare.
- Restauros destrutivos.
- Alterações à main.

Se um passo depender de autorização, não interromper a utilizadora: documentar e continuar noutra frente.

## 11. Checkpoints e interrupção

Criar checkpoints locais após cada grupo relevante de testes.

Manter permanentemente um documento de retoma com o progresso e os grupos ainda não executados.

Não deixar todos os resultados para o fim.

Se a execução for interrompida pela manhã, deve ser possível retomar sem reconstruir fixtures ou repetir a análise inteira.

## 12. Entrega

Criar:

`docs/auditorias/validacao-profunda-20261014/`

Produzir:

1. `MATRIZ-203-PARES.csv` — estado e evidência individual de cada combinação.
2. `COBERTURA-EXECUTADA.md` — totais verificáveis.
3. `TESTES-POR-PERFIL.md` — resultados de autorização.
4. `INTEGRACOES-EXECUTADAS.md` — percursos completos exercitados.
5. `FALHAS-COMPROVADAS.md` — novas falhas, sem duplicações.
6. `TESTES-EM-FALTA.csv` — o que ainda exige validação.
7. `DECISOES-PENDENTES.md` — questões funcionais consolidadas.
8. `RESUMO-PARA-CHATGPT.md` — síntese e principais conclusões.
9. `RETOMA.md` — branch, SHA, testes, ambiente e próximos passos.

Guardar os testes executáveis e as fixtures no repositório de auditoria, com instruções de reprodução.

### Critério de conclusão

A missão não está concluída apenas porque os relatórios foram criados.

Deve existir uma reconciliação verificável dos 203 pares inicialmente não executados, indicando quais foram efetivamente testados e quais continuam pendentes, com motivo.

A seguir, executar as camadas independentes de validação ainda possíveis.

**Não declarar cobertura integral quando a execução tiver sido parcial. Não iniciar alterações de produto ou produção.**