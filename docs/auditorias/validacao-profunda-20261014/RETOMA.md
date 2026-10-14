# Retoma

Branch `codex/validacao-profunda-203-20261014`; base `63f98ddff6ca96e0c89dd0d4125d85a4d29f12b3`. Produto preservado.

Reexecutar `tests/deep-validation-register.py` depois de novas evidências. Continuar frentes independentes: segunda passagem REST; importadores/documentos/alertas/invariantes; screenshots e concorrência; comparação de branches; revisão final. Não encerrar por 24 pares de serviços locais bloqueados. Não chamar a missão concluída enquanto houver trabalho seguro pertinente pendente. Manter contagens do JSON em vez de somar resultados de todas as tentativas.

Runtimes locais: Node/Python no cache Codex; PG17.6 em TEMP/primeline-doc-guard-pg176/package/native/bin; pg em TEMP/primeline-medicina-test-deps/runtime/node_modules; PostgREST em TEMP/primeline-authorization-postgrest. Nenhuma credencial real necessária. Não instalar nem executar scripts contra produção.

Progresso posterior ao checkpoint d93435c: RH nativo5 cenários/9 contagens; metadados RPC9 cenários/13 contagens; RLS direta2 controlos PASS/2 recusas FAIL na baseline, sem prova de produção; compensação PDF após2xx é P2 condicional. Matriz203:172PASS/6FAIL/1contrato/24bloqueados, com2FAIL parciais de metadados dentro dos bloqueados. Consultar RLS-DOCUMENTAL-BASELINE.md e coluna resultado_parcial. Continuar fila independente; não encerrar a missão por estes bloqueios.
