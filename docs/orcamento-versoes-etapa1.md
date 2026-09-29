# Etapa 1 — versões e fontes económicas

Estado: SQL preparado e testado localmente; não aplicado ao Supabase.

## Âmbito e origem das decisões

Esta implementação aplica a Especificação Económica V1 e o preflight técnico:

- `documentos_obra` pode ser referenciado, mas não substitui uma versão económica nem preserva hashes, manifesto e validação.
- `pedido_orcamento_versoes` representa propostas comerciais; não é reutilizado como orçamento da obra.
- As duas tabelas novas começam vazias. Não existem imports, backfills, novas RPCs de negócio ou consumidores frontend nesta etapa.
- Os 18 itens legados e 9 resumos de fases identificados na Obra 120 permanecem intactos. Não são promovidos a artigos detalhados do ORCA.
- `itens_orcamento`, `orcamento_fases`, `contratos`, os seus readers e `vw_previsao_mensal` não são alterados.
- Reutiliza-se `fn_registar_log_auditoria('id')`; a migration não redefine a função nem as policies legadas.

Não se importam valores nesta etapa. A futura reconciliação deve preservar Folha3 como resumo validado pela Jordane e os 279,78 € como diferença de detalhe pendente, sem atribuição inventada a artigos ou alteração de custo.

## Contratos novos

| Campo | Valores permitidos |
| --- | --- |
| natureza | `original_documental`, `revisao`, `referencia_legada` |
| estado_validacao | `rascunho`, `em_validacao`, `validada`, `rejeitada` |
| estado_reconciliacao | `nao_avaliada`, `pendente`, `reconciliada` |

`referencia_legada` é uma classificação disponível para uma futura operação explícita; nenhum registo é criado automaticamente. Uma versão pode ficar validada documentalmente e ter reconciliação pendente; as duas dimensões são independentes.

`papel_fonte` é texto obrigatório não vazio, sem enum prematuro. Exemplos: `original`, `resumo_validado`, `detalhe`, `evidencia_correcao`.

- Número positivo e único por obra. O número de uma versão anterior deve ser menor e da mesma obra; isso impede ciclos.
- Identidade e linhagem da versão (`id`, `obra_id`, `numero_versao`, `versao_anterior_id`) são fixas desde a criação. O conteúdo de rascunhos continua editável.
- Identidade e versão da fonte (`id`, `versao_id`) são fixas; corrigir associação de um rascunho exige remover e recriar a fonte, com auditoria.
- SHA-256 e hash do manifesto usam 64 caracteres hexadecimais minúsculos. A validação exige autor, data, manifesto JSON do tipo objeto e hash.
- A transição para `validada` exige pelo menos uma fonte, revalida os campos obrigatórios, SHA-256 e tamanho de todas as fontes e verifica a obra dos documentos. INSERT diretamente validada sem fontes também é recusado. Fluxo: rascunho → fontes → manifesto completo → validação → congelamento.
- Na validação, a BD verifica a correspondência entre `manifesto_hash` e SHA-256 dos bytes UTF-8 de `manifesto::text`. O hash dos ficheiros continua a exigir verificação dos bytes no futuro fluxo documental.
- A unicidade da fonte usa versão, bucket, object_key, papel, folha e intervalo. NULL e vazio são equivalentes na localização opcional. Alterar nome ou hash não permite duplicar a mesma localização/papel.
- Todos os FKs usam DELETE RESTRICT; não há remoções em cascata.

### Decisão sobre manifesto_hash

Adotada a proteção na BD (abordagem A), usando exclusivamente funções nativas, sem instalar extensões:

```sql
pg_catalog.encode(
  pg_catalog.sha256(pg_catalog.convert_to(manifesto::text, 'UTF8')),
  'hex'
)
```

O contrato é o hash da representação textual do valor JSONB emitida pelo PostgreSQL. Não se inventou canonicalização nem se promete compatibilidade com RFC 8785, JSON.stringify ou versões futuras do servidor. O trigger compara o hash fornecido; não substitui silenciosamente um hash incorreto. Um rascunho pode ter hash ainda incompleto, mas não pode ser validado com hash divergente.

Verificado localmente no PostgreSQL 17.5 do PGlite 0.3.14: ordem de chaves e espaços do JSON de entrada não alteram os exemplos normalizados; Unicode e estruturas aninhadas são convertidos explicitamente para UTF-8. O resultado foi comparado com SHA-256 independente do Node sobre o texto devolvido pela BD. Valores `1` e `1.0` podem ser iguais como JSONB e produzir hashes diferentes, pois a escala numérica é preservada. Isso é parte deste contrato de representação, não uma equivalência semântica universal.

A documentação oficial descreve [SHA-256 nativo](https://www.postgresql.org/docs/16/functions-binarystring.html) e [normalização e preservação de escala no JSONB](https://www.postgresql.org/docs/16/datatype-json.html). Nenhum teste desta revisão foi executado no servidor real. Antes da aplicação, confirmar a versão e repetir os vetores no PostgreSQL de destino/homologação; numa atualização de versão do servidor, rever a representação antes de recalcular hashes históricos. A futura RPC deve obter/calcular o hash no servidor com esta mesma expressão e verificar o conteúdo do manifesto, a sua ligação às fontes e os bytes dos ficheiros.

## Segurança e imutabilidade

RLS ativo nas duas tabelas. `anon` e PUBLIC sem privilégios; `authenticated` apenas SELECT, com visibilidade por obra ou administração. Fontes consultam a versão pai. Não há policies de escrita. `service_role` recebe SELECT/INSERT/UPDATE/DELETE, mantendo os triggers; TRUNCATE não é concedido.

As duas funções novas são apenas funções de trigger, SECURITY DEFINER com search_path fixo. Não substituem futuras RPCs de negócio. As funções de autorização e auditoria existentes são pré-requisitos.

Versões validadas recusam qualquer UPDATE/DELETE, incluindo retrocesso a rascunho e UPDATE sem diferença. Fontes dessas versões recusam INSERT/UPDATE/DELETE. Cada mutação de fonte bloqueia a versão pai com FOR UPDATE, serializando-a com a validação. Uma revisão é sempre outro registo. Proprietários/superutilizadores capazes de alterar DDL ou desativar triggers continuam administradores de confiança.

### Limites que devem ser resolvidos antes da primeira validação real

1. Storage não foi modificado. Bucket/object_key/hash são referências; ainda não garantem preservação imutável dos bytes. Implementar retenção/imutabilidade e verificação de hash numa tarefa separada.
2. `documento_obra_id` é opcional e complementar à cópia dos metadados da fonte. Verifica-se a obra na associação, alteração da fonte e validação da versão, com bloqueio do documento durante essas operações. A FK RESTRICT bloqueia DELETE do documento referenciado, mas permite uma alteração **posterior** de `documentos_obra.obra_id`; ambos os comportamentos foram demonstrados nos testes locais. É necessária uma guarda específica, após preflight, antes de permitir versões reais validadas ligadas a documentos. Não se alterou a tabela legada nesta revisão. O registo da fonte validada continua imutável.
3. Não existem ainda RPCs que atribuam autores a partir da sessão, verifiquem o conteúdo económico/documental do manifesto ou autorizem validações. A verificação criptográfica na BD não substitui esse processo.

## Ficheiros e execução local

- Migration: `supabase/orcamento_versoes_etapa1.sql`.
- Rollback: `supabase/orcamento_versoes_etapa1_rollback.sql`.
- Testes: `tests/orcamento-versoes-etapa1.test.mjs`.
- Fixture: `tests/fixtures/orcamento-versoes-etapa1-base.sql`.

Com as dependências já declaradas em `tests/quadro-runtime/package.json` disponíveis:

```text
node --test tests/orcamento-versoes-etapa1.test.mjs
```

PGlite 0.3.14 executa PostgreSQL em memória. O teste não recebe ligação, URL ou credenciais Supabase. Autorização usa helpers locais controlados; auditoria usa a implementação existente extraída de `ativar_log_auditoria.sql`, sem executar o instalador legado.

As fixtures são sintéticas e reproduzem os contratos necessários, não todo o schema de produção. Há 18 itens e 9 resumos sintéticos, contrato e vínculo de planeamento, permitindo comparar dados, IDs e definições antes/depois. O teste não é certificação da produção. Concorrência entre sessões independentes não é exercitada pelo PGlite; os bloqueios devem ser verificados em PostgreSQL de homologação antes de qualquer aplicação autorizada.

Resultado local após revisão: 23 cenários aprovados, 24 testes contando o teste agregador; zero falhas ou omissões. Inclui fonte obrigatória, estrutura inválida mesmo havendo outra fonte válida, hash divergente, representação JSONB/UTF-8, risco de reatribuição documental, permissões, constraints, imutabilidade, auditoria e sua atomicidade, isolamento do legado e rollback. Nenhuma execução no Supabase. A simulação de estrutura inválida remove constraints apenas dentro de uma transação da fixture local, integralmente revertida.

## Aplicação futura — apenas checklist, sem execução nesta tarefa

1. **PRE-CHECK:** autorização explícita; confirmar projeto/branch/schema; nomes novos ainda ausentes; PKs/FKs e funções existentes; service_role com BYPASSRLS; schema grants; definição atual da auditoria; verificar não haver consumidores novos. Repetir testes de concorrência em homologação.
2. **BACKUP:** exportar definições e dados legados, grants/policies/triggers/funções; registar contagens, IDs e hashes, incluindo os 18 itens e 9 resumos. Testar recuperação do backup.
3. **MIGRATION:** executar o ficheiro integral numa transação, apenas quando autorizado. Não é idempotente: nomes preexistentes provocam erro, evitando assumir que objetos diferentes são compatíveis.
4. **PÓS-CHECK:** duas tabelas vazias; constraints, índices, RLS, grants e triggers esperados; mesmos valores/IDs/definições legados; testes de leitura e de bloqueio em homologação. Não popular nem ativar consumidores.
5. **ROLLBACK:** se as tabelas continuam vazias, executar o rollback integral. Obtém locks exclusivos e recusa tabelas com registos. DROP sem CASCADE recusa dependências adicionais e a transação evita remoção parcial. Se existirem dados, preservar backup e elaborar recuperação específica; não apagar evidência. O log existente nunca é removido.
