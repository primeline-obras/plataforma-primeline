# AD-15 — isolamento tenant no histórico de HE diária — 12/10/2026

## Resultado

AD-15: **CORRIGIDO LOCALMENTE**. Não constitui GO do módulo de avaliação diária. AD-03, AD-13 e AD-14 permanecem como achados anteriores, fora desta tarefa. Não houve SQL real, ativação real, deploy, merge ou push.

## Base e recuperação

Repositório confirmado: primeline-obras/plataforma-primeline. Working tree original limpo; fetch sem sobrescrita. Os três SHAs remotos conferidos foram:

- feat/folha-avaliacao-diaria-20261012: a27322708af530865a0074a25e961579c3becef4.
- audit/folha-avaliacao-diaria-20261012: 396e616ddb921a7c42677b7e019874adc6757214.
- fix/encarregado-falta-20261012: 24e57b10995aeddfc9a2ce98d54e20d3d45b308f.

Branch isolada: fix/folha-he-tenant-20261012, criada exatamente da auditoria 396e616d. A branch de Faltas não é descendente do candidato diário e não foi incorporada. O relatório da auditoria e todas as implementações originais foram preservados.

## Diagnóstico anterior à alteração

Função: public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text), em supabase/folha_avaliacao_diaria.sql, linhas 221–319 no candidato. A declaração lê w de p_dados.work_id. O ramo daily_he_validate/daily_he_disregard valida avaliação/fingerprint/revisão, mas não valida nem remove esse contexto. O INSERT final em folha_gestao_historico usa w diretamente. A FK/campo histórico não garante o tenant da obra; RLS não resolve a escrita feita pela RPC SECURITY DEFINER.

Reprodução original, antes da correção, com o teste já preparado pela auditoria: ator Administrativo e avaliação da empresa sintética 1; work_id da empresa 2; preview e confirmação committed=true; histórico empresa=1 e obra.empresa=2. A operação de prova terminou por ROLLBACK. O output AUDIT_HISTORY_TENANT marcou contract=FAIL. A suite observacional original teve 60 testes concluídos; isso confirma a reprodução dos achados, não é um veredicto de segurança verde.

O histórico já permite obra_id NULL (supabase/folha_ponto_v2_gestao.sql). Uma decisão HE diária é por pessoa/data/avaliação, podendo agregar várias obras; não requer obra inventada. A entidade histórica permanece o UUID real da avaliação.

Revisão dos restantes ramos novos: referência administrativa admite obra explícita e aplica folha_privado.obra; configuração/retificação usam obra e versão; ativação é global. A ativação também aceitava obra arbitrária no histórico. Estes caminhos receberam apenas validações tenant/contexto, sem corrigir duração de horário, referência dos perfis técnicos ou constraints dos outros P1.

## Correção mínima e separada

O pacote é aditivo: cinco scripts novos substituem somente a definição completa da RPC diária. Os SQLs originais da avaliação diária, fixtures originais, testes anteriores e frontend não foram alterados.

- Ator/empresa provêm de folha_privado.ator; a linha do utilizador ativo é bloqueada FOR SHARE.
- empresa_id opcional do payload diferente da empresa do ator é recusado com 42501; nunca autoriza escolher tenant.
- Colaborador é validado no tenant e bloqueado FOR SHARE antes do replay.
- daily_activation/daily_he_validate/daily_he_disregard recusam qualquer work_id não nulo, inclusive obra da própria empresa. São ações globais; HE grava histórico com obra_id NULL.
- Obra explícita nas ações que legitimamente usam obra é validada no tenant e bloqueada FOR SHARE.
- A avaliação é localizada por empresa real/pessoa/data, bloqueada FOR UPDATE e validada antes do replay. evaluation_id opcional deve corresponder ao UUID real. Outra pessoa/avaliação/empresa é recusada 42501.
- Obra de origem da avaliação é validada e bloqueada FOR SHARE, sem a usar como obra arbitrária do histórico HE.
- Ordem de lock pessoa/dia preservada antes do lock de avaliação. Locks existentes do Quadro/61001 e configuração continuam usados.
- Ativação valida e bloqueia as relações das jornadas existentes com as respetivas obras. Não altera nem revalida os cálculos de duração do AD-13.
- Histórico continua derivado de u.empresa_id/u.id/a.id, com before/after e request reais. Campos de autor enviados pelo cliente não substituem o ator.
- Permissões Administrativo/Gestão, recusa de Gerência/perfis técnicos, fingerprint, revisão, token, replay, concorrência e HE normal permanecem iguais. Nenhuma alteração de RLS/GRANT/policy/cálculo ou dado histórico na migration.

## SQLs completos preparados

Ordem local/futura condicionada: precheck → backup → migration → postcheck. Rollback apenas manual.

1. supabase/folha_he_tenant_ad15_precheck.sql — READ ONLY; AD15_PRECHECK_OK. Exige candidato diário instalado, hash/owner/SD/search_path/ACL exatos e DML direto fechado, incluindo grants de coluna. Recusa histórico diário já incoerente; não reconcilia automaticamente.
2. supabase/folha_he_tenant_ad15_backup.sql — AD15_BACKUP_OK. Schema privado primeline_ad15_backup; função/catálogo de autorização, oito tabelas relacionadas e ledger completo. Locks e snapshot integral. Recusa backup pré-existente.
3. supabase/folha_he_tenant_ad15.sql — AD15_MIGRATION_OK. Definição completa CREATE OR REPLACE; repete baseline e comparação integral do backup antes e depois. Nenhuma atualização de linhas de negócio ou ativação.
4. supabase/folha_he_tenant_ad15_postcheck.sql — READ ONLY; AD15_POSTCHECK_OK. Hash do corpo corrigido e metadados exatos, backup privado e dados/ledger integralmente iguais.
5. supabase/folha_he_tenant_ad15_rollback.sql — AD15_ROLLBACK_OK em instalação sem uso. Restaura somente a definição anterior; recusa drift/uso desde o snapshot. Não apaga histórico nem escreve snapshots sobre dados laborais. A restauração reintroduz o comportamento anterior conhecido; usar somente mediante análise/autorização, nunca automaticamente.

Gerador reproduzível: tests/attendance-daily-he-tenant-package.mjs. Extrai a definição original completa e aplica somente as inserções explícitas do AD-15; não faz patches de corpos na BD por replace/EXECUTE. O rollback executa a definição íntegra guardada.

Hash de baseline segue a convenção já existente da avaliação diária: SHA256 de prosrc, CR removido e btrim de espaço/LF/tab. Esperado: 189eb93caeea512629b5823403657032ddabab49358d9b66901caaf244d357fb. O hash novo usa prosrc completo com CR removido: e5dc4c1c3aea0720fcf142e4d52121c40e61d0b1308f87a81e23f5eaf66f2fef. Não são hashes da mesma normalização; cada gate aplica a convenção explícita correspondente.

Estes scripts são um hotfix sobre o candidato diário já instalado LOCALMENTE. Não substituem os prechecks de produção do pacote diário nem autorizam instalá-lo. Os outros P1 mantêm o módulo NO-GO.

## Testes e regressões

Ambiente: PostgreSQL 17.6 descartável, localhost, fixtures sintéticas, chamadas como authenticated com ator da fixture. Nenhuma credencial ou conexão de produção.

Runner: tests/attendance-daily-he-tenant.test.mjs. Reutiliza em memória o bootstrap e as regressões originais de attendance-daily-backend.test.mjs; emite runner temporário fora do Git. Exige QUADRO_PG_BIN e QUADRO_TEST_DEPS, sem SKIP silencioso.

Matriz final: **59 PASS / 0 FAIL / 0 SKIP**, incluindo regressões diárias originais e casos focados:

- Mesmo cenário AD-15 antes/depois: depois, 42501 em preview e confirmação; zero alterações de avaliação, histórico e ledger.
- HE validar/não considerar e wrapper fn_folha_gestao_v2 recusam obra externa; obra arbitrária própria também recusada.
- Pessoa de outra empresa, UUID de avaliação externa e empresa forjada: recusados sem escrita parcial.
- Referência/horário/retificação/ativação com obra externa: recusados.
- Operação legítima sem obra: histórico com avaliação/colaborador/autor/empresa coerentes e obra NULL.
- Preview preserva HE pendente; validação mantém pendência de processamento e bloqueia fecho; não considerar retira apenas a pendência HE específica, mantendo horas e outras pendências.
- Mesmo request em duas ligações confirma uma vez; decisão concorrente com revisão stale é recusada; replay não duplica e revalida tenant/papel.
- Alteração concorrente de empresa do colaborador/obra bloqueada por lock_timeout 55P03 durante a confirmação transacional; sem drift entre validação e gravação.
- RLS/DML direto/helper privado recusados; SD/search_path/ACL preservados; Gestão legítima continua permitida e perfis indevidos recusados.
- Precheck/backup/migration/postcheck/rollback/reinstalação locais PASS, sem modificar dados; rollback após uso recusado. Exposição de ACL da RPC ou backup é detectada pelo postcheck.
- HE dos dias normais, referências, períodos, equipa, multiobra, históricos, payroll e concorrência originais continuam aprovados no runner.

Regressões adicionais: **43 PASS / 0 FAIL / 0 SKIP** em attendance-daily-static, attendance-domain, attendance-v2-static, attendance-client e session-boundary. Total final selecionado: **102 PASS / 0 FAIL / 0 SKIP**; não inclui os 60 testes observacionais anteriores na soma.

Transparência de ambiente: primeira execução das 43 regressões no checkout Windows teve 42 PASS/1 FAIL porque a asserção textual antiga /^.*\nBEGIN;/ não aceita CRLF. A mesma fonte auditada foi exportada para diretório temporário e somente os endings SQL foram normalizados CRLF→LF: 43 PASS. Nenhum teste ou ficheiro original foi corrigido/relaxado nesta tarefa. A falha era de representação textual, não regressão funcional do AD-15.

## Limites e entrega

- Sem validação HTTP/JWT/REST nova nem prova do catálogo de produção; a fixture SQL usa identidade sintética explícita.
- Se já houver histórico diário incompatível numa futura instalação, precheck exige STOP e reconciliação humana separada. Não reescrever históricos para fazer passar.
- Ainda não existe endpoint/processamento monetário novo de HE diária: a HE validada continua a bloquear fecho como exigido.
- AD-03/AD-13/AD-14 e restantes limites da auditoria original permanecem. Nenhum outro P1 foi iniciado.
- Nenhum ficheiro em src/ ou index.html alterado, nenhum cálculo de horas alterado.
- Commit apenas local; push não autorizado. SHA local e estado limpo são entregues na resposta final. A origem main permanece 1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0.
