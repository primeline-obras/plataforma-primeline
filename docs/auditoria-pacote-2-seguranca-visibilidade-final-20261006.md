# Reauditoria independente — documentos RH, HE e dia especial

## A–B. Identidade e âmbito

**SHA auditado:** `5e0feb3454243bdf11fe09292bd9e3db2d40e9b3`.

**Branch de auditoria:** `audit/pacote-2-seguranca-visibilidade-final-20261006`, criada exatamente desse SHA. O commit desta auditoria contém apenas este relatório, dois módulos de testes independentes e duas chamadas desses módulos nas suites existentes; SHA final identificado na entrega e em `git log -1`.

Auditoria anterior preservada: `audit/pacote-2-regras-adm-final-20261006`, `3a239cf0783b6f84e9d2e1162a6c8153b43dd556`. Candidato e main não modificados. Nenhuma leitura ou escrita em produção, tentativa de catálogo bloqueado, deploy ou Fase B real.

Evidência: revisão do código/SQL do SHA fixado, catálogo histórico preservado, instalação dos scripts em PostgreSQL 17.6 efémero, RLS aplicado por SET ROLE authenticated, identidades sintéticas de duas empresas e browser local. As policies abaixo são as **efetivas da fixture após a instalação**, não uma reconfirmação do catálogo atual de produção.

## C–D. Metadata e Storage cross-company — PASS

Admin A lê A; Admin B lê B. UUIDs conhecidos da outra empresa são explicitamente consultados: SELECT retorna zero linhas; INSERT com entidade externa ou empresa falsificada recebe 42501; UPDATE/DELETE de linhas externas afetam zero linhas. O UPDATE que tenta trocar a entidade própria por uma externa recebe 42501. Ambos os tipos, colaborador e viatura, foram testados nos dois sentidos; CRUD legítimo próprio permanece funcional.

Storage: objetos próprios legíveis/inseríveis; UUIDs externos negados para colaborador e viatura. UPDATE/MOVE/DELETE não têm policy permissiva no inventário aplicável e permanecem negados, inclusive DELETE próprio. A suite existente acrescenta temporariamente uma policy ALL ampla, apenas na base sintética: SELECT/MOVE/DELETE sobre RH externo continuam negados pela guarda restritiva; UPDATE próprio autorizado por essa policy funciona. Nenhum ficheiro real foi movido, eliminado ou renomeado.

Anexos de ausência também exigem empresa do colaborador; documentos/objetos de obra legítimos continuam acessíveis. Clientes RH/Medicina usam o reader direto `documentos`, protegido pelo RLS, sem uma nova fonte documental.

## E. Policies efetivas e combinação OR/AND — PASS

Todas as policies enumeradas são para authenticated:

| Tabela | Policy | Tipo / comando |
|---|---|---|
| public.documentos | documentos_insert | PERMISSIVE INSERT |
| public.documentos | documentos_select | PERMISSIVE SELECT |
| public.documentos | pl_admin_total | PERMISSIVE ALL |
| public.documentos | pl_documentos_empresa_insert | PERMISSIVE INSERT |
| public.documentos | pl_documentos_empresa_select | PERMISSIVE SELECT |
| public.documentos | pl_documentos_rh | PERMISSIVE ALL, agora com empresa/entidade |
| public.documentos | pl_documentos_workflow_insert | PERMISSIVE INSERT |
| public.documentos | pl_documentos_workflow_select | PERMISSIVE SELECT |
| public.documentos | rh_empresa_guard | RESTRICTIVE ALL |
| storage.objects | documentos_rh_storage_insert | PERMISSIVE INSERT |
| storage.objects | documentos_rh_storage_select | PERMISSIVE SELECT |
| storage.objects | documentos_storage_insert | PERMISSIVE INSERT |
| storage.objects | documentos_storage_select | PERMISSIVE SELECT |
| storage.objects | rh_storage_empresa_guard | RESTRICTIVE ALL |
| public.ausencias_anexos | ausencias_anexos_rh | PERMISSIVE ALL |
| public.ausencias_anexos | rh_anexo_empresa_guard | RESTRICTIVE ALL |

As oito policies permissivas de metadata não ultrapassam o AND restritivo: empresa do utilizador ativo = empresa do documento e da entidade no tipo correto. Helpers SECURITY DEFINER usam search_path seguro e referências qualificadas. A guarda Storage aplica-se a bucket documentos/namespace RH, validando tipo, UUID e ownership; não concede operações ausentes. Funciona sem acrescentar empresa ao path. A extensão ALL sintética confirma que o OR administrativo alternativo não reabre acesso a RH externo.

## F. Commit documental sobre main — PASS

`origin/main` reconfirmado em `3df019a2f2813c0cbf7f36a8d13000431d33dd50`.

Num worktree temporário detached e limpo, cherry-pick de `cec13e621af6cb299bcc23e0536a2a6531efa784` aplicou sem conflitos; resultado `0eae56d01a5b5c1796ef8e3ff7df15821bedc7b8`. Nenhuma alteração em main.

Nesse worktree, oito suites documentais/RH/Medicina/Viaturas/Centro de Documentos: **88 PASS / 0 FAIL / 3 SKIP**. Os nove testes documentais e rollback passaram sem tabelas Pacote 2. Foi usado o runtime PGlite já existente, por caminho explícito, sem instalação. Worktree limpo removido após a prova.

## G–I. HE bruto, histórico e replay — PASS

| Perfil | JSON HE | Ações verificadas |
|---|---|---|
| Diretor | Projeção operacional exata | Aprova e rejeita; não valida/processa |
| Adjunto | Projeção operacional exata | Aprova e rejeita; não valida/processa |
| Administrativo | Projeção administrativa preservada | Valida e processa; replay legítimo |
| Encarregado | Array HE vazio | Sem gestão administrativa HE |

Diretor/Adjunto recebem exatamente: `id`, `obra_id`, `folha_id`, `folha_revision`, `minutes`, `estado`, `revision`, `sheet`, `person_name`. Sheet contém pessoa/data/intervalos/revisão. Ausentes: empresa_id, processado_em, processado_por, prazo_processamento e eventos administrativos. Também verificados contexto diário, histórico diário, preview/resposta/replay operacional e snapshots antes/depois HE.

`he_approve` e `he_reject` têm domínio HE operacional e âmbito de obra. `he_validate`, `he_process` e configuração de elegibilidade têm domínio administrativo; não entram no histórico bruto Diretor/Adjunto/Encarregado. Escrita administrativa é exclusiva do perfil literal Administrativo. Gestão/Gerência mantêm a leitura administrativa previamente aprovada; não foram confundidos com os perfis operacionais nem receberam nova escrita.

Teste independente adicional para cada ação he_validate/he_process: obter preview como Administrativo → reduzir papel → confirmar recebe 42501; restaurar papel → confirmação legítima; reduzir papel após commit → replay recebe 42501; restaurar papel → replay retorna exatamente o resultado original. A autorização precede a consulta ao cache. Inativação e perda de responsabilidade também continuam cobertas pelas suites preservadas.

Alertas de processamento: obra_id NULL, destinatário Administrativo da mesma empresa, sem email. Policies históricas de alertas exercitadas localmente comprovam que esses dados não chegam a Diretor/Adjunto/Encarregado pelo acesso à obra.

## J–M. Dia especial, invalidação e paridade — PASS

| Estado factual | Diário | Summary / DIA COMPLETO | Vencimentos |
|---|---|---|---|
| special_day=true, special_reviewed=false | REQUER REVISÃO | pending=1, complete=false | 1 facto pendente |
| special_day=true, special_reviewed=true | REVISTO | pending=0, complete=true | 0 factos pendentes |
| Corrigir intervalos após review | REQUER REVISÃO novamente | pending=1, complete=false | 1 facto pendente |

Fixture independente com uma única pessoa/obra/dia, calendário sintético validado e campos manuais preenchidos; assim a pendência observada corresponde exclusivamente ao review. Os valores manuais não representam salários reais.

O browser chama os módulos reais e as RPCs reais da base local: Administrativo marca revisto pelo frontend, diário é recarregado, UI e folha_registos/contexto/payroll_facts são comparados; depois edita intervalos com motivo pelo frontend e confirma a invalidação no diário e Vencimentos. Executado nos três tamanhos, com novo review/edição a cada ciclo. Foram seis confirmações sintéticas: três reviews e três edições.

Fonte única: timestamp persistido do review; flag explícita em contexto e payroll_facts. Trigger BEFORE UPDATE limpa autor/timestamp quando mudam factos relevantes. Save, reconciliação de ausência e ambas as ordens de concorrência continuam testados: revisão velha recebe 40001 e não mantém review indevido. Histórico antes/depois, ator, timestamp, request_id e revisão anterior permanecem preservados.

## N. Browser — PASS

Desktop 1440, tablet 820 e mobile 390:

- **24 verificações** documentais: respostas reais de SQL/RLS local para A/B, colaborador/viatura, metadata e Storage; sem mocks de respostas.
- **21 verificações** Folha/HE: quatro perfis e três transições factuais em cada viewport, através de RPCs reais do PostgreSQL sintético; console sem erros.
- Suites complementares: attendance-security-visibility (54 grupos), sessão (7 cenários), Planeamento/custos (33 verificações), Medicina, Viaturas, Quadro e RH — PASS, com mocks identificados e tráfego externo bloqueado.

Screenshots sintéticos: `%TEMP%/primeline-audit-security-live-pg/reviewed-{1440,820,390}.png` e `invalidated-{1440,820,390}.png`, fora de Git. Console dos testes independentes sem erros; nenhuma ligação a produção.

## O–P. Regressões, scripts e totais — PASS

Regressão focada de **24 suites: 444 PASS / 0 FAIL / 3 SKIP**, incluindo os testes independentes. Não se somam as reexecuções nem os 88 PASS da prova sobre main. A execução independente das duas suites nucleares, incluída nesse total, teve 120 PASS / 0 FAIL.

Três SKIPs RH originais preservados: cenário PostgreSQL próprio do cadastro, formulário de gravação e aviso contratual dependentes do runtime RH específico. Nenhum SKIP transformado em PASS.

Reexecutados documentos/Storage, Medicina, Viaturas, Centro de Documentos, RH, Folha/HE/Vencimentos/dias especiais, férias/ausências, sessão, Quadro, Planeamento e compatibilidade Fase B. Scripts documentais e Folha instalados somente em bases efémeras; postchecks e rollbacks locais passaram. Rollbacks recusam perda de factos; rollback documental restaura permissões anteriores e só poderá ser usado em produção com autorização específica.

Precheck documental é READ ONLY, aborta inconsistências de empresa/entidade e não corrige dados. Backup privado/alteração transacional/postcheck disponíveis e sem dependência Pacote 2. O precheck Folha e o gate Fase B mantêm as comparações e aprovação de catálogo; nenhum fingerprint real foi atualizado/inventado nesta auditoria.

Limite para próxima etapa: o catálogo real, as policies Storage efetivamente instaladas e o calendário empresarial ainda precisam validação autorizada READ ONLY. O precheck Folha compara o catálogo anterior do hotfix; instalar o bloco documental antes dele produz drift esperado. A ordem/fingerprint de rollout deve ser revista explicitamente, não alterada automaticamente nem contornada. O postcheck documental faz verificações nominais de guardas; a reconfirmação real deve também comparar as expressões completas das policies com o SHA aprovado.

`git diff --check` PASS. Diff de produto contra o SHA auditado: vazio em src, supabase e index.html. Alterações desta branch limitadas a testes/relatório; nenhum dump, segredo, dado real ou artefacto gerado versionado.

## Q–R. Achados e decisão

P1 documental original: fechado localmente. P1 HE original: fechado. P2 dia especial original: fechado, incluindo edição e reconciliação. **Nenhum P0/P1/P2 restante identificado na classe auditada.** Nenhuma validação essencial bloqueada pelo ambiente nesta execução. Não equivale a validação de produção ou autorização de rollout.

**GO LOCAL.**

**PACOTE 2 APTO LOCALMENTE PARA VALIDAÇÃO READ-ONLY DO AMBIENTE REAL, COM PRIORIDADE À POLICY DOCUMENTAL E AO CATÁLOGO/CALENDÁRIO, ANTES DO ROLLOUT CONTROLADO.**
