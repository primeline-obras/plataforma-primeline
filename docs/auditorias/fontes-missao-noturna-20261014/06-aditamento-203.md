# ADITAMENTO OBRIGATÓRIO — MISSÃO DOS 203 PARES AÇÃO/PERFIL

Esta instrução complementa a missão de validação profunda já recebida. Não substitui nem reinicia a missão anterior.

## REGRA PRINCIPAL

**Não encerrar a missão apenas porque foram criados os ficheiros de entrega ou executada a primeira bateria de testes.**

O resultado pretendido é uma cobertura técnica verificável, acompanhada de provas reproduzíveis e da reconciliação integral dos 203 pares identificados.

Não há uma duração mínima artificial. Contudo, enquanto existirem verificações pertinentes, independentes, seguras e executáveis no ambiente disponível, continuar a próxima etapa.

Não declarar uma análise concluída quando apenas foi inventariada.

## 1. GATE DE COBERTURA DOS 203 PARES

O ficheiro `MATRIZ-203-PARES.csv` deverá conter uma linha individual para cada um dos 203 pares originais, sem omissões ou duplicações.

Para cada par, indicar:

- Identificador da ação original.
- Perfil.
- Módulo.
- Contrato frontend/backend.
- Comportamento esperado.
- Permissão esperada.
- Pré-condições.
- Ambiente necessário.
- Teste executado ou prova dinâmica reutilizada.
- Resultado observado.
- Estado da cobertura.
- Evidência concreta.
- Risco identificado.
- Próximo passo quando não estiver comprovado.

Estados permitidos: EXECUTADO, COBERTO POR PROVA ANTERIOR, NÃO APLICÁVEL, BLOQUEADO ou NÃO EXECUTADO.

Não considerar inspeção estática, presença de código ou documentação como execução backend.

Se um par for considerado não aplicável, fundamentar com a regra do produto e o contrato correspondente.

Se um teste cobrir vários pares, identificar expressamente cada par que foi efetivamente exercitado e demonstrar por que partilham a mesma autorização.

## 2. EXECUÇÃO OBRIGATÓRIA DOS PARES APLICÁVEIS

Depois de reconciliar os 203 pares, executar todos os casos aplicáveis para os quais o ambiente local tenha contratos e fixtures suficientes.

Não substituir execução por uma descrição do que o teste deveria fazer.

Para cada operação de escrita, verificar sempre que possível:

- Estado anterior da base descartável.
- Autorização do ator.
- Chamada real ao contrato.
- Efeito de persistência.
- Estado posterior.
- Histórico/auditoria.
- Consumidores relevantes.
- Comportamento perante repetição.
- Ausência de efeitos quando o pedido é recusado.

Para leitores, verificar o DTO recebido, o âmbito autorizado, as restrições de informação e o resultado para um perfil sem acesso.

Quando os contratos dependerem de ambiente indisponível, documentar exatamente a dependência e continuar pelos restantes.

## 3. SEGUNDA PASSAGEM OBRIGATÓRIA

Depois da primeira execução, não encerrar imediatamente.

Realizar uma segunda passagem dedicada às situações que frequentemente escapam aos testes normais:

- Registos com valores nulos.
- Relações sem entidades associadas.
- Documentos inexistentes.
- Dados históricos.
- Alterações simultâneas.
- Repetição de operação já confirmada.
- Alteração de empresa ou responsabilidade.
- Utilizador desativado.
- Sessão substituída.
- Cancelamento após preview.
- Erro de rede após confirmação.
- Revisão anterior à atual.
- Operações em lote parcialmente inválidas.
- Estados finais já encerrados.
- Anulação e correção posterior.
- Valores monetários zero, negativos ou desconhecidos, quando válidos para o domínio.

Executar os casos pertinentes para os contratos existentes, não criar cenários artificiais sem relação com a funcionalidade.

Guardar testes reproduzíveis para as lacunas novas.

## 4. AUDITORIA DOS CONSUMIDORES

Para cada escritor crítico exercitado, procurar todos os leitores, relatórios, mapas, alertas e exportadores que utilizam os dados modificados.

Verificar se o resultado chega corretamente a esses consumidores.

Não validar apenas a tabela que recebeu o INSERT ou UPDATE.

Exigir uma classificação explícita: consumidor comprovado, consumidor incorreto, consumidor não ligado ou consumidor por verificar.

## 5. RECONCILIAÇÃO FINAL

Antes de considerar os 203 pares encerrados como inventário de cobertura, verificar:

- Quantidade original: 203.
- Quantidade reconciliada: 203.
- Quantidade efetivamente executada.
- Quantidade coberta por provas anteriores válidas.
- Quantidade não aplicável.
- Quantidade bloqueada.
- Quantidade ainda não executada.

A soma das classificações tem de corresponder aos 203 pares originais.

Apresentar as razões de qualquer diferença.

**Não é obrigatório que todos os pares tenham PASS. É obrigatório que nenhum desapareça da reconciliação.**

## 6. CONTINUAÇÃO AUTOMÁTICA

Depois de concluir as etapas anteriores, prosseguir automaticamente com a missão complementar de auditoria funcional e robustez que acompanha este aditamento.

Não terminar apenas para solicitar nova tarefa.

Só considerar concluída a fila inteira quando:

1. Os trabalhos seguros disponíveis tiverem sido executados.
2. Os bloqueios tiverem sido documentados.
3. Os resultados estiverem guardados.
4. As tarefas ainda não executadas estiverem identificadas.
5. Não existir outra etapa independente e viável prevista na fila.

Se houver limite do ambiente, ferramenta indisponível ou interrupção de execução, preservar o checkpoint e comunicar a cobertura parcial.

## 7. CHECKPOINTS

Guardar os resultados a cada bloco de contratos ou grupo relevante de testes, sem esperar pelo final.

Criar commits LOCAIS de testes e documentação consistentes. Não incluir dados reais, credenciais ou backups privados.

Manter continuamente atualizado `RETOMA.md`, identificando a última execução bem-sucedida, os grupos restantes e os comandos necessários à continuação.

Não executar SQL real, push, merge, deploy ou alteração funcional do produto.

**Não reduzir o rigor da validação para cumprir uma duração. Não repetir testes apenas para aumentar contagens. A qualidade da prova prevalece sobre o número de testes.**