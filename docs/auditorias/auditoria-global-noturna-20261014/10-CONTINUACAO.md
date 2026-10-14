# Continuação — auditoria global noturna

## Checkpoint 0 — preparação (14/10/2026, cerca de 20h00 Lisboa)

- Base de produto: 2ae1f8a194f23d77bf0692d0a6d586566227298c.
- Base de auditoria: 12d86584c16ed640c3c0b5782f4c9cf839593149.
- Branch isolada: codex/auditoria-global-noturna-20261014.
- Worktree: C:/Users/conta/.codex/worktrees/auditoria-global-noturna-20261014/primeline-go-urgente.
- Branches e produto anteriores preservados; árvore inicial limpa.
- Apenas análise, documentação e testes sintéticos. Sem push, produção ou alterações funcionais.
- HR-38: reutilizar prova anterior; decisão de custos-padrão aprovada em princípio, fonte/aprovação/vigência pendentes. Não implementar HR-38/40/41/42.
- Backlog Mestre não localizado nos nomes de ficheiros do repositório; produzir inventário independente.

## Plano de blocos

1. Inventário/entrada/segurança estática.
2. Financeiro e cadeia MQT/TEE/autos/faturas/recebimentos.
3. Administrativo/RH/viaturas/documentos.
4. Fornecedores/compras/preços e proposta obra128.
5. Testes focados, decisões, backlog e consolidação.

A execução não garante temporizador. Não iniciar análise longa após 05h30 Lisboa; terminar em oportunidade segura às 06h00. Se concluída antes, não prolongar artificialmente.

## Checkpoint 1 — inventário e provas novas (14/10/2026)

- 56 JS, 265 SQL e 242 MJS do topo tests abrangidos pelo levantamento estático (não é revisão funcional exaustiva).
- 218 referências estáticas REST/RPC; 588 ocorrências CREATE FUNCTION, incluindo restauros/versões.
- 38 áreas inventariadas; os perfis CSV são autorização da vista, não concessão de cada ação.
- Financeiro: 108 PASS; novas provas finais: 9 PASS. PASS nas provas significa reprodução dos achados, não ausência de problema.
- Administrativo estático: 70 PASS; dois SKIPs de ambiente reexecutados com binários locais disponíveis.
- Reexecução nativa Medicina/Viaturas: 46 PASS /0 FAIL /0 SKIP. Não instalaram dependências.
- Achados novos: fatura/links não atómicos; parcial fecha recebimento; TEE revogado mantém tarefa; Gestão sem criar RNC. Sem correções.
- Provas aritméticas adicionais (zeros/faturado/dupla fonte) são contratos a reconciliar, não prova de dados reais errados.
