# Pacote 2 — correção da auditoria final

## Identificação e limites

- Base exata: `77d50afd44bdade4490a95085665bc74bcc22a4f`.
- Branch: `fix/pacote-2-auditoria-final-20261006`.
- Auditoria preservada no remoto: `audit/pacote-2-folha-ponto-final-20261005`, `4ccdf1e2b44262019e06806b1f27540309ca8951`.
- Nenhum SQL executado em produção, nenhum perfil/dado real usado, nenhum deploy, main ou Fase B real.
- A autorização explícita desta tarefa permite corrigir os scripts locais, apesar da regra geral de `instrucoes.txt`. Não permite instalar os scripts.

## P1 — causa e correção

O writer administrativo aceitava `work_id` em payroll. Guardava o evento salarial com essa obra. O reader filtrava histórico por empresa/obra, mas não pela finalidade; o Encarregado autorizado nessa obra recebia `antes/depois` salariais. A ausência de campos na UI não protegia o JSON.

`folha_gestao_historico.dominio` é uma coluna gerada e armazenada, vinculada a uma CHECK fechada de ações:

- `tarefas`: reporte, confirmação e reconciliação pelo Planeamento;
- `he`: aprovação, rejeição, validação de HE;
- `horario`: configuração de horário da obra;
- `administrativo`: configuração empresarial, férias/direitos e vencimentos.

O cliente não escolhe o domínio. A BD não aceita ações desconhecidas. O reader autoriza pelo domínio estrutural e pelo papel/obra. A coincidência de obra nunca autoriza eventos administrativos para perfis operacionais. O teste inclui deliberadamente um evento salarial histórico mal associado a uma obra, criado apenas pelo owner sintético, e prova que não passa na projeção operacional.

As ações administrativas sem âmbito de obra recusam `work_id` com `22023 / ADMIN_WORK_SCOPE_INVALID`, antes de preview, gravação ou replay. Não há backfill nem reclassificação de dados reais: as tabelas v2 ainda serão criadas pelo rollout autorizado.

### Excesso adicional da mesma classe

1. O contexto diário devolvia a ausência inteira, incluindo comentário livre. Agora projeta apenas `id/data/tipo/estado`.
2. A linha diária devolvia toda a HE. Agora entrega apenas `estado`; o detalhe de revisão/minutos permanece no contexto autorizado de revisão HE.
3. Catálogos de fornecedores/pessoas externas destinavam-se ao formulário de escrita, mas chegavam também aos leitores Diretor/Adjunto. São agora vazios para esses leitores; as linhas externas efetivamente presentes continuam consultáveis.
4. O writer de gestão devolvia replay antes da verificação atual de papel. Uma mudança posterior de perfil podia devolver um resultado salarial antigo. As guardas administrativas, de tarefas e de âmbito HE são agora anteriores ao replay. O teste altera somente o ator sintético e verifica recusa `42501`, seguida de replay legítimo idêntico quando o papel é reposto.

Não foram ampliadas permissões, criadas regras salariais ou concedido acesso ao Financeiro.

## P2 — causa e tratamento

`fn_folha_historico_v2` devolvia `events`, `legacy` e `legacy_interpretation`; `createSheetClient.history` devolvia somente `events`. O cliente passa a validar e preservar os três campos, incluindo a interpretação `original`.

A UI apresenta duas secções: **HISTÓRICO FOLHA V2** e **REGISTO LEGADO**. Mostra data, obra, estado, horas, períodos/intervalos disponíveis e autoria/timestamps originais. Não converte legado, não cria revisão fictícia e não apresenta controlos de edição do legado. Os valores são escapados.

A projeção do ponto legado é uma allowlist explícita: `id`, `data`, `obra_id`, `horas`, `entrada_manha`, `saida_manha`, `entrada_tarde`, `saida_tarde`, `periodos_alocados`, `estado`, `registado_por`, `atualizado_por`, `criado_em`, `atualizado_em`. Não devolve `observacao`, `justificacao_estado`, empresa/pessoa redundantes, nem quaisquer colunas futuras automaticamente.

Uma linha legada da própria empresa/pessoa/data/obra também é evidência válida para consultar o histórico da obra autorizada; não é necessária uma alocação atual inventada. O âmbito da obra e da pessoa continua verificado antes da leitura.

As colunas foram confrontadas com o schema sintético já preparado e com as definições preservadas no repositório. O catálogo real não foi novamente consultado pelo método bloqueado. Precheck e migration verificam a presença das colunas necessárias e abortam se faltar alguma; o teste verifica a guarda em READ ONLY e a recusa de uma coluna ausente numa transação local revertida.

## Matriz de payload por RPC e perfil

| RPC | Perfil | Campos devolvidos | Sensibilidade e justificação |
|---|---|---|---|
| contexto v2 | Encarregado | versão/data/obra, obras atribuídas, linhas de pessoas e externos do dia, horário, resumo, calendário/janela, permissões, catálogos necessários à alocação/externos | Nomes/função operacional, horas e estado da ausência são necessários à Folha. Sem remuneração, contactos, notas RH ou administração. |
| contexto v2 | Diretor/Adjunto | mesmo contexto de leitura da obra atribuída; própria Folha de Escritório quando vinculada | Sem catálogos de escrita externa; sem escrita da equipa; sem bloco salarial. |
| contexto v2 | Preparador | própria linha de Escritório e metadados da jornada | Vínculo pessoal único; não recebe a equipa de obra nem área administrativa. |
| contexto v2 | Administrativo/Gestão/Gerência | âmbito da empresa, linhas operacionais e permissões legítimas existentes | Não altera a autorização anterior de escrita global do Quadro. |
| pessoas v2 | Encarregado/gestor de alocação autorizado | versão; pessoa UUID/nome; destino pontual id/tipo/label; revisão; pode alocar/transferir | Picker autorizado, mesma empresa, pessoas ativas no dia. Sem matriz global, salário, nível remuneratório ou contactos. Diretor/Adjunto/Preparador sem gestão recebem recusa. |
| histórico v2 | responsável da obra | eventos daquela pessoa/data/obra; legado projetado; interpretação original | Eventos operacionais com antes/depois, revisão, autoria, origem e motivo operacional. Legado somente leitura; âmbito confirmado por evidência local. |
| histórico v2 | próprio de Escritório | somente chave própria | Sem histórico de terceiros. |
| histórico v2 | administrativo | chave da mesma empresa autorizada | Não retorna outros colaboradores/datas no mesmo pedido. |
| gestão contexto v2 | Encarregado | versão, horário, permissões, tarefas/reportes, histórico domínio tarefas; overtime vazio | Nenhuma chave `payroll/live_facts/entitlements/vacations/vacation_revision/people/config`. |
| gestão contexto v2 | Diretor/Adjunto | anterior + HE e histórico HE/horário da obra atribuída | Aprovação/rejeição HE e validação operacional de tarefas; nenhum payroll/RH administrativo. |
| gestão contexto v2 | Preparador | recusa | Self-service próprio usa contexto/histórico da Folha, sem herança administrativa. |
| gestão contexto v2 | Administrativo/Gestão/Gerência | anterior + people/config, férias/direitos/revisão, payroll e live_facts, histórico administrativo autorizado | Mesma empresa; pessoa/competência explicitamente selecionadas; comportamento legítimo preservado. |
| quatro readers | Financeiro sem papel RH, inativo, ator ausente, obra de outra empresa | recusa nos fluxos não autorizados | Não herda permissões pela empresa ou pelo login. |

`folha_registos` e snapshots de alocação não contêm valores salariais: o campo `valor_hora` pertence a `colaboradores` e não é projetado nestes readers. O histórico v2 contém exclusivamente os factos operacionais gerados pelos helpers privados; a nova camada administrativa usa outra tabela e domínio estrutural.

## Backend → cliente → UI

Categorias: A obrigatório/usado; B opcional/usado; C metadado técnico sem renderização obrigatória; D excessivo/removido.

| Resposta/campos | Classe | Consumo ou decisão |
|---|---|---|
| contexto: version/date/work_id/works/tipo_local/office_available | A | Validação da resposta, seleção de local/data e jornada Escritório. |
| rows/external_rows: person_id/name/role/provider_name/sheet/revision | A/B | Identidade da linha, estado/horas, editor e revisão esperada. |
| absence/conflict/expected_minutes/can_write/can_remove | A/B | Estado operacional, bloqueio de ações e regularização; comentário RH removido. |
| allocation_ids/allocation_revision/period | A | Alocação/retirada e intervalos da jornada parcial. |
| overtime.estado | B | Estado pendente visível; detalhes desnecessários na linha removidos. |
| summary | C | Resumo equivalente calculado a partir das próprias linhas pela UI; testes de paridade do resumo/estados já existentes. Não oculta pendências. |
| schedule/special_day/correction_days/admin/calendar_verified/overtime_generation/permissions | A/B | Jornada, janela, elegibilidade/ações e aviso explícito de HE/calendário pendente. |
| self_person_id | C | Metadado da vinculação própria; o editor opera pela chave da linha autorizada, não cria nova identidade. |
| providers/external_people/management | B | Formulário externo e abertura do contexto de gestão; catálogos reduzidos aos escritores. |
| pessoas: person_id/name/current_work/allocation_revision/can_allocate/can_transfer | A | Picker e confirmação de transferência; indisponibilidade recusa a ação. `recent` não é uma fonte de autorização nem um campo prometido pelo backend. |
| histórico: events/legacy/legacy_interpretation | A/B | Ambos preservados no cliente; duas origens explícitas na UI, legado sem edição. |
| events: antes/depois/action/at/ator_id/reason | A/B | Rastreabilidade visível. IDs, request_id/revision/origem e chave são C técnicos. |
| legado: data/obra/horas/intervalos/períodos/estado/autoria/timestamps | A/B | Valores originais visíveis; sem conversão em estado v2. ID é C. |
| legado: observacao/justificacao_estado/colunas futuras | D | Não fazem parte da projeção operacional. |
| gestão: tasks/task_reports/history/schedule/permissions | A/B | Tarefas ativas, reportes incluindo confirmados e histórico operacional agora visíveis. Antes `task_reports` e histórico operacional podiam ficar sem apresentação útil. |
| gestão: overtime | B | HE da obra para Diretor/Adjunto e administrativo; Encarregado recebe lista vazia e não recebe tab HE. |
| gestão: people/vacations/vacation_revision/entitlements/payroll/live_facts/config | A/B administrativo, D operacional | Cliente exige estes campos apenas no contrato administrativo. Férias/payroll mostram factos e pendências sem cálculo monetário inventado. |
| operações: preview/token/request_id/revision/changed_keys/result | A/C | Confirmação, idempotência, revisão e recarga após commit. O estado mostrado vem da recarga; erro ambíguo não simula sucesso. |

Não há campo `diagnostics` funcional prometido por estes readers. Conflitos, permissões, revisões, HE, pendências e legado foram confrontados com os consumidores. Não se exige a apresentação de cada UUID técnico.

## Scripts e fingerprints

- `folha_ponto_v2_precheck.sql`: mantém os hashes reais anteriores e guardas do hotfix; acrescenta somente verificação read-only das colunas da projeção legado.
- `folha_ponto_v2.sql`: guarda de colunas, ausência/HE e catálogos mínimos, projeção legado e evidência histórica autorizada.
- `folha_ponto_v2_gestao.sql`: domínio gerado/CHECK, guardas anteriores ao replay, writer administrativo sem obra e projeção por perfil.
- `folha_ponto_v2_postcheck.sql`: verifica também a classificação estrutural instalada.
- Backup e dois rollbacks: revistos, sem alteração necessária. Backup preserva dados/definições legadas; rollback elimina a nova tabela inteira, incluindo coluna gerada/CHECK, apenas quando vazia. Não usa CASCADE nem apaga factos persistentes.
- Fase B: compatibilidade reexecutada localmente; gate ausente/drift recusa, instalação e rollback passam. O fingerprint sintético existe exclusivamente na base efémera. Um fingerprint real exige nova revisão/autorização, não foi regenerado nem marcado.
- SHA-256 dos ficheiros SQL normalizados para LF: manifesto ao fim deste relatório; compara a base aprovada com este candidato, sem substituir hashes do catálogo histórico.

## Evidência e decisão

Os nove casos da auditoria anterior não ligados aos dois achados foram preservados literalmente em `attendance-preserved-audit-cases.mjs`. Os dois casos com contrato antigo foram substituídos por regressões mais completas: JSON bruto por perfil, administrativo legítimo, replay com mudança de papel e os quatro estados de legado/v2. A auditoria original permanece intacta no remoto e prova os achados antes da correção.

Testes/resultados finais: ver secção de execução abaixo. As três SKIPs RH anteriores permanecem SKIP. A ocorrência REST intermitente anterior pertence à auditoria preservada; não será apresentada como PASS nem ocultada caso reapareça na execução final.

P0/P1/P2 conhecidos corrigidos nesta classe; decisão limitada à evidência local. **GO LOCAL para reauditoria independente focada**, condicionado à execução final sem FAIL. Rollout real permanece sem autorização nesta tarefa e requer catálogo real/precheck pelos meios autorizados.

## Execução final

- Suite integrada, 41 ficheiros, sequencial: **561 PASS / 0 FAIL / 3 SKIP** (564 testes).
- Core final, incluindo o caso adicional de domínio/projeções mínimas: **80 PASS / 0 FAIL / 0 SKIP**. Substitui os 79 testes core da execução integrada; não é somado integralmente. Conjunto final sem duplicação: **562 PASS / 0 FAIL / 3 SKIP** (565 testes).
- Browser Folha: **57 grupos PASS**, três viewports, histórico nenhum/legado/v2/ambos.
- Browser consolidação: **51 grupos PASS**, seis perfis × três viewports; reportes confirmados preservados sem tarefas ativas.
- Sessão: 7 cenários PASS. Custos Planeamento: 33 PASS. Browser Medicina, RH, RNC, Viaturas e Quadro: PASS, console limpo.
- As três SKIPs são as mesmas suites RH dependentes de runtime não configurado: migração/cadastro/lote, formulário e aviso contratual. Não foram habilitadas nem contabilizadas como PASS.
- A falha intermitente de arranque PostgREST da auditoria anterior não reapareceu na execução integrada final. As duas falhas de uma execução preliminar desta correção foram uma asserção da fixture que esperava numeric como string dentro de JSON e o teste pai; a asserção foi corrigida para o número JSON real e reexecutada com PASS. Nenhuma falha REST foi ocultada.
- Instalação vazia, ACL/RLS/owners, grants/helper privados, idempotência, concorrência, alertas, B local e rollbacks: PASS em PostgreSQL 17.6 sintético.
- Precheck completo de produção não executado contra fixture reduzida nem BD real. A nova guarda foi testada separadamente em READ ONLY; blocos económicos existentes revistos e testados pelas suites correspondentes.
- Screenshot mobile Encarregado inspecionado: sem blocos administrativos, reporte confirmado visível e estado vazio de tarefas correto.
- `git diff --check`: PASS. Nenhum dado real, credencial, screenshot ou log incluído no commit.

**GO LOCAL para reauditoria independente focada.** Nenhum P0/P1/P2 conhecido restante nesta classe. Não é autorização de rollout.


## SHA-256 dos scripts (UTF-8, CRLF normalizado para LF)

| Ficheiro | Base 77d50afd | Candidato corrigido |
|---|---|---|
| folha_ponto_v2_precheck.sql | e617926a0fd87bcd035cb0dc0e31d82d13feb18d46dd444180449b8efe746817 | 369b52f6e5ed08d0e2c99617f99e13e0a25f155f190b2ff410ff4269396750d0 |
| folha_ponto_v2_backup.sql | fbf94fd5cc2704ab0f47339117dd6227c4189ea58c21d26196b62148654060f3 | fbf94fd5cc2704ab0f47339117dd6227c4189ea58c21d26196b62148654060f3 |
| folha_ponto_v2.sql | 965cbb29000b80bd133c1525bfbecfb0c80c5a594737925516a9880af83627a0 | e9470508da4cb4e3de5bbfba7312700c91d4e733169551287c4ed747d31e036d |
| folha_ponto_v2_gestao.sql | 9f3911194587bdb6ffc14d49d781181bfd52971169754c44aa9fa90d4142bb87 | 67a28079d523ac400fc090d423ad02636118e83be2e3797ab405147872a628c9 |
| folha_ponto_v2_postcheck.sql | 5b965fa12c741a7c535092fcfcb8b7d59be5db01d43b87ad5d05a3f07d4e87c2 | 4b3ad147936ae6c13ac0b5860b240c3e09ebfe3fa7aaaeb32a200bec88198e05 |
| folha_ponto_v2_gestao_rollback.sql | 1a0eda31b26a6d75c7ec798e0b1248cf21a571d020b8d0e3727f10e2771ae51e | 1a0eda31b26a6d75c7ec798e0b1248cf21a571d020b8d0e3727f10e2771ae51e |
| folha_ponto_v2_rollback.sql | 4c2125a1a3173a48c09fe117e0408db8eb8a16f35d948668b9e1ab93ac5fb3d6 | 4c2125a1a3173a48c09fe117e0408db8eb8a16f35d948668b9e1ab93ac5fb3d6 |
