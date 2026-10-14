# Checkpoint WIP — Gestão Integrada de Horas — 14/10/2026

Branch: feat/gestao-horas-integrada-20261013.
Base: 3aef80f6e43b69bfa08a123912c4698fd6c4c517.
Estado: implementação local INCOMPLETA; não instalar nem publicar.

Preservação: 5 ficheiros modificados e 61 novos, inspecionados antes deste commit. Não foram encontrados candidatos a credenciais; fixtures são sintéticas. Caminhos locais de runtime e dependências de teste não são credenciais. Nenhum backup real ou captura de produção incluído.

Inclui seis pacotes locais completos de SQL/precheck/backup/postcheck/rollback: destino operacional, conferência externa, referências controladas, mapas/custos HR-31, plano integrado e contextos operacionais; componentes editor/equipa/Excel não montados em app.js; geradores e testes correspondentes.

Último log recuperado: 276 testes, 273 PASS e 3 FAIL (dois subtestes e agregador). TEAM: ADDON_DATA_DRIFT ao chamar pós-check de instalação depois de alterações funcionais. EXTERNAL inativo: 25P02 por transação abortada anterior. A investigação deve confirmar a deriva e preservar os checks, sem mudar expectativas para esconder falhas. Resultados anteriores não certificam as últimas alterações.

Verificações de recuperação: git diff --check sem erros; 19 JS/MJS com sintaxe válida; 30 SQL sem delimitadores $$ desequilibrados; nenhum ficheiro vazio. Isso não substitui execução PostgreSQL.

Retoma: investigar isolamento/ordem do pós-check e rollback, executar os casos afetados e regressão integrada; rever lock/releitura do ator e empresa nas RPCs e consistência das leituras; testar concorrência. Depois completar integração operacional e apresentar modelos finais para aprovação antes da montagem definitiva. Estimativas HR-31 pendentes não bloqueiam validação factual.

Nenhum SQL real, push, merge ou deploy autorizado/executado nesta preservação. Não descartar o trabalho. Commit WIP deliberadamente preserva testes falhados.
