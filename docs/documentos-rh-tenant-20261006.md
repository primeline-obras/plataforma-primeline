# Proteção documental RH independente do Pacote 2

Material local, não aplicado em produção. Não depende de folha_registos ou outra entidade Pacote 2. Usa fn_utilizador_atual_id e fn_e_administrativo existentes; confirma atividade e empresa em utilizadores. Helpers SECURITY DEFINER no schema privado, search_path=pg_catalog, sem acesso anon/service_role; authenticated recebe somente o uso dos predicados booleanos necessários ao RLS, sem linhas ou informação de outra empresa.

## Causa e policies

Snapshot preservado de 04/10: documentos possui oito policies permissivas: documentos_insert, documentos_select, pl_admin_total, pl_documentos_empresa_insert/select, pl_documentos_rh, pl_documentos_workflow_insert/select. As regras amplas permitem o mesmo RH por OR. ausencias_anexos_rh exige apenas papel. As regras Storage RH dos scripts existentes verificam tipo/path/papel, sem ownership do UUID.

Depois: nenhuma policy de obra é removida. pl_documentos_rh exige empresa do documento e da entidade; rh_empresa_guard é RESTRICTIVE ALL e exige empresa atual para metadata, além de ownership de colaborador/viatura no respetivo tipo. Fecha os OR alternativos, incluindo pl_admin_total, sem ampliar papéis. rh_anexo_empresa_guard associa ausência ao colaborador/empresa. rh_storage_empresa_guard exige UUID pertencente à empresa em rh/colaborador, rh/viatura e rh/ausencia; rejeita tipos desconhecidos, UUID inválido, segmentos vazios/dot/traversal.

Storage: a regra nova é restritiva; não cria permissões INSERT/UPDATE/DELETE ausentes. Se a política permissiva existente não autorizar uma operação, ela continua recusada. Não move objetos nem acrescenta empresa ao path. Caminhos de obra continuam sujeitos às regras existentes. Nenhum byte é apagado/substituído. Uma futura policy permissiva ampla não ultrapassa a guarda restritiva para authenticated.

## Ordem e limites

PRECHECK → BACKUP → documentos_rh_tenant.sql → POSTCHECK. Precheck somente leitura: schema/helpers, inconsistências RH/empresa, órfãos, todas as policies e grants. Backup privado preserva policies/RLS/ACL e metadata/objetos; não duplica bytes do Storage. Migration transacional, owner postgres, backup obrigatório. Postcheck compara integralmente dados e grants, guardas, RLS e helpers. Rollback explícito restaura a policy anterior e RLS anterior e mantém backup; não usa CASCADE e não mexe em ficheiros. O rollback reintroduz a autorização anterior insegura e só deve ser aplicado com autorização específica.

As definições efetivas de Storage e de acesso aos bytes precisam reconfirmação read-only antes do rollout. Esta tarefa usa catálogo histórico e scripts, sem consultar produção. Operações rh/ausencia não são habilitadas onde não existir policy permissiva segura; sem infraestrutura completa a confirmação de doença deve permanecer bloqueada/documento pendente.

## Evidência local

PostgreSQL 17.6 efémero: 9 PASS / 0 FAIL. Duas empresas, Administrativos A/B, Gerência A, Encarregado, colaboradores/viaturas/ausências próprios e externos. SELECT/INSERT/UPDATE/DELETE metadata e Storage, empresa enviada falsamente, entidade de tipo errado, UUID externo conhecido, caminhos inválidos; OR amplo de admin não reabre acesso. UPDATE/MOVE/DELETE Storage sem policy permissiva continuam negados; com policy permissiva ALL sintética, ownership ainda impede target externo. Documentos/Storage de obra legítimos e anexos próprios preservados. Rollback restaura todas as policies exatamente. Testes não utilizam qualquer tabela Pacote 2.

Commit autocontido: cinco scripts novos, fixture, suite e este documento. O SHA é o commit que introduz estes ficheiros. Prova de aplicação sobre origin/main registada no relatório final da correção, sem alterar main.
