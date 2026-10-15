# PRIMELINE GO — MISSÃO NOTURNA DE AUDITORIA GLOBAL

**Data:** 14/10/2026  
**Início:** aproximadamente 19h50  
**Encerramento pretendido:** 06h00 de 15/10/2026  
**Modalidade:** trabalho autónomo, sem supervisão.

## MISSÃO

Realizar uma auditoria técnica profunda e transversal de TODA a plataforma Primeline GO, identificando funcionalidades incompletas, bugs, lacunas no desenvolvimento, duplicações, problemas de segurança, integrações pendentes e possíveis simplificações.

O objetivo é produzir uma base técnica sólida para atualizar o Backlog Mestre global e planear as próximas implementações.

Esta tarefa deve ser predominantemente de ANÁLISE, INVESTIGAÇÃO, TESTES e DOCUMENTAÇÃO.

Não implementar novas funcionalidades nem alterar regras de negócio.

## 1. Preparação segura

Repositório: `primeline-obras/plataforma-primeline`.

Último checkpoint da Gestão de Horas:
`2ae1f8a194f23d77bf0692d0a6d586566227298c`.

Última auditoria conhecida:
- Branch: `codex/audit-gestao-horas-integrada-20261014`
- SHA: `12d86584c16ed640c3c0b5782f4c9cf839593149`.

Confirmar o estado real antes de iniciar.

Criar worktree/branch isolada para a auditoria noturna, preservando integralmente as branches existentes.

Não executar operações destrutivas de Git.

Trabalhar apenas com o código, scripts, documentação e ambientes sintéticos locais disponíveis.

## 2. AUDITORIA GLOBAL DOS MÓDULOS

Percorrer sistematicamente toda a aplicação.

Inspecionar:

- `src/`
- `supabase/`
- `tests/`
- `docs/`
- `index.html`
- Configurações e pontos de entrada relevantes.

Identificar TODAS as áreas da plataforma, independentemente da sua situação atual.

Para cada módulo, documentar:

1. Funcionalidades existentes.
2. Perfis autorizados.
3. Componentes frontend.
4. Tabelas, RPCs, leitores e writers.
5. Integrações com outros módulos.
6. Testes existentes.
7. Funções parcialmente desenvolvidas.
8. Funcionalidades inacessíveis pela interface.
9. Código antigo, duplicado ou aparentemente obsoleto.
10. Riscos e pendências comprovadas.

Não interpretar código existente como prova de instalação em produção.

Se o Backlog Mestre não estiver disponível no repositório, não interromper o trabalho: criar um inventário técnico independente para reconciliarmos depois.

## 3. FINANCEIRO — AUDITORIA PROFUNDA

Analisar o circuito completo:

Orçamentação/MQT → Planeamento → Custos → Previsões Financeiras → TEEs → Autos → Faturação → Recebimentos.

Investigar especialmente:

- Origem dos valores e fontes de verdade.
- Custos estimados e custos reais.
- Margens, desvios e valores faturáveis.
- Distribuição mensal de custos.
- Integração entre Planeamento e previsão financeira.
- Autos de medição e respetivos artigos.
- Integração entre itens TEE e itens dos autos.
- Faturação parcial e recebimentos.
- Faturas de fornecedores e controlo de duplicados.
- Despesas gerais e débitos diretos.
- Riscos de dupla contagem.
- Casos com contratos de investimento próprio.
- Divergências entre frontend, SQL, documentação e testes.

Preparar um mapa das dependências técnicas.

Não criar nem alterar valores monetários reais.

## 4. ADMINISTRATIVO, RH E VIATURAS

Auditar os módulos de:

- Cadastro de colaboradores.
- Contratos de trabalho.
- Medicina do Trabalho.
- Férias e ausências.
- Quadro de Pessoal.
- Folha de Ponto e relatórios.
- Gestão de viaturas.
- Documentação de colaboradores e empresa.
- Alertas de prazos e validade.
- Acessos e permissões.

Identificar campos incompletos, fluxos redundantes, ações incompatíveis entre perfis e integrações que existem apenas parcialmente.

Rever particularmente a ligação entre Encarregado, FALTOU, Mapa de Ausências e Administrativo.

O fluxo novo de Gestão de Horas já foi desenvolvido localmente; não o reimplementar.

## 5. FORNECEDORES, SUBEMPREITEIROS E COMPRAS

Auditar os cadastros e diretórios existentes.

Investigar:

- Fornecedores incompletos ou duplicados.
- Subempreiteiros e especialidades.
- Relações entre fornecedores, consultas, propostas e adjudicações.
- Dados de preços de materiais e equipamentos.
- Comparabilidade das unidades de medida.
- Histórico e datas dos preços.
- Possibilidade de construir um mapa de preços consultável pelos Encarregados.

Avaliar tecnicamente uma solução em que o Encarregado possa consultar e comparar preços, sem obter automaticamente autorização para comprar, adjudicar ou alterar condições comerciais.

Distinguir preços de propostas, preços adjudicados, preços faturados e valores históricos.

Preparar proposta funcional e técnica, sem implementar.

## 6. OBRA 128 — TRABALHOS A MAIS POR ADMINISTRAÇÃO DIRETA

Estudar a viabilidade de um processo específico para trabalhos a mais por administração direta.

Fluxo pretendido:

1. Identificação do trabalho a mais.
2. Preparação de TEE com estimativa.
3. Apresentação ao cliente.
4. Aprovação formal.
5. Registo factual pelo Encarregado durante a execução.
6. Apontamento de trabalhadores, horas, tarefas, materiais, equipamentos e quantidades.
7. Conferência pela equipa técnica.
8. Apuramento dos custos efetivos.
9. Determinação do valor final ao cliente, conforme regra contratual a definir.

Investigar como reutilizar os módulos atuais de Folha de Ponto, materiais, compras, fornecedores, TEE e autos.

Identificar as entidades e relações necessárias, sem inventar custos, preços, margens ou condições contratuais.

Preparar proposta de interface do Encarregado e fluxo de validação.

Não implementar sem aprovação.

## 7. SEGURANÇA E CONSISTÊNCIA

Auditar transversalmente:

- Autorizações por perfil.
- Isolamento entre empresas e obras.
- Segurança dos writers.
- RLS e SECURITY DEFINER.
- Exposição de dados financeiros e RH.
- Histórico e rastreabilidade.
- Concorrência e revisões.
- Idempotência.
- Integridade de documentos.
- Dependências entre migrations.
- Compatibilidade de versões.

A vulnerabilidade HR-38 já foi comprovada. Não repetir a auditoria original sem necessidade.

Considerar as seguintes decisões recentes:

- Custos-padrão operacionais globais por função e nível, independentes dos custos individuais RH: aprovados em princípio.
- Valores/hora individuais RH confidenciais, aplicáveis a todas as obras.
- Administrativo autorizado, incluindo Belmira, pode definir e aprovar o valor individual.
- Fonte definitiva, aprovação da tabela-padrão e vigências ainda precisam de fecho.
- Não implementar HR-38/40/41/42 nesta missão.

Pode analisar arquiteturas e apresentar recomendações, mas não alterar permissões nem contratos.

## 8. TESTES AUTÓNOMOS

Executar testes existentes relevantes e verificações adicionais somente quando puderem correr em ambientes locais seguros e descartáveis.

Priorizar análises que acrescentem evidência nova.

Não repetir centenas de testes sem necessidade.

Não instalar dependências ou alterar o ambiente global do computador apenas para contornar bloqueadores.

Nunca enfraquecer testes para obter resultados positivos.

Registar resultados exatos, skips e limitações.

## 9. AUTONOMIA E DECISÕES

Não interromper a utilizadora para perguntas funcionais.

Quando surgir uma dúvida:

1. Registar a pergunta.
2. Explicar por que precisa de decisão.
3. Apresentar alternativas.
4. Recomendar uma solução fundamentada.
5. Continuar com outra análise independente.

Se surgir pedido de permissão, autenticação ou acesso externo que não esteja autorizado, não tentar contorná-lo.

Documentar o bloqueio e avançar com outro trabalho disponível.

Não considerar perguntas não respondidas como autorizações implícitas.

## 10. LIMITES ABSOLUTOS

**NÃO AUTORIZADO:**

- SQL em base de dados real.
- Escritas no Supabase hospedado.
- Alterações no Cloudflare.
- Deploys ou previews.
- Push.
- Merge.
- Alterações à main.
- Alterações funcionais da aplicação.
- Mudanças nas permissões existentes.
- Acesso ou exportação de dados pessoais reais.
- Eliminação de ficheiros ou histórico.

Trabalhar exclusivamente na auditoria, em relatórios e testes locais seguros.

## 11. GESTÃO DA EXECUÇÃO

O trabalho deve ser desenvolvido por etapas independentes.

Não deixar toda a documentação para o final. Guardar o resultado de cada auditoria imediatamente após a sua conclusão.

Registar um checkpoint após cada grande bloco de trabalho.

A partir das 05h30, não iniciar novas análises longas. Priorizar consolidação e entrega.

Às 06h00, terminar na próxima oportunidade segura, preservando os ficheiros e os resultados.

Esta instrução não constitui um temporizador garantido. Se a execução não permitir interrupção automática, preservar checkpoints para que possa ser interrompida manualmente pela manhã.

Caso as auditorias acabem antes das 06h00, aprofundar apenas os itens ainda não investigados e com evidência disponível. Não inventar tarefas para ocupar tempo.

## 12. ENTREGA FINAL

Criar a pasta:

`docs/auditorias/auditoria-global-noturna-20261014/`

Produzir:

**01 — RELATORIO-GERAL.md**

Resumo executivo, principais descobertas, riscos e prioridades.

**02 — INVENTARIO-PLATAFORMA.csv**

Módulos, funcionalidades, estado identificado, perfis, dependências, testes e evidências.

**03 — FINANCEIRO.md**

Auditoria dos processos financeiros e integrações.

**04 — ADMINISTRATIVO-RH-VIATURAS.md**

Auditoria dos processos administrativos.

**05 — FORNECEDORES-COMPRAS.md**

Cadastros, comparativos e oportunidades.

**06 — OBRA128-ADMINISTRACAO-DIRETA.md**

Arquitetura e fluxo proposto.

**07 — SEGURANCA-PERMISSOES.md**

Riscos, provas e recomendações.

**08 — PENDENCIAS-PARA-BACKLOG.csv**

Somente tarefas relevantes, com descrição específica, estado, prioridade, evidência e dependências.

**09 — QUESTOES-PARA-DECISAO.md**

Todas as questões reunidas, com alternativas e recomendações.

**10 — CONTINUACAO.md**

Trabalhos realizados, incompletos, testes, branch, SHA e próximos passos.

Cada descoberta deve indicar a evidência concreta, preferencialmente caminho, função e linha de código.

Classificar as afirmações como CONFIRMADO, PROVÁVEL ou NÃO VERIFICADO.

Não apresentar um levantamento como exaustivo se não tiver sido possível percorrer todos os módulos.

Criar commits LOCAIS de documentação quando apropriado, sem incluir ficheiros temporários, credenciais, backups ou dados sensíveis.

Não efetuar push.

**Objetivo final: entregar uma auditoria global que permita atualizar o Backlog Mestre sem duplicar trabalhos já realizados, recuperar pendências esquecidas e definir prioridades reais para toda a Primeline GO.**