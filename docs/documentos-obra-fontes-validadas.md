# Proteção da obra de documentos usados por versões validadas

Estado: preparada e testada localmente; **não aplicada na BD real**.

## Base e âmbito

Preflight reutilizado: branch `urgent/planeamento-operacional-20260928`, HEAD
`9b84e7009cebb492fc7e92a34c3789ed6cfce90c`, working tree inicialmente limpo.
As definições SQL locais foram relidas e comparadas com o levantamento real já
concluído: validação com `FOR SHARE OF d`, fontes com lock na versão e `FOR SHARE`
no documento, FK documental `ON DELETE RESTRICT`, auditoria documental existente.
Esta implementação não executou novas consultas SQL nem alterações no Supabase.

A tarefa explícita autoriza esta migration isolada, apesar da orientação genérica
de `instrucoes.txt` para apenas frontend. Não se altera a migration da Etapa 1,
Storage, frontend, `fn_apagar_documento_obra`, policies ou auditoria.

## Regra

`trg_impedir_reatribuicao_documento_validado` é `BEFORE UPDATE OF obra_id`.
Se a obra não muda, retorna imediatamente. Se existir referência a uma versão
`validada`, recusa com SQLSTATE `23514`. Rascunhos, versões em validação ou
rejeitadas não congelam o documento. Outros campos mantêm o comportamento atual.
DELETE permanece exclusivamente sujeito à FK e às regras existentes.

A função é `VOLATILE SECURITY DEFINER`, com proprietário `postgres`, nomes de
tabelas qualificados e `search_path=pg_catalog,pg_temp`. `row_security=off` não
concede bypass: evita uma leitura silenciosamente filtrada caso os privilégios
do proprietário deixem de permitir a consulta integral. EXECUTE é revogado de
PUBLIC, anon, authenticated e service_role; o trigger continua a executar.

## Concorrência

O UPDATE bloqueia a linha do documento antes de executar o trigger. Esse lock
conflita com o `FOR SHARE` já usado pela validação e permanece até terminar a
transação. Não se acrescentam advisory locks, locks de versão ou tabelas auxiliares.

1. **Validação primeiro:** mantém `FOR SHARE` no documento; a reatribuição espera.
   Após COMMIT da validação, a consulta VOLATILE em READ COMMITTED vê o estado
   confirmado e recusa a mudança. Se a validação fizer ROLLBACK, a mudança pode seguir.
2. **Reatribuição primeiro:** a validação espera pelo documento. Após COMMIT da
   mudança, o trigger existente reconsulta a obra e recusa a validação divergente.
   Se a mudança fizer ROLLBACK, a validação pode seguir.

READ COMMITTED é essencial para atualizar o snapshot depois da espera. Por decisão
expressa do utilizador, uma mudança efetiva de obra em REPEATABLE READ ou SERIALIZABLE
falha com `40001`, exigindo **nova transação READ COMMITTED**. Isto também se aplica
a documentos sem fontes. Repetir no mesmo isolamento não resolve. Outros campos e
atribuição da mesma obra continuam permitidos. READ UNCOMMITTED tem semântica de
READ COMMITTED no PostgreSQL e é aceite.

Referências: [volatilidade e snapshots](https://www.postgresql.org/docs/17/xfunc-volatility.html),
[isolamento](https://www.postgresql.org/docs/17/transaction-iso.html).

## Testes executados

```powershell
node --test tests/documentos-obra-fontes-validadas.test.mjs tests/orcamento-versoes-etapa1.test.mjs
```

37 testes aprovados, zero falhas/omissões, incluindo agregadores. O teste novo
compara dados, policies, constraints, índices e funções existentes antes/depois;
usa quatro documentos **sintéticos**, não os quatro registos reais. Verifica RLS,
service_role, auditoria existente, atomicidade, estados, outros campos, FK,
isolamentos e rollback. O teste antigo continua a demonstrar a limitação da
Etapa 1 isoladamente; a nova suite aplica também esta proteção.

Concorrência executada em PostgreSQL **17.6**, num cluster portátil temporário,
apenas `127.0.0.1:55439`, sem serviço instalado e sem ligação ao Supabase:

```powershell
$env:DOC_GUARD_LOCAL_TEST = '1'
node --test tests/documentos-obra-fontes-validadas-concorrencia.test.mjs
```

6 testes aprovados, zero falhas/omissões, incluindo agregador. As sessões são
independentes; o teste observa `pg_blocking_pids` antes de libertar o primeiro
lock. Cobre as duas ordens com COMMIT e ROLLBACK e a recusa de snapshot fixo.
O cliente de teste implementa apenas simple-query TCP/trust em loopback; não
aceita host remoto, URL ou credenciais. Requer cluster novo (roles da fixture
ainda ausentes); recusa BD `primeline_doc_guard_test` preexistente. Porta alternativa
local: `DOC_GUARD_PG_PORT`. Sem opt-in, o teste nativo fica explicitamente omitido.

Distribuição portátil de teste: `@embedded-postgres/windows-x64@17.6.0-beta.15`,
extraída na pasta temporária e verificada pelo SHA-512 publicado no npm. Não é
dependência da aplicação nem modifica package.json/lockfiles do repositório.

## Aplicação e rollback futuros

Antes de aplicar, repetir em leitura o preflight real e confirmar que as definições
dos triggers de validação e da auditoria não mudaram, os nomes novos estão livres,
o executor é o proprietário de confiança e não existem divergências validadas.
Guardar definições e snapshot dos quatro documentos e das tabelas económicas.

Aplicar somente `supabase/documentos_obra_fontes_validadas.sql`, após autorização.
Pós-check: trigger/função, grants, policies inalteradas e igualdade integral de dados.
Não criar fontes/versões reais para testar.

O rollback isolado remove apenas trigger e função, sem CASCADE, sem modificar
dados ou auditoria. Recusa executar quando existem documentos associados a versões
validadas: retirar a proteção nessa situação exige um plano específico que preserve
a integridade. Os locks exclusivos coordenam essa verificação com operações em curso.

**Storage imutável e verificação dos bytes continuam pendentes. Esta proteção,
isoladamente, não autoriza a primeira versão ORCA real.**
