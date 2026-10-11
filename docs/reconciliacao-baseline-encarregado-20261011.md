# Reconciliação da baseline real do Encarregado — 11/10/2026

Base: 08affd17a88fd7aefcec15a165d0135983624bc6. Captura READ ONLY: 2026-10-11T13:46:33.300181+00:00. SHA-256 da captura: 4f259a904bf89bd983dfdd78241f040b4a511b8d6869abc0a360afe7faeee6a8. Nenhuma execução real nesta tarefa.

## Causa raiz

O bootstrap convertia CRLF para LF ao carregar as migrations e recriava Agenda a partir de um ficheiro formatado. md5(prosrc) refletia essa reconstrução local em vez da definição real instalada. Oito corpos coincidem byte a byte após normalizar exclusivamente CRLF→LF; Agenda tem todos os tokens SQL iguais à versão commitada, e a definição real coincide com o catálogo de 04/10. Nenhuma diferença lógica.

| Assinatura | Hash antigo | Hash real | Origem | Classificação | Diferença | Segurança |
|---|---|---|---|---|---|---|
| `folha_privado.facts(jsonb,date)` | `3eb9bc9ffe17363f30f925901a631c80` | `3eb9bc9ffe17363f30f925901a631c80` | folha_ponto_v2.sql | MATCH COM BASELINE CONHECIDA | Corpo coincidente sem transformação. | PASS |
| `folha_privado.linha(uuid,uuid,date,text)` | `8154e88e10b38921f0af4e0ba4e4da8e` | `2a2bf9de10694bd48fd6247e468061dc` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `folha_privado.local(uuid,uuid,boolean)` | `d2c83f8f24e1571a411da6663f907f97` | `65620aa6353d6507899becad35ae883a` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `folha_privado.normal(uuid,uuid,date)` | `4494cc93c7317ea0164da968d3cf7002` | `a76dcfb24f3924561d403eea452b27d7` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `folha_privado.save(jsonb,uuid,date,uuid,boolean)` | `811c7c791efe79a664f812855c7820e6` | `0a000683532abff274518f9318f8371f` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `public.fn_equipa_operar_v2(text,jsonb,boolean,text)` | `cb3ba9772a6959a628827c4076f800da` | `f9c99c4e66111219808a62dc9b9e61ba` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `public.fn_folha_contexto_v2(date,uuid)` | `3dcfd7360ec89cebf9f2d4b1fe5a9bc1` | `bbe53357ac9e13524866c1465d9e972e` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `public.fn_folha_operar_v2(text,jsonb,boolean,text)` | `7172ac4a5a13cb90a00cd890f39c16bd` | `d36cb485e24d1892f8a242c831c0f64a` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `public.fn_folha_pessoas_v2(date,uuid)` | `9cc4f3dffcf2c4899599015c8046ccf6` | `5b84c17ff9df855e933050ec609fcb1a` | folha_equipa_operacional.sql, main 37b95fa | DIFERENÇA NÃO FUNCIONAL | Exclusivamente CRLF→LF; igualdade byte a byte depois desta transformação. | PASS |
| `public.fn_listar_colegas_agenda()` | `93127401177f7763624f88b581eadf68` | `4a7f789e508a204be05aad1478d6ae0e` | Catálogo real 04/10, calendario_compromissos.sql e backup Folha V2 | DIFERENÇA NÃO FUNCIONAL | CRLF e formatação; todos os tokens SQL coincidem. | PASS |

## Diff textual/estrutural

Nas oito funções Folha, exatamente a transformação CRLF→LF produz o corpo esperado completo; nenhum espaço, literal, token ou comentário foi normalizado. facts coincide sem transformação. Os corpos completos, contratos e dependências estão no fixture, sem dados operacionais ou OIDs de produção. Agenda, após normalização apenas de finais de linha:

```diff
--- bootstrap-local
+++ captura-real
@@ -1,9 +1,13 @@

-  select u.id,u.nome,u.funcao
+  select
+    u.id,
+    u.nome,
+    u.funcao
   from public.utilizadores u
-  join public.utilizadores atual on atual.id=public.fn_utilizador_atual_id()
-  where coalesce(atual.ativo,true)
-    and u.empresa_id=atual.empresa_id
-    and coalesce(u.ativo,true)
-    and u.id<>atual.id
+  join public.utilizadores atual
+    on atual.id = public.fn_utilizador_atual_id()
+  where coalesce(atual.ativo, true)
+    and u.empresa_id = atual.empresa_id
+    and coalesce(u.ativo, true)
+    and u.id <> atual.id
   order by u.nome;
```

## Backups, migrations e segurança

primeline_equipa_backup.funcoes preserva sete versões anteriores a folha_equipa_operacional.sql; não é a baseline instalada depois desse rollout. primeline_folha_v2_backup.funcoes preserva Agenda. Outros backups consultados não contêm estas assinaturas. As oito versões atuais são do rollout Equipa/Folha aprovado e publicado no main 37b95fa; main cb6c91f mantém os scripts.

Owners postgres 10/10. facts é invoker/STABLE privado por desenho; restantes DEFINER. Nove search_paths pg_catalog. Agenda anterior usa public com tabelas/helper explicitamente qualificados por public, sem relações/helpers resolvidos no schema implícito; o pacote final usa pg_catalog. ACLs: helpers só postgres; cinco RPCs postgres + authenticated; PUBLIC/anon/service_role sem EXECUTE. Tenant, âmbito, ator ativo, revisões/locks e contratos preservados nos corpos conhecidos. Writer legado CLOSED, trigger habilitado e função preservada. Nenhuma estrutura parcial.

Catálogo: 19 dependências, 5 chamadores; nenhuma policy/view/trigger diretamente dependente. pg_depend não representa todas as chamadas PL/pgSQL: corpos completos e chamadores textuais também são evidência preservada.

## Correção dos gates

Precheck/backup/migration fixam SHA-256 da definição completa normalizada apenas CRLF→LF e todos os metadados críticos (owner, definer, search_path, linguagem, argumentos/defaults/retorno, volatility, parallel, strict, leakproof, ACL por nomes de papéis). Nenhum corpo formatado arbitrário/grant novo é aceite. Backup captura definição exata com CRLF, owner e ACL/metadados; migration exige igualdade exata com o backup. Rollback restaura e verifica definição byte a byte e metadados/ACL. Postcheck tolera apenas finais de linha no corpo e verifica owner/definer/search_path, além dos checks operacionais/ACL anteriores.

## Limites

Limpeza 11/10 encerrada e não repetida. Wanderson e jornadas não configurados. Nenhuma produção/main/deploy/Fase B ou alteração de HE/calendário. A execução local e a reprodução em segunda worktree são documentadas abaixo e na entrega final.

## Prova por definição completa

As nove definições fora de Agenda foram comparadas independentemente com pg_get_functiondef das migrations anteriores instaladas no bootstrap, antes de carregar a captura real. A comparação normaliza só CRLF→LF. Agenda real é idêntica ao corpo preservado no backup Folha V2 e no catálogo de 04/10. Nenhum drift inexplicado.

### folha_privado.facts(jsonb,date)

- SHA-256 da definição completa LF: `6f1b77b09ce6c0bd93182a4ca09b98f73a10a83a213b7e9ae5411aad1b4bcaec`.
- SHA-256 do corpo LF: `c6c1f14d425ef379ba54a1c799a2ed89482cb4c7cfb5ad984a3cf2eff46898ac`.
- Finais CRLF no corpo capturado: 0.
- Contrato e segurança: owner postgres, definer False, search_path=pg_catalog; ACL integral fixada no gate.

### folha_privado.linha(uuid,uuid,date,text)

- SHA-256 da definição completa LF: `0e7668583f3c3b78a4e9007515a9caceae70b491c9cdb4300f6d3ac4de25c100`.
- SHA-256 do corpo LF: `d2014e924d82be9137ef16f5d55a116f7c0baa5f891a7ad274fcefc08461264e`.
- Finais CRLF no corpo capturado: 47.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### folha_privado.local(uuid,uuid,boolean)

- SHA-256 da definição completa LF: `17d473f2cf300bc4dc4f64cf3920dc394dcd8284b317bf737b40abaf458ccec3`.
- SHA-256 do corpo LF: `a6c2c3ba5c04883d8e9c647daf8fbccb7d6f9330a25e17ba117909de16da2f5d`.
- Finais CRLF no corpo capturado: 32.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### folha_privado.normal(uuid,uuid,date)

- SHA-256 da definição completa LF: `ecd9239207649502d787aba88d5361f68a906a3f1c199dd9b6199b7e0f6f8b7c`.
- SHA-256 do corpo LF: `8621d9d51195a775cd9c15308cc6634830c0fe91d8644b8fa7149bde38cd98d6`.
- Finais CRLF no corpo capturado: 13.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### folha_privado.save(jsonb,uuid,date,uuid,boolean)

- SHA-256 da definição completa LF: `915febb0e4d9a88dffb0f145d75f7d9113c2eac34da4d9e35706806e698ffae9`.
- SHA-256 do corpo LF: `2d0049687892fc4bbe867a68953e5914fea97caeb3607d78c708cc4d774a96fa`.
- Finais CRLF no corpo capturado: 51.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### public.fn_equipa_operar_v2(text,jsonb,boolean,text)

- SHA-256 da definição completa LF: `089d09f54c6ccdeea061e00c2b66df23999c8f22a4a21e377d8ac3f2b61f61e3`.
- SHA-256 do corpo LF: `cb0fb6a8b7a3e965783d1ae454073f833fb9c5d821b5a569a5eb4591cfdc5da3`.
- Finais CRLF no corpo capturado: 80.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### public.fn_folha_contexto_v2(date,uuid)

- SHA-256 da definição completa LF: `075ff7cd2c48b93e64f2b00ac750d9fc74d3950e1f22b5fa2b583f958dc8ae2b`.
- SHA-256 do corpo LF: `851abc2cd16081ff06afe63527ca9ea3120971291fdd1bb9ec7d6eb67654493e`.
- Finais CRLF no corpo capturado: 59.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### public.fn_folha_operar_v2(text,jsonb,boolean,text)

- SHA-256 da definição completa LF: `1f04f313dfe5b29944d4448cbdf24277bbeca4b1e3ddab34de3ebf1b055c273b`.
- SHA-256 do corpo LF: `dbda2513acb869309c0859384fd668f0a7ad66d948b78240023c6e78f4e63139`.
- Finais CRLF no corpo capturado: 97.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### public.fn_folha_pessoas_v2(date,uuid)

- SHA-256 da definição completa LF: `41b62dfce8084230a2fbaea09321c8547edb6b3a1426cb5305cc86cc23079300`.
- SHA-256 do corpo LF: `d53de7d70369530b37d4de25379e949fac49633e42f40ec7854c9b5732862dec`.
- Finais CRLF no corpo capturado: 19.
- Contrato e segurança: owner postgres, definer True, search_path=pg_catalog; ACL integral fixada no gate.

### public.fn_listar_colegas_agenda()

- SHA-256 da definição completa LF: `d86c1f1219cb919d0827d916981ab5f1b8caaa427903a67e6f469d1b0d00cbf8`.
- SHA-256 do corpo LF: `a988ea8ab8de382ac8683fb6ae0a7f3d67300c7f65782204f219d1c83ef86563`.
- Finais CRLF no corpo capturado: 13.
- Contrato e segurança: owner postgres, definer True, search_path=public; ACL integral fixada no gate.

## Evidência dos backups anteriores

| Backup / assinatura | MD5 do corpo guardado | Relação com produção atual |
|---|---|---|
| primeline_equipa_backup.funcoes / `fn_folha_contexto_v2(date,uuid)` | `58fa982222bf0b96c61079525e27913b` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_equipa_backup.funcoes / `folha_privado.save(jsonb,uuid,date,uuid,boolean)` | `67fe72b685431d6a3aee73c72aa62a24` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_equipa_backup.funcoes / `folha_privado.local(uuid,uuid,boolean)` | `5abbb1b9b74b860512db9c892a2a7d08` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_equipa_backup.funcoes / `folha_privado.linha(uuid,uuid,date,text)` | `f55d8641949f5044e1a17f77ff30ff2b` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_equipa_backup.funcoes / `folha_privado.normal(uuid,uuid,date)` | `fae9f197c1cd185a7e63ada59889ac52` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_equipa_backup.funcoes / `fn_folha_pessoas_v2(date,uuid)` | `82dbe560981521db5c8a27840a4fdffc` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_equipa_backup.funcoes / `fn_folha_operar_v2(text,jsonb,boolean,text)` | `5b1a70e11cf1edd06a5f754206e47c8b` | Versão antecedente, substituída no rollout Equipa/Folha |
| primeline_folha_v2_backup.funcoes / `fn_listar_colegas_agenda()` | `4a7f789e508a204be05aad1478d6ae0e` | Igual byte a byte |

## Resultados locais

- Runner completo inicial: 452 PASS / 0 FAIL / 1 SKIP; dez suites browser PASS.
- Suite PostgreSQL após acrescentar a comparação independente: 23 PASS / 0 FAIL.
- Instalação CRLF, instalação LF, precheck, backup, postcheck, rollback vazio exato e reinstalação: PASS.
- Drift de corpo, owner, SECURITY DEFINER, search_path, volatility, strict e grants: recusado. Backup obsoleto e rollback após utilização: recusados.
- Screenshots inspecionadas: Folha/editor em 768×1024, confirmação em 1024×768 e editor externo em 768×1024; hierarquia/editor contextual/horários/total preservados. Suites abrangem 375×812, 768×1024, 1024×768, 820×1180 e 1440×900.
- `git diff --check`: PASS.
- O SKIP é o cenário sintético de importação com ficheiro real de 47 linhas; não é contabilizado como PASS.
- A confirmação da repetição integral em segunda worktree limpa no SHA commitado acompanha a entrega final. Logs/screenshots ficam fora do Git.

GO LOCAL para preparar o rollout usando estes scripts reconciliados, condicionado à configuração factual autorizada e aos gates reais. Nenhum comando real executado nesta tarefa.
