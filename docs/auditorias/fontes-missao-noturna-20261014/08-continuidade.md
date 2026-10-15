# PRIMELINE GO — REGRA OBRIGATÓRIA DE CONTINUIDADE AUTÓNOMA

Esta instrução complementa as três missões já recebidas e tem prioridade sobre qualquer interpretação anterior de encerramento por bloqueio.

## PRINCÍPIO FUNDAMENTAL

**UM BLOQUEIO NUMA TAREFA NÃO É UM BLOQUEIO DA MISSÃO.**

Não encerrar a execução inteira porque uma análise, teste ou funcionalidade exige uma resposta, aprovação, ferramenta indisponível, autorização, decisão funcional ou dependência externa.

Tratar cada impedimento individualmente, preservar o progresso e continuar automaticamente com a próxima tarefa independente da fila.

## 1. Procedimento obrigatório perante bloqueios

Sempre que encontrar um impedimento:

1. Identificar exatamente a tarefa e a etapa afetada.
2. Registar o problema e a evidência disponível.
3. Identificar a dependência que impede a continuação.
4. Explicar o que seria necessário para desbloquear.
5. Registar eventuais alternativas e recomendação técnica.
6. Marcar a tarefa como **BLOQUEADA — AGUARDA DECISÃO**, **BLOQUEADA — AGUARDA AUTORIZAÇÃO** ou **BLOQUEADA — DEPENDÊNCIA TÉCNICA**, conforme aplicável.
7. Guardar os resultados parciais e o ponto exato de retoma.
8. **Passar imediatamente à próxima tarefa independente.**

Não pedir uma resposta à utilizadora durante a execução noturna.

Não assumir uma autorização implícita nem alterar regras funcionais para contornar o bloqueio.

## 2. Estados obrigatórios das tarefas

Utilizar os seguintes estados no controlo da execução:

- **NÃO INICIADA:** ainda por analisar.
- **EM EXECUÇÃO:** trabalho atualmente ativo.
- **CONCLUÍDA:** critérios de aceitação efetivamente cumpridos, com evidência.
- **PARCIAL:** existem resultados úteis, mas ainda falta trabalho executável.
- **BLOQUEADA:** não pode avançar sem uma dependência ou decisão identificada.
- **NÃO APLICÁVEL:** comprovadamente fora do âmbito, com justificação.

Não classificar como CONCLUÍDA uma tarefa que teve apenas o diagnóstico realizado.

Não transformar tarefas bloqueadas em concluídas para finalizar a missão.

## 3. Fila de execução obrigatória

Manter uma fila persistente de todas as tarefas previstas nas instruções anteriores:

**Primeira missão:** reconciliação e validação dos 203 pares ação/perfil, incluindo as verificações adicionais.

**Segunda missão:** as 12 frentes de Engenharia de Qualidade.

Dentro de cada frente, manter as suas subtarefas e testes associados.

Ao encontrar um bloqueio:

- Suspender apenas a tarefa dependente.
- Continuar as subtarefas independentes da mesma frente.
- Quando não houver mais subtarefas executáveis nessa frente, avançar para a seguinte.
- Regressar às tarefas parciais se ainda houver verificações independentes possíveis.
- Não repetir tentativas que dependam da mesma autorização indisponível.

**Não é permitido abandonar o restante da fila porque uma tarefa prioritária ficou bloqueada.**

## 4. Registo permanente de progresso

Criar e atualizar continuamente:

`CONTROLO-EXECUCAO-NOTURNA.md`

Para cada tarefa, indicar:

- Código/identificador.
- Frente e subtarefa.
- Estado.
- Trabalho realizado.
- Evidência e testes.
- Bloqueio, quando existir.
- Próxima ação.
- Dependência externa, se aplicável.

Manter separadamente:

`BLOQUEIOS-PARA-DECISAO.md`

Neste segundo documento, reunir todas as questões que serão apresentadas à utilizadora e ao ChatGPT no dia seguinte, sem interromper o trabalho noturno.

Guardar ambos progressivamente, com checkpoints locais.

## 5. Critério para avançar

Não esperar que uma frente esteja 100% concluída para iniciar outra.

O critério é:

**Terminou o trabalho executável nesta frente?**

- **SIM:** passar à próxima.
- **NÃO:** continuar.
- **Há bloqueio parcial:** registar o bloqueio e continuar as partes independentes.

Priorizar trabalho novo e verificável, evitando relatórios repetitivos e testes redundantes.

## 6. Critério para encerrar a missão inteira

A missão só pode ser considerada integralmente concluída quando:

1. Todas as tarefas previstas nas instruções anteriores tiverem sido identificadas na fila.
2. Todas tiverem um estado explícito.
3. Todas as tarefas executáveis tiverem sido efetivamente trabalhadas até cumprir os critérios de aceitação ou atingir um impedimento real.
4. Os testes e evidências tiverem sido guardados.
5. As tarefas parciais e bloqueadas tiverem ponto de retoma documentado.
6. Todas as perguntas pendentes estiverem consolidadas.
7. Não existirem outras tarefas independentes e seguras previstas na fila que possam continuar.

Se existirem tarefas bloqueadas, o estado geral deverá ser **EXECUÇÃO PARCIAL COM BLOQUEIOS**, nunca CONCLUÍDA INTEGRALMENTE.

Se restarem tarefas executáveis, continuar, sem pedir autorização para a próxima etapa já incluída nas instruções.

## 7. Autonomia não significa contornar segurança

Continuam absolutamente proibidos:

- SQL na base de produção.
- Acesso a dados pessoais reais.
- Push, merge ou deploy.
- Alterações no Cloudflare.
- Alterações funcionais ou de permissões sem aprovação.
- Operações destrutivas.
- Contorno de mecanismos de segurança ou pedidos de autorização.

Se um bloqueio resultar dessas restrições, respeitá-lo, documentá-lo e continuar noutra tarefa.

Se a execução atingir um limite técnico da sessão, preservar o estado e emitir uma retoma completa. Não é necessário ultrapassar limites do ambiente.

## 8. Entrega da manhã

Quando a utilizadora regressar, deve ser possível saber imediatamente:

- Quantas tarefas estavam previstas.
- Quantas foram concluídas com prova.
- Quantas ficaram parciais.
- Quantas ficaram bloqueadas.
- Quantas não foram iniciadas.
- O que foi efetivamente testado.
- Que decisões ou autorizações são necessárias.
- Qual é a próxima tarefa executável.
- Branch, SHA e estado do working tree.

**Não interromper a execução apenas para apresentar relatórios intermédios. Guardá-los e continuar trabalhando.**

A utilizadora solicitará a paragem segura quando regressar, se a execução ainda estiver ativa.

**REGRA FINAL: bloquear uma tarefa, documentar, continuar a próxima. Repetir até percorrer toda a fila de trabalho seguro disponível.**