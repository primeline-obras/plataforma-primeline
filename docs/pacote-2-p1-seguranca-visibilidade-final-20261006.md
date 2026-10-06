# Pacote 2 — fecho dos dois P1 e do P2 ADM

## A–D. Identidade, preservação e independência

Branch: `fix/pacote-2-p1-seguranca-visibilidade-final-20261006`, criada exatamente de `c250283d84feef7034867e18bae5997b3424772d`. O SHA final é o commit desta entrega, identificado por `git log -1`.

Auditoria anterior preservada, remoto reconfirmado: `audit/pacote-2-regras-adm-final-20261006` em `3a239cf0783b6f84e9d2e1162a6c8153b43dd556`. Nenhum ficheiro dessa branch foi alterado.

Dois commits separados:

1. Documental: `cec13e621af6cb299bcc23e0536a2a6531efa784`, `fix(documents): isolate RH metadata and storage by company`.
2. Folha/HE/review: commit que contém este relatório, `fix(attendance): minimize HE payloads and reconcile special day review`.

Prova sobre main: `origin/main = 3df019a2f2813c0cbf7f36a8d13000431d33dd50`. Criado worktree temporário detached nesse SHA; `git cherry-pick cec13e6...` sem conflitos, resultado `b799a0fc6c1fd714376cb6df8111a88660aa53da`, working tree limpo. Suite documental nesse worktree: **9 PASS / 0 FAIL**. Worktree temporário removido depois da prova. Main não foi movida.

## E–H. Metadata, policies e Storage

Causa confirmada no catálogo preservado de 04/10 e scripts: `pl_documentos_rh` autoriza por tipo/papel sem ownership. Outras policies permissivas combinam por OR; corrigir apenas essa policy não fecha `pl_admin_total`. Storage RH validava path/papel, sem provar empresa do UUID. `ausencias_anexos_rh` tinha o mesmo problema por ausência.

| Policy de documentos existente | Depois |
|---|---|
| documentos_insert / documentos_select | Preservadas; sujeitas à nova guarda restritiva |
| pl_admin_total | Preservada; OR amplo não ultrapassa a guarda |
| pl_documentos_empresa_insert / select | Preservadas; guarda adicional |
| pl_documentos_workflow_insert / select | Preservadas; documentos de obra legítimos mantidos |
| pl_documentos_rh | Empresa atual = documento = entidade no tipo correto |
| rh_empresa_guard, nova RESTRICTIVE ALL | Empresa atual em metadata; colaborador/viatura com ownership confirmado |

`rh_anexo_empresa_guard` protege anexos através de ausência → colaborador → empresa. `rh_storage_empresa_guard`, RESTRICTIVE ALL, protege bucket `documentos`, namespace `rh`, UUID colaborador/viatura/ausência. UUID externo conhecido, tipo errado, path vazio/dot/traversal e formato inválido são recusados. Helpers booleanos SECURITY DEFINER em schema privado, search_path seguro, predicados acessíveis apenas a authenticated para aplicação do RLS; nenhum reader público novo.

Inventário Storage conhecido nos scripts: `documentos_storage_select/insert` para obra e `documentos_rh_storage_select/insert` para RH. A guarda aplica-se a TODAS as policies existentes: não elimina regras de obra e não cria permissões UPDATE/MOVE/DELETE. Sem regra permissiva, essas operações continuam negadas. Fixture acrescenta explicitamente ALL permissiva e comprova que ela também não reabre ownership externo.

**9 testes PostgreSQL**, duas empresas, Admin A/B, Gerência, Encarregado: metadata SELECT/INSERT/UPDATE/DELETE; empresa falsificada, entidade externa/tipo errado; Storage SELECT/INSERT, UPDATE/MOVE/DELETE ausentes e permissiva alternativa; anexos; documentos/objetos de obra; rollback exato das policies e preservação de dados. Table grants da fixture são deliberadamente amplos para provar RLS mesmo com CRUD; a migration não altera grants de tabela/coluna. Nenhum path/byte existente é movido, renomeado ou apagado.

## I–K. Projeção e histórico HE

Inventário completo de `folha_he` e resposta de contexto:

| Campo | Diretor/Adjunto | Administrativo | Encarregado |
|---|---|---|---|
| id | SIM | SIM | NÃO |
| empresa_id | NÃO | SIM | NÃO |
| obra_id | SIM, âmbito autorizado | SIM | NÃO |
| folha_id | SIM | SIM | NÃO |
| folha_revision | SIM | SIM | NÃO |
| minutes | SIM | SIM | NÃO |
| estado | SIM | SIM | NÃO |
| revision | SIM | SIM | NÃO |
| processado_em | NÃO | SIM | NÃO |
| processado_por | NÃO | SIM | NÃO |
| prazo_processamento | NÃO | SIM | NÃO |
| sheet: person_id/date/intervals/revision; person_name | SIM | SIM | NÃO |

Gestão/Gerência conservam a leitura administrativa já existente (`permissions.admin`). Validação/processamento HE e special_review continuam exclusivos de Administrativo (`permissions.adm`); nenhum papel novo recebeu escrita.

Helper privado `he_operacional(jsonb)` constrói allowlist explícita; não entrega `to_jsonb(folha_he)` indiscriminadamente. Diretor/Adjunto recebem exatamente nove chaves no objeto HE enriquecido. Encarregado recebe array vazio. Snapshots antes/depois dos eventos operacionais também usam a allowlist, inclusive campos futuros não projetados.

Domínio operacional HE: **he_approve / he_reject**. **he_validate / he_process / configure_he_eligibility** são administrativos na origem; não entram no contexto Diretor/Adjunto. UI esconde processamento/prazo por autorização e restringe também snapshots do histórico operacional, independentemente da minimização SQL.

Sweep raw: contexto de gestão, contexto diário, histórico diário, preview/resposta/replay operacional; resultados administrativos antigos não são recuperáveis após perda de papel ou inativação. Alertas de processamento têm destinatário Administrativo da mesma empresa, `obra_id NULL`, sem email, evitando divulgação pelo OR de acesso à obra. Teste instala localmente as quatro policies de alertas do snapshot: Diretor/Adjunto/Encarregado não leem esses alertas; Administrativo lê. Não altera policies de alertas do produto.

## L–M. Dia especial e revisão factual

`special_day` mantém o facto histórico; `special_reviewed` deriva exclusivamente de `special_reviewed_at IS NOT NULL`. Não é inferido pelo calendário. Backend diário, cliente, resumo e facts de Vencimentos usam a mesma origem.

| Situação | Diário/Vencimentos | Pendência especial | DIA COMPLETO |
|---|---|---|---|
| Especial não revisto | DIA ESPECIAL · REQUER REVISÃO | +1 | NÃO |
| Especial revisto | DIA ESPECIAL · REVISTO | 0 por este motivo | SIM se não há outras pendências |
| Edição factual posterior | Volta a REQUER REVISÃO | +1 | NÃO |

A mensagem global de calendário apenas pede horários reais; não acusa todos os dias especiais de review pendente. O indicador individual vem do registo factual. O domínio não gera potencial HE por duração num dia especial já revisto.

`special_review` guarda antes/depois reais, ator, timestamp, request_id e revisão atualizada. Trigger BEFORE UPDATE invalida metadata do review quando mudam intervalos, minutos, estado, natureza especial, minutos esperados, obra/pessoa/data/tipo de local. Save já limpa revisão; reconciliação por ausência também é protegida. Histórico conserva a evidência da revisão anterior e da invalidação.

Concorrência PostgreSQL com duas conexões: review confirma primeiro → edição com revisão velha recebe 40001; edição confirma primeiro → review antigo recebe 40001. Locks/revisões existentes são reutilizados. Sem escrita direta nova; helpers privados não têm EXECUTE externo.

## N–P. Verificação local final

**499 PASS / 0 FAIL / 3 SKIP**, 42 suites node locais. Contagem sem somar reexecuções. Backend Folha: 103 PASS; documental: 9 PASS. PostgreSQL 17.6 efémero, identidades e dados sintéticos.

SKIPs originais preservados em RH Cadastro: cenário PostgreSQL próprio, formulário de gravação e aviso contratual dependentes do runtime RH específico. Não foram convertidos em PASS. Suites locais de Medicina, Viaturas, Centro de Documentos, sessão, Quadro, Planeamento, Financeiro, RNC, férias/ausências/HE/Vencimentos, scripts/rollbacks e compatibilidade Fase B aprovadas.

Browser local, endpoints sintéticos; nenhuma escrita real e nenhum contacto externo:

| Suite | Resultado final |
|---|---|
| security-visibility | 54 grupos PASS; seis perfis; desktop 1440/tablet 820/mobile 390; console sem erros |
| adm-rules | 48 grupos PASS |
| visible-state | 126 PASS |
| reconciliation-state | 81 PASS |
| attendance-sheet | 57 PASS |
| consolidation | 51 grupos PASS |
| session-boundary | 7 cenários PASS |
| planning-cost-access | 33 PASS |
| rh-frontend / workforce-controlled / medicine / vehicle-assignment / encarregado-rnc | PASS |

Fixtures antigas foram corrigidas onde esperavam empresa_id no payload HE operacional ou omitiram review/pendência do dia especial. Não foram removidas as verificações de âmbito; foram substituídas por projeção exata e estados explícitos. Uma fixture de ausência de Folha não é evidência de review factual.

Screenshots sintéticos fora de Git: `%TEMP%/primeline-security-visibility-browser`, `%TEMP%/primeline-adm-rules-browser` e pastas das regressões existentes. `git diff --check` aprovado. Só código, SQL local, fixtures sintéticas e documentação na branch; nenhum segredo, dump real ou log versionado.

## Q–R. Scripts, riscos e decisão

Documental autocontido: `documentos_rh_tenant_precheck.sql` → `documentos_rh_tenant_backup.sql` → `documentos_rh_tenant.sql` → `documentos_rh_tenant_postcheck.sql`; rollback explícito disponível. Postcheck compara dados/grants, RLS, helpers e guardas; rollback conserva bytes e backup, mas restaura permissões antigas inseguras e exige autorização própria.

Folha: core e gestão atualizados, postcheck exige contrato de projeção/review e trigger ativo; ambos rollbacks removem os novos helpers/trigger, recusando perda de factos existentes. Backup/precheck legados não foram enfraquecidos nem tiveram fingerprints reais inventados. Fase B continua a exigir aprovação independente do catálogo real.

**Antes de rollout real:** reconfirmar catálogo/policies/grants de Storage e metadata; rever compatibilidade dos fingerprints de precheck com a instalação documental. O precheck Folha ainda compara integralmente o catálogo anterior do hotfix: uma instalação documental independente causa drift esperado e deve ser tratada numa preparação de rollout expressamente autorizada, sem atualizar snapshots automaticamente. Não aplicar scripts em sequência improvisada nem interpretar o GO local como autorização de produção. Calendário, valores HE automáticos e exporter oficial mantêm gates próprios.

Varredura focada das seis classes pedidas: nenhum caminho externo sem a nova guarda nos testes metadata/Storage; nenhum campo/histórico de processamento HE no JSON operacional; nenhum REQUER REVISÃO em review válido; nenhuma revisão válida após edição/reconciliação factual. Scripts históricos inseguros continuam preservados como histórico, substituídos pelo novo rollout documental.

Nenhum P0/P1/P2 restante identificado nesta classe pela evidência local. Produção, main, dados/perfis reais, deploy e Fase B inalterados. Não foi tentado o método bloqueado de catálogo.

**GO LOCAL para reauditoria dos 3 achados.** Rollout real permanece condicionado a catálogo/gates e autorização separados.
