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
5. Publicar, mediante autorização futura, o frontend corrigido. O candidato usa app v171 / workforce-allocation v2, com endpoints v1 explícitos.
6. Recarregar as sessões/clientes. Verificar Network: consultas `fn_quadro_contexto_v1`, preview/confirmação `fn_quadro_operar_v1`, nenhum INSERT/PATCH/DELETE de alocação. Identificar o SHA efetivamente servido e testar Administrativo/Gestão e Encarregado. Não usar a ausência de tráfego num instante como prova de que todos os separadores antigos foram atualizados.
7. Executar `quadro_controlado_fase_b_precheck.sql`, guardar a identificação do SHA publicado/validado e executar `quadro_controlado_fase_b_backup.sql` imediatamente antes do hardening. Este backup é da Fase A instalada, sem pressupor que as contagens iniciais ainda sejam iguais.
8. Na mesma sessão de operador, definir `primeline.quadro.frontend_validado` com o SHA confirmado; instalar `quadro_controlado_fase_b.sql`.
9. Executar `quadro_controlado_fase_b_postcheck.sql` (também disponível como `quadro_controlado_postcheck.sql`) e repetir as validações finais.

O identificador de frontend é uma pré-condição operacional do script administrado pelo proprietário. Não é um sinalizador de autorização de DML. A proteção de escrita usa tabela privada, inacessível a anon/authenticated/service_role, com autorização limitada à transação, pessoa, dia e autor.

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

Resultados finais: **58 testes do backend Quadro passaram**, zero falhas/skips; **176 testes de regressão passaram**, zero falhas e um skip opcional (RH_XLSX externo não fornecido). Oito navegadores offline passaram: Quadro, RH frontend, Cadastro RH, Medicina, Planeamento, seleção de obra, atribuição de Viaturas e validades.

PostgreSQL **17.6**, cluster descartável, dois clientes independentes, dados sintéticos. Todos os seis triggers reais do Quadro estão exercitados; tabela de auditoria e alertas são locais. Outros helpers periféricos não exercitados continuam identificados como stubs na fixture. Nenhum teste de escrita usa produção.

Cobertura: quatro combinações suportadas + antiga/B recusada; revisão após estado vazio; idempotência; concorrência; tenant; períodos; ausência; RH com/sem alocação; falhas depois do INSERT da pessoa; importação; notificações; backup/postchecks; rollback após uso e forward-fix.

Regressões: Quadro, Cadastro/Importação RH, Ponto legado, Férias, Medicina, Viaturas e Planeamento. Medicina: apenas atualização do mock do contexto v1 no teste original; nenhum ficheiro de produção de Medicina alterado. Navegadores offline usam desktop/tablet/mobile e verificam console/ausência de DML direto.

O browser Cadastro RH original usa bootstrap temporário para caminhos Windows e Edge instalado; o teste/código RH de produção não é alterado por esse bootstrap. O caso opcional de Excel externo com 47 pessoas é separado: depende de RH_XLSX, não se inventa ficheiro real para o substituir.

## Riscos restantes / próxima etapa

- **Nova varredura crítica obrigatória**, incluindo revisão independente dos scripts A/B e dos rollbacks antes de autorizar SQL real ou publicação.
- B depende da atualização efetiva dos clientes; o SHA registado pelo operador não prova por si só que todos os separadores foram recarregados.
- Lock global serializa escritas do Quadro. É uma opção conservadora para coexistência antigo/novo; medir duração/contensão antes de otimizar noutro pacote.
- Ponto mantém dívida temporal intencional; não se considera correta a herança, nem se preenche cobertura inventada.
- Conflitos e coexistências históricos são preservados. Alteração exige confirmação humana; remoção explícita continua disponível no âmbito autorizado.
- Questões P2/P3 da auditoria que não pertencem à correção P0/P1 continuam fora do escopo (ex.: UX de intenções/períodos, limitações visuais preexistentes e novos pacotes).
- Nenhuma nova regra de Financeiro, Férias, horas, custos ou novo Ponto foi implementada.

**Sem GO para produção. Próxima etapa: nova varredura estrutural crítica.**
