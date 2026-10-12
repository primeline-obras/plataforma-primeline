# Auditoria adversarial local — avaliação diária — 12/10/2026

## Veredicto

**NO-GO para preparar aplicação real.** Quatro P1 confirmados. Nenhum P0 confirmado. Nenhuma correção da implementação foi efetuada.

Candidato integralmente preservado: `feat/folha-avaliacao-diaria-20261012`, `a27322708af530865a0074a25e961579c3becef4`. Base do main: `1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0`.

Branch local das provas/relatório: `audit/folha-avaliacao-diaria-20261012`. Não houve SQL real, ativação real, push, merge ou deploy. As ativações/ataques descritos ocorreram exclusivamente no PostgreSQL 17.6 descartável com dados sintéticos; cada ataque de dados foi isolado por rollback.

## PASS/FAIL por seção solicitada

| Seção | Resultado | Evidência / limite |
|---|---|---|
| 1. Diff completo | FAIL | Escopo dos 12 ficheiros e definições completas corretos; P1 funcionais abaixo impedem aprovação. Nenhum frontend ou outro módulo modificado. |
| 2. Reentrância/estado parcial | PASS | Nunca instalado, instalação, reexecução recusada, falha após DDL revertida, nome ocupado recusado e schema sem ativação comprovados. |
| 3. Dados existentes | PASS | Instalação/rollback/reinstalação sobre dados não vazios: 1 folha anterior, 1 HE anterior, 1 payroll anterior e restantes tabelas idênticas ao backup. Intervalos, expected=480, minutes=540 preservados. |
| 4. Ativação | FAIL | Corte, idempotência, uma vez por empresa, histórico e atomicidade funcionam; configuração incoerente é aceita e versionada (P1-02). |
| 5. Vigência de horários | PASS | Intervalos [desde,até), lock por obra, sobreposição recusada, snapshot imutável, tenant/FKs e futuros recusados. Fronteiras e correção histórica comprovadas. |
| 6. Constraints/invariantes | FAIL | Quatro estados inválidos aceites, incluindo regular com falta e snapshot JSON null (P1-03). |
| 7. Misto/dupla contagem | PASS | 3 registos factuais: A=240, B=90, C=90 minutos; 420 total, esperado diário 480; misto agrega normal+personalizado uma vez. Não há HE por destino. |
| 8. HE | PASS no fluxo legítimo | Pendente/validada bloqueiam; não considerada preserva outras pendências e realizado; edição invalida decisão com histórico anterior preservado. O contexto do histórico possui P1-04. |
| 9. Fecho/payroll | PASS no fluxo legítimo | Normal preservado; personalizado/misto usam gate diário; inativa não interfere; referência pendente/HE bloqueiam; fechado impede alteração; reabertura não recaptura. Não foi adicionado cálculo monetário. |
| 10. Perfis técnicos | FAIL / BLOQUEADOR | Encarregado, Diretor, Adjunto e Preparador próprios sem permanência gravam com referência pendente; não existe resolução histórica segura para a origem (P1-01). |
| 11. Testes não verdes | FAIL / pendente | REST local continua sem PostgREST; dois browsers obsoletos reproduzidos também em main. Classificação detalhada abaixo. |
| 12. Rollback | PASS | Antes de ativação restaura definição/ACL/owner/constraints com dados anteriores não vazios; após ativação/histórico recusa. Sem force/CASCADE destrutivo. |
| 13. Segurança | FAIL | SD/search_path/ACL/RLS, autoria real, replay e DML direto funcionam em SQL local; histórico aceita obra de outro tenant pela RPC (P1-04). JWT/HTTP não certificado pelo actor sintético. |
| 14. Resultado | NO-GO | Corrigir P1-02/03/04 e fechar a decisão funcional de P1-01 antes de nova revisão. |

## P1-01 — referência diária dos perfis técnicos não resolvida

Local: `supabase/folha_avaliacao_diaria.sql`, função `folha_privado.diaria_referencia`, linhas 106–123.

A função utiliza exclusivamente a permanência por pessoa/data. `elegivel_equipa` e o contrato de permanência operacional representam Pedreiro/Servente; a responsabilidade técnica por obra não é uma permanência principal histórica.

Prova com vínculos únicos colaborador→utilizador e callers autenticados:

| Perfil | Confirmação factual | Referência | Esperado | Motivo |
|---|---|---|---|---|
| Encarregado | committed=true | pendente | NULL | origem_principal_nao_inequivoca |
| Diretor de obra | committed=true | pendente | NULL | origem_principal_nao_inequivoca |
| Adjunto | committed=true | pendente | NULL | origem_principal_nao_inequivoca |
| Preparador | committed=true | pendente | NULL | origem_principal_nao_inequivoca |

Não há jornada inventada: o fail-closed funciona. A lacuna é funcional: o contrato não resolve automaticamente esses utilizadores e bloqueia o fecho até regularização manual. A possibilidade de corrigir manualmente cada dia não substitui a origem histórica exigida.

**PARAR implementação/rollout neste ponto funcional.** Não ampliar `elegivel_equipa` nem permanências. Precisamos de uma decisão separada sobre uma referência principal histórica legítima para esses perfis.

## P1-02 — ativação não revalida a configuração completa

Local: `fn_folha_diaria_gestao_v2`, linhas 242–247 e 290–295.

A ativação executa `PERFORM folha_privado.facts(schedule_row.intervals,today)` e descarta o resultado. Não exige carga declarada igual à soma, dois períodos normais distintos ou ausência de intervalo aberto. A validação do precheck de instalação não resolve alterações posteriores antes da ativação.

Prova isolada após instalação, antes de ativar a empresa sintética:

- configuração existente: 08:00–12:00, período manhã;
- soma real do horário: 240 minutos;
- expected_minutes declarado: 480;
- RPC autenticada `daily_activation`: **committed=true**;
- versão-base criada com essa configuração incoerente.

A fixture foi criada por owner, sem desativar os triggers de integridade de tenant; a RPC de ativação foi executada como authenticated com perfil Administrativo. Não alegamos que o formulário normal produza essa configuração. A falha é a garantia independente exigida da ativação.

Correção necessária, não executada: repetir integralmente a validação de horário dentro da operação controlada; uma configuração inválida deve abortar a ativação inteira.

## P1-03 — constraints permitem estados impossíveis

Local: tabela `folha_avaliacoes_diarias`, linhas 33–66.

Ataques por owner numa transação isolada; a escrita direta por authenticated permanece recusada. Esta prova testa a integridade do modelo, sem confundi-la com bypass da aplicação.

| Combinação | Resultado exigido | Resultado real |
|---|---|---|
| Capturada sem snapshot SQL NULL | Recusar | Recusada |
| Capturada com snapshot JSON null | Recusar | **ACEITA** |
| Pendente com expected preenchido | Recusar | Recusada |
| Regular com falta de 30 minutos | Recusar | **ACEITA** |
| Regular com excedente e HE pendente | Recusar | **ACEITA** |
| HE validada sem autor | Recusar | Recusada |
| HE não considerada sem decisão | Recusar | Recusada |
| ativa=false com estado regular | Recusar | Recusada |
| Duplicada empresa/pessoa/data | Recusar | Recusada |
| Fingerprint inválido | Recusar | Recusada |
| Tenant cruzado na avaliação | Recusar | Recusada |
| HE validada com excedente NULL | Recusar | **ACEITA** |

Causas: ausência de compatibilidade estado↔minutos/pendências, `IS NOT NULL` aceita JSON null, e CHECK de HE pode resultar SQL NULL quando excedente é NULL; PostgreSQL aceita CHECK NULL.

Correção necessária, não executada: checks completos e resistentes a NULL, forma válida de snapshot e compatibilidades do estado/HE/pendências. Não abrir DML para corrigir isto.

## P1-04 — obra de outro tenant no histórico de decisão HE

Local: `fn_folha_diaria_gestao_v2`, declaração de `w`, ramo HE e INSERT em `folha_gestao_historico` (linhas 277–284 e 314).

A ação global aceita `p_dados.work_id`. No ramo HE não valida essa obra nem exige NULL; usa-a posteriormente no histórico.

Prova **pela RPC authenticated**, sem alteração direta da tabela de histórico:

- actor e avaliação da empresa sintética 1;
- `daily_he_validate` com work_id de uma obra da empresa sintética 2;
- resposta **committed=true**;
- histórico persistido dentro da transação: empresa_id=empresa 1, obra_id ligado à empresa 2;
- rollback final do ataque.

Não foi criada folha_he nem pagamento. A falha é a integridade/contexto do histórico e a entrada de uma obra arbitrária numa decisão diária global. Não demonstramos divulgação de dados ao outro tenant.

Correção necessária, não executada: ações globais não devem aceitar contexto de obra arbitrário. Preservar o work_id explicitamente legitimado da correção de referência; validar o âmbito de cada ação e o tenant do histórico.

## P2

1. **DELETE de manutenção silenciosamente cancelado antes da ativação.** `diaria_config_guardar`, linhas 206–218, retorna NEW inclusive em DELETE. Com a empresa desativada, `DELETE FROM folha_horarios ... RETURNING` por owner remove 0 linhas, sem erro. Não existe caminho frontend de DELETE autorizado. É uma regressão do caminho de manutenção; não altera dados durante a instalação.
2. **Lacuna REST local.** `QUADRO_POSTGREST` ausente. A suite `encarregado-autorizacao-rest.mjs` deveria provar JWT→role, filtros/UUID/colunas sem exposição RH/financeira, RPC mínima, RPCs financeiras recusadas e PATCH/DELETE/INSERT legado bloqueados. Não testa diretamente as RPCs diárias novas. Classificação: bloqueador de evidência de integração antes da BD real; não é um defeito SQL comprovado. Requer também provas REST específicas dos novos endpoints, roles, autoria real e NULL/revisões. O fixture `test.actor` é um substituto sintético, não prova criptográfica de identidade JWT.
3. **Browsers obsoletos a corrigir separadamente:**
   - `attendance-security-visibility-browser.mjs:35`: procura `[data-management-tab=tasks]`, aba já removida;
   - `folha-equipa-operacional-browser.mjs:28/41`: mock só trata `save`; frontend usa `periods_save`; facts.p nunca é preenchido.

Não foram ignorados: executámos ambos numa exportação temporária do main de base (`1c5fa5b...`). Ambos terminaram com exit=1 e o mesmo timeout. 57 ficheiros JS/CSS e os dois scripts de teste foram comparados e são idênticos ao candidato, desconsiderando somente CRLF/LF. Nenhuma nova funcionalidade de UI foi implementada para contornar os mocks.

## Revisão estrutural dos 12 ficheiros

- Cinco SQLs completos, dois testes, quatro fixtures técnicas e documentação; não há dados reais no Git.
- Funções apresentadas integralmente, sem reescrita de corpos instalados por replace/EXECUTE de patch.
- Assinaturas públicas existentes preservadas; RPC diária é aditiva. O corpo de gestão preservado mantém as ações existentes.
- SECURITY DEFINER e search_path pg_catalog controlados e conferidos pelo pós-check; helpers internos sem EXECUTE de aplicação.
- RLS nas duas tabelas novas, sem acesso/DML direto de aplicação. Guards usam executor real, não GUC autorizador.
- Drop do CHECK anterior é seguido de CHECK ampliado; rollback restaura a definição anterior. Não se elimina qualquer tabela antiga.
- DELETE existente do lote permanece dirigido a uma pessoa/data/obra com revisão e preservação de histórico. Não há DELETE de factos históricos na instalação.
- Não há atualização massiva de folhas/HE/ausências/permanências/Quadro/horários durante instalação, nem criação de avaliações/versões-base antes de ativação.
- Não foram identificados novos cálculos monetários nem alterações em outros módulos. Os P1/P2 acima limitam esta conclusão estrutural.

## Queries de prova da instalação

Executadas apenas no PostgreSQL local. O pós-check compara **todas as linhas de cada tabela** com `primeline_diaria_backup.dados`; para configuração, desconsidera somente as quatro colunas novas inicialmente NULL. A comparação passou com dados anteriores não vazios e após rollback/reinstalação.

```sql
SELECT count(*) FROM public.folha_registos;
SELECT count(*) FROM public.folha_he;
SELECT count(*) FROM public.folha_vencimentos;
SELECT intervals, expected_minutes, minutes
FROM public.folha_registos WHERE id = :id_sintetico;
SELECT count(*) FROM public.folha_avaliacoes_diarias;
SELECT count(*) FROM public.folha_horarios_versoes;
SELECT count(*) FROM public.folha_config_empresa
WHERE avaliacao_diaria_data_ativacao IS NOT NULL;
```

Resultado imediatamente após instalação: folha=1/HE=1/payroll=1 preservados; expected=480/minutes=540 inalterados; avaliação=0/versões=0/empresas ativadas=0. Ausências, permanências, Quadros, históricos, horários e ledger anteriores também passaram na comparação integral com o backup.

**Instalação da migration ≠ ativação do mecanismo.** O P2 do DELETE é uma alteração de comportamento de manutenção, não uma ativação automática.

## Vigência e contagem

O predicado real de resolução é `vigente_desde <= data AND (vigente_ate IS NULL OR vigente_ate > data)`.

Teste literal de fronteira: 15/10→X, 20/10→Y, 25/10→Y. Como a máquina está em 12/10 e futuros são proibidos, o cenário literal usa VALUES para provar o predicado temporal; não alegamos confirmação futura de ponto. O resolver/RPC reais foram testados também com datas históricas relativas e correção retroativa, preservando snapshots.

Multiobra: A tem dois intervalos num registo (240 minutos), B um (90), C um (90); total 420. Personalizados mantêm expected factual NULL; avaliação tem expected=480 uma vez. `payroll_facts` substitui o gate por dia, sem somar esperado por destino; uma avaliação inativa deixa de participar. O total factual existente continua obtido de sheets, não somando novamente daily_evaluations.minutes.

## Rollback

A condição explícita de recusa é a existência de **qualquer** avaliação diária, versão de horário ou empresa com corte de ativação preenchido. Há ainda recusa de drift das tabelas anteriores/backup exposto.

Antes da ativação: rollback e reinstalação passaram com folha/HE/payroll anteriores não vazios, restaurando funções/ACL/owners e constraint. Depois da ativação sintética: `DAILY_ROLLBACK_UNSAFE_AFTER_ACTIVATION`, sem apagar referência ou história. Não existe force que destrua histórico.

## Testes e significado dos resultados

Comandos:

```text
node --test tests/attendance-daily-adversarial.test.mjs tests/attendance-daily-static.test.mjs
node tests/attendance-daily-main-browser-audit.mjs
```

As provas de reprodução dos defeitos afirmam a ocorrência do comportamento indevido e imprimem `contract: FAIL`. Um teste de reprodução passar significa que o defeito foi reproduzido, **não que o candidato foi aprovado**.

Nova implementação/correção: nenhuma. O diff da auditoria contém apenas este relatório e dois scripts de provas; SQL, frontend e os 12 ficheiros do candidato ficam intactos. Não houve SQL real, ativação real ou publicação.

## Próxima decisão

**NO-GO.** Fechar primeiro a origem histórica dos perfis técnicos com autorização funcional separada; corrigir validação de ativação, invariantes e âmbito/tenant do histórico; reexecutar provas de rejeição e integração REST. Não preparar aplicação real a partir deste SHA sem nova revisão.
Execução final: **66 testes/provas locais passaram como reprodução e regressão**, 0 falhas de harness, 0 skips. Os quatro P1 continuam reproduzidos e não corrigidos; estes números não constituem aprovação do contrato. Os dois browsers de main terminaram com exit=1 conforme a falha preexistente investigada. git diff --check foi executado antes do commit de relatório/provas.
