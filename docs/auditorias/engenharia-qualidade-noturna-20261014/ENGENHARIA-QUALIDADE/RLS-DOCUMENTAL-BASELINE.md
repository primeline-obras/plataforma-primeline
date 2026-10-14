# RLS documental — corroboração local relacionada com N-SEC-02

## Resultado e limite

**P1 na baseline reconstruída. Catálogo hospedado não validado. Produto inalterado.**

Dois controlos próprios passam; duas recusas estrangeiras falham para Gestão/Gerência. O teste usa role authenticated, row_security=on, rolbypassrls=false e documentos_obra com RLS ativo. O ator pertence à empresa1, a obra/documento à empresa2. Nenhuma escrita é feita pela operação avaliada e nenhum byte é descarregado.

Provas: EVIDENCIAS-DOCUMENTOS-DML-RLS.json e logs/DOCUMENTOS-DML-RLS.txt. O Node apresenta8 contagens:5 PASS/3 FAIL, incluindo o grupo pai que falha. São2 falhas de cenário, não3 causas.

## Caminhos diferentes

- A policy capturada pl_admin_total é permissiva, FOR ALL, USING/WITH CHECK fn_e_admin().
- Os papéis Gestão/Gerência satisfazem esse helper sem um predicado sobre a empresa do documento.
- O centro documental faz GET/POST direto a documentos_obra em src/documents.js.
- fn_registar_documento_obra e fn_apagar_documento_obra atuais têm guarda de alvo/tenant; os9 cenários específicos de RPC passaram. Isso não protege automaticamente a rota DML.
- Os scripts posteriores revistos não substituem documentos_obra RLS; ainda assim, não se assume que o projeto hospedado tenha exatamente o catálogo reconstruído.

A policy vem da baseline20261004. Não foi demonstrado que a Gestão Integrada de Horas introduziu este comportamento. Existe relação com N-SEC-02, mas não se equipara automaticamente a toda hipótese histórica de reaplicação de SQL.

## Próximo gate autorizado futuramente

Confirmar o conjunto completo de policies, permissividade, grants de tabela/coluna, owner, FORCE RLS e triggers no catálogo real, quando autorizado. Não atualizar um fingerprint para fazer passar e não executar essa consulta nesta missão.

Se o conjunto ainda permitir o comportamento, preparar correção isolada de RLS. Não basta adicionar outra policy PERMISSIVE por empresa: a policy administrativa continua a autorizar pelo OR. É necessário restringir a combinação efetiva por tenant, com qualificação coerente de USING/WITH CHECK e empresa derivada do ator/alvo legítimo, preservando permissões dentro da empresa.

Aceitação futura: Gestão/Gerência continuam a consultar documentos próprios; leitura estrangeira devolve0 linhas; escritas estrangeiras são recusadas sem efeitos; restantes perfis mantêm o âmbito aprovado. Testar também a rota DML, além das RPCs. Auth/Storage completo continua pendente.

## Contagens sem falso fecho

A matriz203 mantém179 pares backend executados (172PASS/6FAIL/1contrato) e24 fluxos completos bloqueados. Dentro destes últimos,2 pares DOCUMENT têm FAIL parcial de metadados numa coluna separada. Não são mais dois pares nem se tornam aprovados pela falta do Storage.
