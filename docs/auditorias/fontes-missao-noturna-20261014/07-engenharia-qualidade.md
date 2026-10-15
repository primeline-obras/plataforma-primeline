# PRIMELINE GO — MISSÃO COMPLEMENTAR DE ENGENHARIA DE QUALIDADE
## Auditoria extensiva de interfaces, importações, dados, documentos, processos e regressões

### MISSÃO

Após a validação profunda dos pares ação/perfil, continuar autonomamente com uma segunda missão dedicada à qualidade funcional e robustez da plataforma Primeline GO.

**Esta missão contém doze frentes de trabalho. Deve avançar sequencialmente enquanto existirem análises e testes seguros disponíveis.**

Não é uma auditoria exclusivamente documental.

Para cada frente, privilegiar:

1. Identificação dos contratos existentes.
2. Construção de cenários sintéticos representativos.
3. Execução efetiva.
4. Comparação entre resultado esperado e observado.
5. Reprodução de erros encontrados.
6. Testes de regressão reutilizáveis.
7. Registo das evidências.
8. Identificação das lacunas restantes.

Não modificar funcionalidades do produto nem corrigir silenciosamente os defeitos encontrados.

## 0. PREPARAÇÃO E ISOLAMENTO

Confirmar o repositório, a branch, o HEAD e o working tree.

Ler os resultados anteriores das auditorias globais e da validação dos 203 pares.

Continuar na worktree de auditoria quando for seguro e não existir execução concorrente. Caso necessário, criar uma worktree isolada, sem afetar os checkpoints existentes.

Reutilizar infraestrutura de PostgreSQL descartável, PostgREST local, Playwright, Node e fixtures já disponíveis.

Não instalar ferramentas adicionais que exijam autorização.

Criar:

`docs/auditorias/engenharia-qualidade-noturna-20261014/`

Manter um índice atualizado do progresso.

---

# FRENTE 1 — AUDITORIA FUNCIONAL DE TODAS AS INTERFACES

Percorrer os módulos e páginas existentes da Primeline GO.

Não limitar a análise à navegação principal. Inspecionar separadores, modais, formulários, tabelas, filtros, menus contextuais e operações secundárias.

Para cada interface com acesso local seguro:

- Abrir com contexto sintético autorizado.
- Verificar carregamento inicial.
- Testar estado vazio.
- Testar estado com muitos registos.
- Testar nomes longos e conteúdos extensos.
- Testar carregamento lento.
- Testar ausência de resposta.
- Testar erro de API.
- Testar cancelamento.
- Testar troca de contexto.
- Testar atualização após operação.
- Testar componente desmontado durante pedido.
- Testar navegação de regresso.
- Testar estado após troca de sessão.
- Verificar duplicação de botões, ações e mensagens.

Investigar especialmente componentes antigos que não foram concebidos para os novos contratos de autorização.

**Entrega:** matriz de interfaces, estados exercitados, capturas representativas e falhas comprovadas.

---

# FRENTE 2 — IMPORTADORES E FICHEIROS EXCEL

Auditar todos os importadores relevantes existentes no repositório:

- Orçamentos e MQT.
- Planeamentos.
- Dados de obras.
- Subempreitadas.
- Fornecedores.
- Colaboradores e RH.
- Mapas operacionais.
- Outros XLSX/CSV efetivamente suportados.

Criar ficheiros exclusivamente sintéticos representando:

- Ficheiro válido.
- Ficheiro vazio.
- Colunas em ordem diferente.
- Colunas obrigatórias ausentes.
- Duplicados.
- IDs inexistentes.
- Campos monetários inválidos.
- Números com separadores portugueses.
- Datas em formatos diferentes.
- Fórmulas.
- Células com texto inesperado.
- Linhas incompletas.
- Ficheiros com centenas ou milhares de linhas, dentro dos limites seguros do ambiente.
- Mesma importação executada duas vezes.
- Importação parcialmente inválida.
- Importação entre duas empresas.

Avaliar se a operação é atómica, idempotente e se o utilizador consegue identificar quais linhas foram aceites ou recusadas.

Não usar dados pessoais reais.

Comparar também exportação seguida de reimportação, quando o produto suportar esse percurso.

Não prometer compatibilidade com formatos que a aplicação não suporta.

**Entrega:** catálogo de importadores, fixtures, resultados, limitações e testes de regressão.

---

# FRENTE 3 — CENTRO DOCUMENTAL E ARQUIVOS

Investigar o ciclo de vida dos documentos:

Upload → metadados → associação à entidade → permissões → visualização → download → revisão → arquivo/remoção.

Abranger os módulos efetivamente existentes:

- Documentos por obra.
- Desenhos.
- PDEs e PAMEs.
- Atas.
- Contratos.
- Faturas.
- Documentos de colaboradores.
- Documentos da empresa.
- Medicina e ausências.
- Viaturas.
- RNC.
- Anexos de subempreitadas.
- Outros arquivos suportados.

Criar testes locais para:

- Documento válido.
- MIME incorreto.
- Extensão incompatível.
- Ficheiro vazio.
- Ficheiro demasiado grande.
- Documento repetido.
- Nome de ficheiro especial.
- Revisão posterior.
- Documento associado a entidade errada.
- Entidade eliminada ou arquivada.
- Referência órfã.
- Falha de upload após criação de metadados.
- Falha de metadados após upload.
- Tentativa de consulta por perfil não autorizado.
- Documento pertencente a outra empresa.

Reutilizar as descobertas anteriores de renderização HTML, sem repetir análises já comprovadas e sem executar cargas ofensivas fora de ambiente isolado.

Não utilizar Storage real.

**Entrega:** matriz documental, integridade de associações, contratos de armazenamento e testes sintéticos.

---

# FRENTE 4 — ALERTAS, AGENDA E TAREFAS

Investigar o ciclo:

Evento → criação do alerta → destinatário → apresentação → ação → resolução → histórico.

Abranger:

- Alertas administrativos.
- Medicina do Trabalho.
- Contratos a terminar.
- Documentos a vencer.
- Viaturas.
- Planeamento.
- Tarefas semanais.
- Alertas financeiros.
- Notificações da equipa técnica.
- Outros tipos existentes.

Criar cenários que verifiquem:

- Um evento gera o número correto de alertas.
- Dois eventos distintos não são fundidos incorretamente.
- Mesmo evento não é duplicado por repetição do processamento.
- Mudança de responsável.
- Utilizador desativado.
- Obra encerrada.
- Tarefa concluída.
- Prazo alterado.
- Prazo ultrapassado.
- Alerta já resolvido.
- Alerta histórico.
- Diferenças entre destinatários.
- Mudança de sessão.
- Falhas de carregamento.

Investigar particularmente os casos conhecidos de alertas duplicados no Planeamento e na Obra 120.

Não eliminar alertas reais.

**Entrega:** matriz de eventos e destinatários, cenários executados e lacunas da reconciliação.

---

# FRENTE 5 — COERÊNCIA DOS INDICADORES FINANCEIROS

Construir cenários económicos exclusivamente sintéticos e verificar as invariantes dos cálculos entre módulos.

Não repetir apenas os P1 já demonstrados. Avaliar também:

- Orçamento inicial e revisões.
- Contrato e aditamentos.
- TEE positivo e negativo.
- Quantidade medida inferior à contratada.
- Quantidade medida superior à contratada.
- Auto parcial.
- Adiantamento.
- Retenção.
- Faturação parcial.
- Recebimentos sucessivos.
- Nota de crédito.
- Fatura anulada.
- Despesa associada à obra errada.
- Custo distribuído por vários meses.
- Mudança da data prevista de conclusão.
- Mês sem movimento.
- Obra de investimento próprio.
- Previsão versus realização.
- Custo desconhecido versus zero.
- Ausência de tarifa aprovada.
- Dados financeiros contraditórios entre mapas.

Testar conservação de saldos, distinção entre estados e ausência de dupla contagem.

Criar testes metamórficos quando possível: por exemplo, dividir um recebimento válido em duas parcelas deve conservar o total recebido e o saldo final, embora os estados intermédios sejam diferentes.

Não alterar as fórmulas existentes.

**Entrega:** catálogo de invariantes, cenários, resultados e divergências.

---

# FRENTE 6 — FORNECEDORES, COMPRAS E PREÇOS

Fazer testes de consistência dos cadastros, propostas e comparativos.

Abranger:

- Fornecedor sem especialidade.
- Fornecedor com várias especialidades.
- Entidades potencialmente duplicadas.
- Subempreiteiro também fornecedor.
- Material semelhante com unidades diferentes.
- Equipamento vendido versus alugado.
- Propostas com validade diferente.
- Preço com e sem IVA.
- Descontos.
- Transporte.
- Quantidades mínimas.
- Fornecedor sem proposta válida.
- Preço histórico.
- Preço adjudicado versus preço faturado.

Avaliar os contratos necessários à futura consulta de preços pelo Encarregado.

Não implementar a consulta nova.

Apresentar que informações podem ser divulgadas ao Encarregado sem conceder autoridade comercial indevida.

**Entrega:** matriz de comparabilidade, limites dos dados e proposta de testes de aceitação.

---

# FRENTE 7 — SIMULAÇÃO FUNCIONAL DA OBRA 128

Construir um estudo sintético completo de um TEE por administração direta.

Cenário exemplificativo:

- Trabalho a mais identificado.
- TEE estimativo preparado.
- Cliente aprova.
- Execução distribuída por vários dias.
- Vários trabalhadores.
- Materiais consumidos.
- Equipamentos utilizados.
- Quantidades realizadas diferentes das estimadas.
- Interrupção da execução.
- Correção de um apontamento.
- Conferência técnica.
- Apuramento do custo real.
- Valorização final dependente de regra contratual.

Mapear que funcionalidades existentes já suportam cada etapa e quais precisam de novos contratos.

Não inventar a fórmula de preço final ao cliente.

Separar rigorosamente:

**Custo estimado / custo real / preço contratual / valor faturável.**

Produzir proposta de modelo de dados e interface, sem implementação funcional.

**Entrega:** fluxo por estados, contratos reutilizáveis, entidades em falta, riscos e protótipo estrutural documentado.

---

# FRENTE 8 — QUADRO DE PESSOAL E RH

Investigar integridade entre:

- Cadastro de colaboradores.
- Cargo RH.
- Perfil operacional.
- Data de admissão.
- Atividade.
- Alocação.
- Transferência.
- Ausências.
- Férias.
- Folha de Ponto.
- Horário individual.
- Conferência mensal.
- Contratos e medicina.

Verificar cenários de:

- Colaborador sem data de admissão.
- Colaborador sem conta Auth.
- Conta sem colaborador associado.
- Dois utilizadores ligados incorretamente.
- Mudança de função.
- Mudança de obra.
- Períodos históricos.
- Transferência no próprio dia.
- Saída da empresa.
- Reativação posterior.
- Ausência e horas em conflito.
- Jornadas em vigências diferentes.
- Horário ainda não aprovado.
- Dia útil sem horas nem ausência.

Preservar as regras aprovadas de Folha de Ponto.

FP-28 e FP-29 permanecem apenas como propostas futuras.

**Entrega:** matriz de integridade RH/Equipa e resultados de testes sintéticos.

---

# FRENTE 9 — RESPONSIVIDADE E ACESSIBILIDADE

Testar os ecrãs relevantes em, pelo menos, estes contextos quando viáveis:

- Desktop amplo.
- Desktop compacto.
- Tablet 1024×768.
- Tablet 768×1024.
- Ecrã móvel estreito.

Verificar:

- Overflow.
- Scroll horizontal indevido.
- Campos inacessíveis.
- Botões ocultos.
- Modais que ultrapassam o viewport.
- Teclado.
- Ordem de foco.
- Rótulos acessíveis.
- Mensagens de erro.
- Contraste.
- Leitura de tabelas.
- Estados disabled/loading.
- Inputs de data e hora.
- Perda de valores ao mudar de layout.
- Comportamento com nomes longos.
- Comportamento de tabelas extensas.

Priorizar Quadro de Pessoal, Folha de Ponto, Financeiro, Planeamento, Documentos e páginas administrativas.

Gerar capturas apenas quando acrescentarem prova útil.

Não redesenhar a interface nem modificar CSS do produto.

**Entrega:** matriz por ecrã/viewport, problemas comprovados e capturas de referência.

---

# FRENTE 10 — SESSÕES, ESTADOS ASSÍNCRONOS E RECUPERAÇÃO

Auditar problemas de sincronização frontend:

- Troca rápida de obra.
- Troca rápida de colaborador.
- Mudança de mês durante carregamento.
- Atualização depois de logout.
- Resposta de utilizador anterior.
- Duas leituras concorrentes.
- Repetição de clique.
- Falha de rede após preview.
- Ação confirmada sem resposta HTTP.
- Formulário desmontado.
- Cache desatualizada.
- Reabertura da página.
- Refresh de token, em ambiente sintético quando suportado.
- Utilizador sem permissão após atualização de perfil.

Dar atenção ao P2 já encontrado de consulta antiga permanecer visível depois de trocar de obra.

Não corrigir o código funcional.

Criar testes que reproduzam as falhas e comprovem as condições necessárias à sua correção.

**Entrega:** matriz de cenários assíncronos, testes e riscos de contaminação entre contextos.

---

# FRENTE 11 — COMPATIBILIDADE ENTRE BRANCHES E EVOLUÇÃO DA PLATAFORMA

Comparar, apenas por leitura:

- `main`.
- Branch de Gestão Integrada de Horas.
- Branch de Planeamento operacional.
- Branch de auditoria global.
- Outras branches relevantes disponíveis localmente.

Identificar:

- Contratos que divergiram.
- Migrations com definições incompatíveis.
- Funcionalidades presentes apenas numa branch.
- Testes com expectativas contraditórias.
- Modificações na mesma função.
- Scripts históricos perigosos de reaplicar.
- Dependências que precisam de integração antes de publicação.
- Mudanças de frontend sem backend correspondente.

Não fazer merge nem alterar branches funcionais.

Criar um mapa de conflitos por ficheiro, objeto SQL e comportamento.

Preparar uma sequência proposta de integração futura, sujeita a aprovação.

**Entrega:** matriz de divergências e plano de reconciliação.

---

# FRENTE 12 — CONSOLIDAÇÃO E CONTROLO DE QUALIDADE

Depois das frentes anteriores, realizar uma segunda revisão dos próprios resultados.

Verificar:

1. Todas as conclusões têm evidência.
2. Os testes de vulnerabilidade estão corretamente identificados como falhas do produto.
3. Os números de testes não incluem repetições contabilizadas duas vezes.
4. Os ficheiros de evidência são reproduzíveis.
5. Nenhuma fixture contém dados reais ou credenciais.
6. As novas pendências não duplicam as descobertas anteriores.
7. As classificações P1/P2/P3 são justificadas.
8. As recomendações não contradizem decisões funcionais aprovadas.
9. Cada bloqueio identifica o que falta para ser resolvido.
10. O relatório final distingue claramente código local, código publicado e comportamento ainda não comprovado.

Criar uma matriz de cobertura com a quantidade de cenários planeados, executados, aprovados, falhados, bloqueados e não executados.

Não declarar cobertura total por mera inspeção de ficheiros.

---

# GESTÃO AUTÓNOMA DA FILA

Esta missão deve continuar automaticamente de uma frente para a seguinte.

Não terminar depois de produzir o primeiro relatório.

Ao concluir cada frente:

1. Guardar documentação e provas.
2. Atualizar o índice de execução.
3. Registar os testes e resultados.
4. Criar checkpoint local quando apropriado.
5. Continuar imediatamente para a próxima frente independente.

Se uma frente estiver bloqueada, registar a causa e continuar para outra.

Não pedir decisões funcionais durante a noite.

Não aguardar aprovação de interfaces, autorização de produção ou credenciais.

Não criar tarefas fictícias para ocupar tempo.

Se todas as frentes forem concluídas antes da manhã, fazer uma revisão de lacunas ainda executáveis, aprofundando os testes mais críticos que ficaram parcialmente cobertos.

Se não houver trabalho seguro e pertinente restante, encerrar com relatório completo.

---

# RESTRIÇÕES ABSOLUTAS

Permitido:

- Código de testes isolado.
- Fixtures sintéticas.
- PostgreSQL/PostgREST descartável.
- Browser automatizado local.
- Documentação.
- Matrizes.
- Diagramas técnicos textuais.
- Commits locais de auditoria.

Proibido:

- Alteração funcional do produto.
- SQL em BD real.
- Acesso a dados pessoais reais.
- Escritas no Supabase hospedado.
- Push.
- Merge.
- Deploy.
- Operações no Cloudflare.
- Modificação de permissões reais.
- Restauro destrutivo.
- Alteração de dados de produção.
- Modificação de regras de negócio ainda pendentes de aprovação.

Nenhuma descoberta autoriza automaticamente a sua própria correção.

---

# ENTREGA

Criar dentro da pasta de auditoria:

`ENGENHARIA-QUALIDADE/`

Produzir um relatório por frente, matrizes CSV e os testes/fixtures necessários.

Criar também:

**`INDICE-EXECUCAO.md`**

Estado de cada frente: não iniciada, em execução, parcialmente concluída, concluída ou bloqueada.

**`COBERTURA-REAL.csv`**

Cenários planeados, executados, resultado e evidência.

**`NOVAS-DESCOBERTAS.csv`**

Apenas problemas novos ou novas provas que alterem substancialmente uma descoberta anterior.

**`DECISOES-PARA-UTILIZADORA.md`**

Questões agrupadas, com alternativas, recomendação e impacto.

**`CONSOLIDACAO-BACKLOG.csv`**

Propostas de atualização do Backlog Mestre, com códigos existentes quando identificáveis.

**`RESUMO-CHATGPT.md`**

Resumo executivo, riscos, testes, bloqueios e próximas decisões.

**`RETOMA.md`**

Branch, HEAD, working tree, comandos de reprodução, trabalho concluído e trabalho restante.

Guardar tudo progressivamente. Criar checkpoints locais sem push.

**A missão não está concluída simplesmente porque os documentos existem. Cada frente precisa de uma classificação de cobertura e evidência suficiente para justificar o respetivo estado.**

---

# ENCERRAMENTO

A utilizadora poderá verificar a execução por volta das 07h00 e solicitar uma interrupção segura.

Não é necessário terminar automaticamente às 06h00.

Manter sempre resultados parciais preservados para permitir essa interrupção.

Se os trabalhos terminarem antecipadamente, encerrar com uma prestação de contas precisa, sem inventar testes ou prolongar artificialmente o processamento.

**Objetivo: maximizar a quantidade de trabalho técnico útil, reproduzível e seguro realizado durante a ausência da utilizadora, sem alterar o produto ou a produção.**