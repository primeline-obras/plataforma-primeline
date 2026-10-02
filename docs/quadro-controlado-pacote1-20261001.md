# Pacote 1 — Quadro controlado: candidato corrigido após varredura

## Estado

Branch `feat/quadro-controlado-20261001`; correção do candidato `029d448267711f32464a9ce00720427c33a98a88`, conforme auditoria `900310acc78d9bbd675f8ae82719666d12ba80f1`.

Preparado e testado localmente. Nenhuma migration aplicada à BD real, nenhuma alteração de dados reais, nenhum deploy ou merge em main. **Não há GO para produção. É obrigatória nova varredura crítica separada.** O SHA desta revisão consta na entrega e em `git log -1`.

## P0 corrigidos

1. Instalação em duas fases, com RPCs novas `fn_quadro_operar_v1` e `fn_quadro_contexto_v1`. A RPC antiga conserva o contrato na Fase A; apenas recebe o lock comum antes dos locks individuais. O frontend novo não substitui silenciosamente o contrato antigo.
2. As funções `fn_listar_ponto_obra` e `fn_guardar_ponto_obra` não são redefinidas. Os três helpers de permissão antigos também ficam inalterados. Os postchecks comparam as definições instaladas com o backup.

O novo Quadro resolve exclusivamente a data solicitada. O Ponto antigo conserva temporariamente a herança temporal que existe em produção. Não foram criadas alocações para 03–14/10, nem copiados dias, nem inferida presença a partir de responsabilidade.

**Dívida transitória intencional — remover no Pacote 2.** O Pacote 2 deverá incluir Ponto pessoa/dia, programação explícita, UX para copiar dias e cobertura operacional validada antes de retirar a herança do Ponto.

## Scripts e sequência de rollout

Todos os scripts estão em `supabase/`. São completos, transacionais e preparados para execução posterior autorizada. Não executar o antigo `quadro_controlado.sql` ou `quadro_controlado_rollback.sql`: ambos interrompem explicitamente e indicam os scripts por fase.

1. Executar/rever `quadro_controlado_precheck.sql` — leitura, definições/grants/policies/triggers, escritores e fotografia 227 alocações / 98 movimentos. Divergência exige parar e repetir o preflight, sem atualizar automaticamente esses limites.
2. Executar `quadro_controlado_backup.sql`. Exportar para arquivo privado externo, confirmar acesso e comparar as cópias. Nenhuma linha real deve entrar no Git.
3. Instalar `quadro_controlado_fase_a.sql`.
4. Executar `quadro_controlado_fase_a_postcheck.sql` e a validação funcional do cliente antigo e novo.
5. Publicar, mediante autorização futura, o frontend corrigido. O candidato usa app v172 / workforce-allocation v3, com endpoints v1 explícitos.
6. Recarregar as sessões/clientes. Verificar Network: consultas `fn_quadro_contexto_v1`, preview/confirmação `fn_quadro_operar_v1`, nenhum INSERT/PATCH/DELETE de alocação. Identificar o SHA efetivamente servido e testar Administrativo/Gestão e Encarregado. Não usar a ausência de tráfego num instante como prova de que todos os separadores antigos foram atualizados.
7. Após a prova operacional, executar SEPARADAMENTE e manualmente como sessão/role `postgres` o script `quadro_controlado_marcar_frontend_validado.sql`. Regista contrato 1, release estável `quadro_frontend_contract_v1`, instalação/tentativa atuais, timestamp e identidade do operador; timestamps anteriores à tentativa ou futuros são recusados. O SHA servido é metadado opcional. Não executar este script automaticamente durante A/B.
8. Executar `quadro_controlado_fase_b_precheck.sql` e `quadro_controlado_fase_b_backup.sql` imediatamente antes do hardening. O backup inclui o controlo e as validações privados. Não restaurar esses marcadores como autorização de nova tentativa.
9. Instalar `quadro_controlado_fase_b.sql`. O script repete os checks de integridade A, verifica o marcador e consome-o na mesma transação das alterações B. Falha reverte tanto o consumo como o hardening.
10. Executar `quadro_controlado_fase_b_postcheck.sql` (também `quadro_controlado_postcheck.sql`) e repetir as validações finais.

A BD não prova autonomamente a versão no Cloudflare. O operador confirma no browser os assets, os endpoints v1, a ausência de DML direto, Administrativo/Gestão/Encarregado e o reload dos clientes relevantes; só depois regista essa validação. O módulo servido expõe `WORKFORCE_FRONTEND_CONTRACT` (`version: 1`, `releaseId: quadro_frontend_contract_v1`). Pode ser inspecionado por import do asset servido no DevTools. O Git SHA não é uma referência circular exigida pelo gate.

O custom GUC anteriormente utilizado deixou completamente de participar nos scripts de autorização. Qualquer valor configurado pela aplicação é irrelevante para o rollout.

### Gate privado de rollout

Schema `primeline_quadro_rollout`, owner `postgres`, fora do schema público/API. Tabelas `controlo` e `validacoes`, RLS ativa sem policies; nenhum grant de schema, tabela, coluna ou função para PUBLIC/anon/authenticated/service_role. Helpers são SECURITY INVOKER privados, nunca RPCs públicas. Apenas operador com session_user=current_user=postgres pode executar os scripts. Superutilizadores da BD continuam, naturalmente, capazes de administrar objetos; não são contas de aplicação.

O controlo tem UUID da instalação A, tentativa, estado, contrato/release estáveis e fingerprint da estrutura A. A validação guarda instalação/tentativa, contrato/release, SHA opcional, autor, data e fingerprint, com marcas de consumo/invalidação. O fingerprint cobre definições/ACL/owners dos escritores e funções relevantes, tabelas privadas do núcleo, colunas, policies, triggers e constraints. Exclui linhas operacionais: uso legítimo do Quadro/RH não invalida a instalação. Divergência estrutural exige parar/rever, não atualizar o fingerprint para forçar a execução.

Após rollback B, o estado volta a A, a tentativa aumenta, regista a hora de início da nova tentativa e a autorização anterior fica invalidada, preservada para auditoria. Forward-fix B exige NOVA prova operacional e execução do script de marcação pelo owner para a tentativa atual. Sem isso, recusa. O backup original B continua disponível para restauração estrutural; não reativa validações antigas. O gate exige que o backup corresponda ao UUID e fingerprint da instalação A atual; o rollback B conserva essa instalação, enquanto um forward-fix A inicia outra instalação e exige rever/substituir o backup B com arquivo privado prévio. Não apagar um backup para forçar a execução.

Rollback A marca a instalação como retirada e invalida validações. Forward-fix A gera nova identidade de instalação e novo fingerprint apenas após reinstalar a estrutura A; é necessária nova validação operacional antes de B. Não há autorização para migração real ou publicação nesta entrega.

### Fase A compatível

- Cria revisões, operações idempotentes e permissões privadas de escrita.
- Adiciona origem/request ao histórico existente, sem preencher retroativamente.
- Preserva grants/policies/DML necessários ao frontend antigo. O guard aceita operações controladas ou aplica integralmente a validação antiga ao caminho legado.
- Usa um lock global de escrita antes dos locks de pessoa/dia. O trigger por statement cobre DML direto; a RPC antiga recebe esse lock antes do seu advisory lock individual. RPCs novas e renomeação seguem a mesma ordem.
- Escritas legadas incrementam revisão e conservam o âmbito histórico; operações do núcleo incrementam uma vez por pessoa/dia.
- Cadastro/importação RH usam o mesmo núcleo interno. Gerência mantém a autorização legítima de Cadastro RH, separada da autorização de movimentação no Quadro.
- Notificações antigas continuam a funcionar; o trigger antigo não duplica as operações controladas, que têm emissor privado derivado da regra instalada.

### Fase B final

- Revoga DML direto em tabelas e colunas, incluindo PUBLIC/anon/authenticated/service_role.
- Preserva leitura autenticada com RLS por empresa/âmbito.
- Desativa a RPC antiga para clientes normais; o corpo também recusa o contrato antigo se invocado por operador privilegiado.
- Guard exige a permissão privada do núcleo. Outros escritores genéricos sem essa permissão não são autorizados a escrever no Quadro.
- Cadastro RH continua funcional pelo núcleo comum.

## Matriz de compatibilidade

| Frontend | Backend | Resultado |
| --- | --- | --- |
| Antigo | Antigo | DML/RPC legítimos funcionam conforme as regras anteriores |
| Antigo | Fase A | DML e RPC antigos continuam funcionais; revisões novas acompanham essas escritas |
| Novo | Fase A | Contexto v1 + preview + confirmação atómica funcionam |
| Novo | Fase B | Mesma API v1; escrita direta fechada |
| Antigo | Fase B | Escrita não suportada; recusa antes da corrupção. Exige reload |

A Fase A pode coexistir com sessões antigas. Não autorizar B antes de atualizar/recarregar os clientes. Um separador antigo que sobreviva à transição fica bloqueado com segurança; não existe fallback de escrita direta no cliente novo.

## Permissões finais

| Perfil | Leitura | Escrita nova no Quadro |
| --- | --- | --- |
| Administrativo | Empresa atual | Global na empresa, auditada |
| Gestão da Plataforma | Empresa atual | Global/override na empresa, auditável |
| Gerência | Leitura legítima da empresa | **Nenhuma nova movimentação global**; Cadastro RH continua autorizado |
| Encarregado | Âmbito autorizado | Origem e destino autorizados; sem Escritório/linhas globais |
| Diretor/Adjunto | Obras sob responsabilidade | Sem movimentação |
| Preparador | Sem novos poderes | Sem novos poderes |
| Inativo/outra empresa | Recusado | Recusado |

Os helpers novos de autorização não substituem `fn_pode_gerir_quadro`, `fn_quadro_minha_obra` ou `fn_pode_consultar_quadro`. O frontend restringe explicitamente a ação aos perfis de escrita e às capacidades devolvidas pelo contexto.

## Revisão de pessoa/dia vazio

`quadro_dias_revisoes` mantém revisão e `obras_visiveis`, união dos âmbitos reais anteriores/novos. O contexto pode devolver essa revisão ao responsável autorizado mesmo sem alocações. Não revela revisões de outro tenant ou de obras sem autorização.

Comprovado: manhã/tarde/dia inteiro → última remoção → allocations=[] → reload preserva revisão 2 → operação seguinte usa 2 e devolve 3. Replay repete request e snapshot da confirmação original. Duas sessões de Encarregado após estado vazio: apenas uma confirma; a outra recebe STALE_REVISION. Nenhuma herança de dia anterior no Quadro.

## Notificações

Emissor privado mantém a regra instalada: autor Encarregado ativo; origem Encarregado/Diretor, destino Diretor, Administrativo da empresa; destinatários ativos com login, sem duplicação por destinatário e sem notificar o próprio autor. Remoção e destino sem obra não introduzem alertas novos.

O núcleo deriva origem/destino do estado anterior/final, incluindo split/merge dos períodos, e agrupa pares repetidos. O trigger legado ignora apenas a operação com permissão interna válida. Alertas são transacionais, com `enviar_email=false`, e só são visíveis externamente após commit.

Testes: preview=0; adição sintética=2 destinatários; replay=0 extra; movimento 100→101=2 destinatários corretos (ADM e Diretor da origem); remoção=0 extra; rollback=0 persistidas. Dados/IDs são exclusivamente sintéticos.

## Cadastro/importação e escritores

| Escritor | Fase A | Fase B |
| --- | --- | --- |
| DML direto do frontend antigo | Preservado com guard antigo e revisão por trigger | Revogado |
| save/remove/rename do frontend novo | Apenas RPC v1 | Apenas RPC v1 |
| `fn_quadro_operar` antiga | Corpo/contrato preservados + lock comum | Bloqueada |
| `fn_quadro_operar_v1` / rename | Núcleo privado comum | Núcleo privado comum |
| Construtores de colaborador 6/12 argumentos | Wrappers do construtor/núcleo privado | Continuam autorizados no RH |
| fn_rh_guardar/importar → fn_rh_guardar_interno | Cadeia/atomicidade preservadas | Mesmo mecanismo |
| fn_mgo_inserir_json_compativel(regclass,jsonb) | Privada, sem chamador legítimo encontrado para Quadro | Guard final recusa escrita sem permissão do núcleo |
| Scripts históricos de definição/preenchimento | Não reaplicar | Não reaplicar |

Inventário instalado original: três escritores diretos (RPC antiga e dois construtores). O scan das funções/SECURITY DEFINER/SQL dinâmico foi preservado no preflight; postchecks interrompem perante writer não inventariado. O SQL genérico privado não é uma RPC normal.

Cadastro com alocação cria apenas a data explícita de admissão fornecida. Sem alocação não inventa destino/data. Falha da alocação reverte também colaborador e cadeia RH. Histórico contém autor, origem cadastro/importação e antes/depois, sem criar histórico retroativo.

A importação existente exige IDs já cadastrados: não cria pessoas/alocações iniciais. Essa regra foi preservada. Testes importam pessoas com/sem alocação e verificam preservação e rollback integral do lote perante erro. Não foi adicionada criação por importação fora do contrato existente.

## Backup e postchecks

Backup A guarda linhas das tabelas relacionadas, definições completas das funções, ACL efetiva, owner/security/search_path, os três helpers antigos, Ponto/RH, policies, grants de tabelas, colunas/defaults/ACL, constraints, triggers/estado e sequências relacionadas. Inclui o notifier substituído. Backup B guarda a fotografia instalada A das funções/ACL/owner, policies, tabelas/RLS, colunas/grants e triggers, mais cópias das alocações, movimentos, revisões e operações atuais, antes de fechar DML. O lock SHARE mantém essas cópias consistentes perante escritas normais.

Postchecks A/B verificam anon/authenticated/service_role e PUBLIC; RPCs públicas/privadas; owner/SECURITY DEFINER/search_path; RLS sem policies nas três tabelas privadas; nenhuma permissão de tabela/coluna privada; grants/policies finais; DML direto; sequências se existirem; triggers ativos; writers permitidos. Também comparam Ponto/helpers antigos e ACL/owner dos construtores RH e triggers modificados com o backup. UUIDs não introduzem sequências novas.

A: compara ACL das tabelas legadas com backup. B: somente SELECT autenticado, nenhum DML nem grants por coluna, RPC antiga fechada. As expressões das policies finais são comparadas com as assinaturas validadas no PostgreSQL 17.6; divergência obriga a parar, sem flexibilizar o check automaticamente. Testes negativos provam recusa de grant privado indevido, helper exposto e policy permissiva. A prova frontend é complementar: testes exercitam o consumidor real e verificam ausência de DML direto no Network; o operador precisa confirmar a versão publicada antes de B.

## Rollback e forward-fix

- `quadro_controlado_fase_b_rollback.sql`: restaura somente os corpos/ACL afetados pela Fase B (guard, RPC antiga e predicado de leitura), mais grants/policies e grants por coluna da Fase A. Mantém alocações, operações, revisões, alertas e histórico já confirmados.
- `quadro_controlado_fase_a_rollback.sql`: restaura somente funções realmente substituídas na Fase A e ACL/policies legadas; não reescreve Ponto, Medicina ou helpers antigos inalterados. Retira o trigger de lock novo; fecha os endpoints v1. Mantém as tabelas privadas e colunas históricas para reconciliação. É necessário voltar/recarregar o frontend compatível; não existe remoção de dados para simular um estado anterior.
- `quadro_controlado_fase_a_forward_fix.sql`: reinstala as definições completas sobre estruturas retidas após rollback A; mantém todos os dados e incrementa revisões para invalidar previews antigos. Requer backup e DML legado aberto; não reabre B automaticamente. Executar postcheck A.
- `quadro_controlado_fase_b_forward_fix.sql`: reinstala integralmente a proteção final, após backup e nova confirmação do frontend. Executar postcheck B. Não altera alocações.

Rollback de B permite cliente antigo/novo em A. Rollback A torna o novo cliente fail-closed até retirada/reload. Backups nunca são apagados por rollback. O inventário amplo de funções serve para comparação; não autoriza restaurar indiscriminadamente funções de outros módulos. Não reaplicar A inicial sobre estruturas retidas; usar apenas o forward-fix revisto. Divergência não deve ser corrigida manualmente para forçar a execução.

## Testes e limites

Resultados da revisão anterior (não repetidos integralmente nesta correção): **58 testes do backend Quadro passaram**, zero falhas/skips; **176 testes de regressão passaram**, zero falhas e um skip opcional (RH_XLSX externo não fornecido). Oito navegadores offline passaram: Quadro, RH frontend, Cadastro RH, Medicina, Planeamento, seleção de obra, atribuição de Viaturas e validades.

PostgreSQL **17.6**, cluster descartável, dois clientes independentes, dados sintéticos. Todos os seis triggers reais do Quadro estão exercitados; tabela de auditoria e alertas são locais. Outros helpers periféricos não exercitados continuam identificados como stubs na fixture. Nenhum teste de escrita usa produção.

Cobertura: quatro combinações suportadas + antiga/B recusada; revisão após estado vazio; idempotência; concorrência; tenant; períodos; ausência; RH com/sem alocação; falhas depois do INSERT da pessoa; importação; notificações; backup/postchecks; rollback após uso e forward-fix.

Regressões: Quadro, Cadastro/Importação RH, Ponto legado, Férias, Medicina, Viaturas e Planeamento. Medicina: apenas atualização do mock do contexto v1 no teste original; nenhum ficheiro de produção de Medicina alterado. Navegadores offline usam desktop/tablet/mobile e verificam console/ausência de DML direto.

O browser Cadastro RH original usa bootstrap temporário para caminhos Windows e Edge instalado; o teste/código RH de produção não é alterado por esse bootstrap. O caso opcional de Excel externo com 47 pessoas é separado: depende de RH_XLSX, não se inventa ficheiro real para o substituir.

## Correção do gate após a segunda auditoria

Auditoria preservada na branch audit/quadro-controlado-pacote1-critica2-20261001, commit 28157ed. O GUC configurável pela aplicação aceitava qualquer texto não vazio; não era prova operacional confiável. Foi substituído pelo controlo privado descrito acima, sem alteração das funções funcionais de Quadro/RH/Ponto.

Nesta revisão: **115 testes de Quadro/gate/client passaram**, incluindo PostgreSQL 17.6 com duas ligações; **40 regressões passaram**, com 1 skip do Excel externo opcional RH_XLSX. Dois browsers offline passaram: Quadro (três viewports e console) e RH (três viewports, 49 combinações de permissões e console). git diff --check passou.

Ataques: DML e helpers privados negados a anon/authenticated/service_role; marcação recusada a esses roles; GUC/payload não autorizam B; marcador ausente, release/contrato/instalação/fingerprint/data inválidos recusados; drift de ACL recusa B; duplicação de marcador recusada; consumo e DDL B revertidos juntos em falha; rollback exige nova validação antes do forward-fix. O SHA opcional do frontend é apenas metadado. A comparação com 80d41cc confirmou os blocos funcionais anteriores de A e forward-fix A integralmente preservados.

Apenas estes testes foram repetidos nesta revisão. Os resultados históricos de Medicina/Viaturas/Planeamento acima não constituem nova execução nesta etapa. A nova varredura crítica completa permanece obrigatória; não emitir GO de produção.

## Riscos restantes / próxima etapa

- **Nova varredura crítica obrigatória**, incluindo revisão independente dos scripts A/B e dos rollbacks antes de autorizar SQL real ou publicação.
- B depende da atualização efetiva dos clientes; o SHA registado pelo operador não prova por si só que todos os separadores foram recarregados.
- Lock global serializa escritas do Quadro. É uma opção conservadora para coexistência antigo/novo; medir duração/contensão antes de otimizar noutro pacote.
- Ponto mantém dívida temporal intencional; não se considera correta a herança, nem se preenche cobertura inventada.
- Conflitos e coexistências históricos são preservados. Alteração exige confirmação humana; remoção explícita continua disponível no âmbito autorizado.
- Questões P2/P3 da auditoria que não pertencem à correção P0/P1 continuam fora do escopo (ex.: UX de intenções/períodos, limitações visuais preexistentes e novos pacotes).
- Nenhuma nova regra de Financeiro, Férias, horas, custos ou novo Ponto foi implementada.

**Sem GO para produção. Próxima etapa: nova varredura estrutural crítica.**

## Correção de notificações e pré-varredura local — 02/10/2026

O P1 da terceira auditoria foi corrigido somente nos emissores de alertas A/forward-fix A. A ocorrência controlada deriva de empresa, request privado, pessoa/data, par origem/destino e destinatário. O trigger legado deriva da revisão seguinte da pessoa/dia e destinatário. Ambas são determinísticas; o índice global não foi alterado.

Os testes habituais agora instalam o índice real capturado de alertas. A entrega executou 347 testes aprovados, zero falhas e um skip opcional RH_XLSX, mais oito browsers offline, incluindo o original de Medicina. Inclui 28 testes específicos de alertas e 29 de pré-varredura adicional, sem somar novamente as execuções isoladas.

Relatório completo: [quadro-controlado-prevarredura-local-20261002.md](quadro-controlado-prevarredura-local-20261002.md). Contém provas A/B/gate/rollback, escritores, limites e questões P2. Os resultados desta secção são os desta entrega; os números das secções anteriores são históricos.

**GO LOCAL apenas para nova auditoria independente. Sem GO para produção ou SQL real.** Nenhum acesso ao Supabase/Chrome autenticado/produção nesta sessão. As validações reais pendentes estão enumeradas no relatório.
## Correção dos três P1 da auditoria final — 02/10/2026

Ver [relatório de correção e pré-varredura](quadro-controlado-correcao-p1-20261002.md).

Pós-check B recalcula o catálogo atual contra uma referência privada obtida da A validada antes da instalação. Sete triggers são explicitamente obrigatórios; corpos/ACL/policies/objetos críticos são comparados, não apenas metadados de segurança. O alias postcheck é equivalente. O backup B agora deve incluir `primeline_backup.quadro_fase_b_estrutura_20261001`; B e forward-fix B recusam backup antigo sem essa referência. Não gerar referência a partir de um B com drift nem sobrescrever backups existentes.

Frontend limpa saving no finally do handler real, preservando o bloqueio enquanto a gravação está ativa. Sete dias têm targets legíveis e scroll horizontal; testes mouse/tap comprovam que data visual e payload coincidem em desktop/tablet/mobile. Cache-busting app v173/workforce-calendar v8.

Regras de alocação/RH/Ponto/alertas preservadas. GO local somente para nova auditoria independente; nenhuma autorização de aplicação/merge/deploy. P2/P3 e validações reais permanecem no relatório. A falha Agenda hardcoded continua documentada e intacta.
