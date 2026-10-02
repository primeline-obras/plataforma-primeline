# Checkpoint de rollout — Pacote 1 Quadro — 02/10/2026

## Identidades para retomar

- Main remoto: `9e0e6c40b439160201289823db8cfee0b9adad02`.
- Candidato remoto: `feat/quadro-controlado-20261001`, `d6db2c3c9e48170a3d4c6ec937b5f7ad76e411fb`.
- Auditoria final: `audit/quadro-controlado-fecho-20261002`, `91d330025cda8e474a22a5330efdfc67f5fa8ffe`.
- Branch deste relatório: `ops/quadro-rollout-checkpoint-20261002`, baseada exatamente no candidato. Apenas este relatório foi acrescentado.
- Projeto real confirmado: Primeline-Obras.

## Precheck e autorização

Precheck real PASS em 02/10/2026, entre 15:03 e 15:12 Europe/Lisbon. Reconferência às 15:20:50: SHAs inalterados, 227 alocações / 98 movimentos e nomes de backup livres. Comparação posterior das definições das funções capturadas: sem diferenças; objetos novos do pacote ausentes.

A Jordane autorizou expressamente nesta sessão a execução somente de `supabase/quadro_controlado_backup.sql`. O conteúdo completo foi lido diretamente do disco e enviado intacto, sem adaptar o SQL. Uma única execução, resposta HTTP 201 sem erro; COMMIT do próprio script concluído.

## Backup real: PASS

Pós-check em **02/10/2026 15:25:07 Europe/Lisbon / 14:25:07 UTC**.

Todas as 15 tabelas previstas existem em `primeline_backup`:

- `quadro_20261001`
- `quadro_movimentos_20261001`
- `quadro_colaboradores_20261001`
- `quadro_ausencias_20261001`
- `quadro_obras_20261001`
- `quadro_responsaveis_20261001`
- `quadro_funcoes_20261001`
- `quadro_policies_20261001`
- `quadro_estrutura_20261001`
- `quadro_colunas_20261001`
- `quadro_tabelas_20261001`
- `quadro_acl_funcoes_20261001`
- `quadro_acl_tabelas_20261001`
- `quadro_triggers_20261001`
- `quadro_sequencias_20261001`

### Privacidade

Owner do schema e das 15 tabelas: `postgres`. Schema com ACL exclusivamente `postgres=UC/postgres`; tabelas exclusivamente `postgres=arwdDxtm/postgres`. Nenhuma ACL explícita de coluna nas cópias. PUBLIC não consta das ACLs. Verificação efetiva de `anon`, `authenticated` e `service_role`: sem USAGE/CREATE no schema e sem privilégios de tabela nas cópias.

### Integridade

Comparação integral por JSON ordenado por UUID, sem expor dados pessoais: cópias de alocações, movimentos, colaboradores, ausências, obras e responsabilidades **idênticas** às tabelas operacionais no pós-check.

- Alocações reais / backup: **227 / 227**.
- Movimentos reais / backup: **98 / 98**.
- Funções capturadas: **23**.
- Policies: **5**.
- Estrutura: **21 linhas**.
- Colunas/defaults/ACL de coluna: **33 linhas**.
- ACL de funções: **40 linhas**.
- ACL de tabelas: **53 linhas**.
- Triggers/estado: **6 linhas**.
- Sequências: tabela criada, **0 linhas**, conforme ausência de sequências associadas às duas tabelas UUID.

O backup não alterou as seis tabelas operacionais comparadas. As 27 sobreposições históricas e duas coexistências com ausências, documentadas no precheck, não foram corrigidas.

## Exportação externa: PENDENTE

O script recomenda exportação para arquivo privado externo, mas não define destino ou mecanismo seguro já configurado. Não foi improvisada exportação nem copiado backup para Git. Antes de aplicar Fase A, definir/autorizar o destino privado, exportar e verificar a integridade. O backup persistido permanece no schema privado da BD real.

## Estado seguro

Produção continua **pré-Fase-A**. `quadro_operacoes`, `quadro_dias_revisoes` e namespace `primeline_quadro_rollout` continuam ausentes. Nenhuma migration A/B foi executada, nenhum frontend publicado, nenhum merge ou deploy iniciado.

No pós-check: **0 transações de backup abertas**. Todas as consultas adicionais usaram READ ONLY e ROLLBACK; o backup usou a transação completa do script e COMMIT. Os processos MCP usados foram encerrados pelo helper após cada chamada.

Os worktrees existentes foram verificados limpos antes do checkpoint. Main local deste computador ainda está em `3f67ae912ff00c99fd2559203a344f8593acd89f`, atrás do main remoto confirmado acima; não foi atualizado nem alterado. Em casa, usar o SHA remoto confirmado, não assumir o HEAD deste checkout local.

## Próxima ação exata

**AUTORIZAÇÃO SEPARADA PARA APLICAR FASE A.**

Antes de qualquer aplicação, reconfirmar identidades/estado real e resolver a exportação externa pendente. O checkpoint não autoriza Fase A, publicação do frontend ou Fase B. Não repetir o backup com os mesmos nomes: agora existem; preservar as cópias.

Sequência restante, cada etapa sujeita à autorização correspondente:

1. Fase A.
2. Postcheck A e comparação dos dados preservados.
3. Frontend do candidato aprovado.
4. Validação autenticada dos perfis e dispositivos.
5. Prova privada B após validação real.
6. Precheck e backup B.
7. Fase B.
8. Postcheck final B e alias, incluindo ACL de coluna.

Frase para retomar: “Retomar o Pacote 1 pelo checkpoint ops/quadro-rollout-checkpoint-20261002. Backup A PASS, produção pré-Fase-A. Primeiro resolver a exportação privada pendente e reconfirmar os SHAs; não aplicar Fase A sem autorização separada.”
