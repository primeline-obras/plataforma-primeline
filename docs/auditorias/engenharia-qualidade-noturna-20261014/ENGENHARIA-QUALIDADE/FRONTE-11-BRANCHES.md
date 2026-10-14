# Frente 11 — comparação das branches locais

Base funcional auditada: `2ae1f8a194f23d77bf0692d0a6d586566227298c`. Todas as comparações foram feitas por leitura de objetos Git; nenhum merge/reset/fetch. Ver COMPARACAO-BRANCHES.csv.

- `main` → `1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0`; commits exclusivos: 0; sobreposições: nenhuma.
- `feat/gestao-horas-integrada-20261013` → `2ae1f8a194f23d77bf0692d0a6d586566227298c`; commits exclusivos: 0; sobreposições: nenhuma.
- `urgent/planeamento-operacional-20260928` → `f0894e48933ef4b4a1f45a5745e064a942960348`; commits exclusivos: 24; sobreposições: index.html;src/app.js.
- `chore/fase-b-readiness-20261011` → `b7bf4c158e93cf455cc307097eef83d90e9c6a77`; commits exclusivos: 1; sobreposições: nenhuma.
- `fix/despesas-gerais-tenant-20261011` → `abc160d33328e305dfdd4d4748a2973765c18c0d`; commits exclusivos: 2; sobreposições: nenhuma.
- `codex/auditoria-global-noturna-20261014` → `63f98ddff6ca96e0c89dd0d4125d85a4d29f12b3`; commits exclusivos: 12; sobreposições: nenhuma.

## Proposta de integração, não executada

Preservar a sequência AD15 → AD14 → AD13 → AD03 e as dependências HR27/FALTOU/leitores/conferência/destinos/custos/plano/contextos. Fase B e Débitos Diretos são pacotes independentes: exigir catálogo/precheck próprio antes de qualquer proposta real. Comparar qualquer redefinição de helper/RPC com a versão cumulativa de Horas; coincidência de nome não prova equivalência. Repetir regressões em base combinada descartável apenas quando essa integração for autorizada. Não transportar a branch antiga de Planeamento por cópia cega de ficheiros partilhados.

Limitação: esta frente verifica divergência/ancestralidade e ficheiros; não certifica o comportamento de uma integração ainda inexistente.
