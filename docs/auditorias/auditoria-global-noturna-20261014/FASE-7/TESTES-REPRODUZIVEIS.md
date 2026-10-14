# Testes reproduzíveis — somente local

Node empacotado, pg17.6 e módulo pg já presentes em TEMP; Playwright/Edge usados nas fases anteriores. Não instalar ferramentas com aprovação externa. Variáveis apontam para binários locais, nunca para produção.

```powershell
$env:QUADRO_PG_BIN=Join-Path $env:TEMP 'primeline-doc-guard-pg176\package\native\bin'
$env:QUADRO_TEST_DEPS=Join-Path $env:TEMP 'primeline-medicina-test-deps\runtime\node_modules'
node tests/night-phase3-rh-run.mjs
node --test tests/night-phase3-finance.test.mjs
node --test tests/night-phase3-procurement.test.mjs tests/session-boundary.test.mjs tests/procurement-planning-pending-consultations.test.mjs tests/planning-operational.test.mjs
node --test tests/night-phase5-profiles.test.mjs
node --test tests/night-phase7-rh-batch.test.mjs
```

Final:299+9+29+8+5=350 contagens Node,0FAIL/0SKIP. Pais de grupos incluídos; não350 operações independentes nem cobertura única de toda plataforma. Cinco novas famílias/suites, reusando o bootstrap seguro. Regeneradores night-mission-* só escrevem matrizes/documentação Fases3–7; não executar geradores antigos que sobrescrevem Fases1/2.

Clusters localhost/porta livre/trust apenas descartável, parados em finally, não eliminados. Auth na fixture usa test.actor, não tokens reais. Finança usa helpers autorizados sintéticos, portanto não certificado cross-tenant. Cadastro/importRH usam writers reais e roles por empresa; dependencia do criador do ficheirocampos_completos explicitada.

As asserções de diagnóstico de C01/C02 e P1 antigo verificam a falha observada e são classificadas FALHA/VULNERABILIDADE, não aprovação de segurança. Não alterar expectativas para mascarar o resultado. Nenhuma nova cargaHTML/exploração foi necessária; evidênciasFase2 preservadas.
