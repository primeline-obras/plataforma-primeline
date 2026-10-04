# Correção de escrita financeira e alertas de inativos — 04/10/2026

**GO LOCAL para nova auditoria independente. Não é autorização de aplicação em produção.** As seis RPCs financeiras recusam os casos entre empresas exercitados e mantêm operações legítimas. O Encarregado inativo deixa de ler alertas. A varredura do mesmo domínio encontrou caminhos alternativos, também corrigidos e reproduzidos em testes locais.

A auditoria anterior foi preservada e enviada: `origin/audit/encarregado-autorizacao-final-20261004 = 10f065a1fb1645dec3bc43e02489557a06374325`. A branch `fix/autorizacao-financeira-cross-tenant-20261004` nasceu exatamente de `ff949e64f6d56986a3de6ac979c567cf745cfdb3`. O SHA final desta correção consta da entrega Git.

## Inventário reconfirmado

Fonte: catálogo capturado em `tests/fixtures/encarregado-catalogo-real-20261004.json`, snapshots auxiliares de privilégios/integridade e consumidores atuais em `src`. Não se voltou a consultar produção. O inventário das seis RPCs, incluindo ACL, owner, search_path anterior, hashes e callers encontrados, está em `tests/fixtures/financeiro-autorizacao-inventario-20261004.json`.

Todas são **SECURITY DEFINER, owner postgres** e tinham EXECUTE de `postgres` e `authenticated`, sem PUBLIC/anon/service_role. Não havia validação da empresa do recurso. As cinco operações de pagamento/devolução usavam `fn_e_financeiro()`. O avanço de fluxo usava essa guarda para `paga` e autorização técnica de obra nas outras transições. `fn_e_financeiro()` concede acesso a Financeiro e aos administradores reconhecidos pelo helper existente; a autorização por papel foi preservada.

| Assinatura | Escritas diretas | Consumidor encontrado | Correção |
|---|---|---|---|
| `fn_marcar_fatura_paga(uuid,date)` | faturas | RPC instalada; sem chamada no frontend atual encontrado | sessão ativa e empresa da fatura bloqueada antes de alterar pagamento |
| `fn_desmarcar_fatura_paga(uuid)` | faturas | `src/app.js`, reversão do pagamento | mesma guarda de recurso antes da reversão |
| `fn_devolver_fatura_financeiro(uuid,text)` | faturas | `src/app.js`, devolução pelo Financeiro | mesma guarda antes da devolução; motivo continua obrigatório |
| `fn_avancar_estado_fluxo_fatura(uuid,text,date,text)` | faturas | `src/app.js`, fluxo técnico/financeiro | guarda da empresa em todas as transições; papel Financeiro exigido em `paga`; permissões técnicas originais preservadas nas restantes |
| `fn_marcar_faturacao_auto_paga(uuid,date,numeric)` | faturacao | `src/app.js`, recebimento de faturação | guarda da empresa do documento bloqueado antes de pagamento/recebimento |
| `fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)` | faturacao_recebimentos, faturacao | RPC de contrato instalada; sem chamada no frontend atual encontrada | bloqueio e autorização do documento **antes do replay**, além das validações, revisão e idempotência existentes |

Parâmetros de alvo: UUID da fatura/faturação; não recebem empresa como prova de autorização. O workflow recebe também estado, data e observação; recebimento parcial recebe versão, data, valor, request_id e valor esperado. Os restantes parâmetros econômicos e contratos de resposta permanecem iguais.

Não foram encontrados outros callers internos das seis RPCs nos corpos do catálogo capturado. Triggers de faturas/faturação podem produzir auditoria/eventos e foram instalados no harness. Não há prova nesta tarefa sobre configuração cron remota; nenhum job real foi invocado. A execução autenticada foi mantida para compatibilidade e testada, em vez de eliminar as RPCs legítimas.

## Autorização e concorrência

`fn_autorizacao_sessao_ativa()` deriva a identidade de `auth.uid()` e exige `utilizadores.ativo IS TRUE`. É SECURITY DEFINER, owner postgres, search_path `pg_catalog`, e expõe somente um booleano para a sessão atual.

`fn_financeiro_autorizar_obra(uuid,boolean)` é **helper privado**, sem EXECUTE para PUBLIC, anon, authenticated ou service_role. A RPC resolve a obra da entidade existente e bloqueada, depois chama o helper como owner. O helper bloqueia o utilizador ativo e a obra com `FOR SHARE`, exige empresa não nula e igualdade de empresa, e verifica o papel financeiro quando a operação é de pagamento. Na variante técnica, a função chamadora mantém a sua autorização original de papel/responsabilidade.

Os locks da fatura/faturação, do utilizador e da obra permanecem até ao fim da transação. Os testes confirmaram que desativar o ator, mudar a sua empresa ou mudar a empresa da obra noutra ligação fica bloqueado durante a operação. Recebimentos concorrentes com a mesma revisão permitem uma gravação e recusam a outra com stale revision. Dois pedidos simultâneos idênticos retornam sucesso com um único movimento.

As RPCs usam `search_path=pg_catalog, public, pg_temp`, tabelas e helpers qualificados. As recusas de sessão/empresa e de papel financeiro usam SQLSTATE `42501`. Entidade inexistente e entidade de outra empresa recebem a mesma mensagem segura de indisponibilidade. O helper não aceita uma empresa fornecida pelo cliente.

EXECUTE final das RPCs: postgres/authenticated. Service_role não ganhou novo canal público e não pode executar diretamente estas RPCs. Owner e consumidores internos conservam os helpers técnicos anteriores. Um owner que pretenda usar uma RPC de aplicação precisa do contexto autenticado válido; não se criou um bypass sem sessão.

## Caminhos alternativos encontrados e fechados

A varredura foi limitada ao domínio pedido, usando o inventário anterior como mapa e reconfirmando corpos, grants e consumidores. Não reiniciou uma auditoria integral dos 247 objetos.

Foram reproduzidos localmente acessos entre empresas por Gerência/Gestão em caminhos adicionais:

| Caminho | Antes | Depois |
|---|---|---|
| DELETE REST de fatura | podia apagar fatura de outra empresa | zero linhas alteradas |
| `fn_decidir_fatura`, `fn_decidir_faturacao_auto` | aprovação técnica fora da empresa por autorização administrativa global | recusada; Diretor da empresa/obra mantém aprovação |
| `fn_devolver_fatura_administrativo` | devolução fora da empresa | recusada; Diretor próprio mantém operação |
| `fn_vincular_fatura_subempreitada` | alteração de vínculo fora da empresa | recusada; equipa técnica própria mantém operação |
| dois overloads de `fn_editar_fatura_pendente` | edição financeira fora da empresa | recusada; Administrativo autorizado mantém edição própria |
| edição com novo obra_id/fornecedor_id | campos recebidos podiam deslocar o âmbito | valida origem e destino reais; fornecedor precisa pertencer à empresa da obra |
| `fn_apagar_guia_fatura`, `fn_apagar_anexo_fatura` | Financeiro podia apagar registo associado a fatura alheia | recusado; operação própria preservada |
| `fn_eliminar_mapa_comparativo`, `fn_eliminar_item_comparativo` | administração global podia apagar mapa/item de outra empresa | recusado; técnico da obra própria mantém eliminação/recalculo |

Esses acessos pertencem ao mesmo problema de autorização por recurso/empresa. Foram corrigidos nesta tarefa, sem criar regras económicas novas. Não se alterou Storage nem bytes de anexos: as RPCs continuam a devolver o caminho conforme contrato existente.

Os grants reais de `faturas` e `faturacao` já excluíam UPDATE; o PATCH financeiro direto não era um exploit reproduzido. Não se concedeu UPDATE. Foram adicionadas **24 policies restritivas de escrita**, somente nos comandos já concedidos, em dez tabelas: faturas, faturacao, faturas_itens, faturas_anexos, faturas_guias, mapas_comparativos, comparativo_itens, comparativo_propostas, comparativo_ajustes e comparativo_itens_precos.

Essas policies intersectam as permissões existentes com a empresa da obra, resolvida através dos pais reais quando necessário. As regras de papel existentes continuam a decidir se a operação é permitida. `fn_financeiro_obra_da_empresa(uuid)` é a guarda pura usada por RLS e pelo postcheck. SELECT financeiro legado permanece com o comportamento anterior; esta tarefa fecha escrita, não redesenha leitura administrativa global.

A matriz local avaliou todas as 24 expressões USING/WITH CHECK com recursos próprios e externos. O DELETE REST foi exercitado ponta a ponta. A avaliação de expressão não deve ser confundida com testar todas as combinações de dados/constraints por REST em cada tabela.

Os quatro helpers P0 originais continuam sem EXECUTE externo. Os helpers de importação técnica e geração/reconciliação de alertas que já eram internos mantêm ACLs. `fn_importar_mapa_gestao` já deriva a empresa de utilizador ativo e resolve obras/fornecedores/colaboradores nessa empresa; não foi modificado. Não se encontrou outro P0/P1 residual nos caminhos exercitados desta tarefa. Isso não substitui a nova auditoria independente de todos os ramos relevantes.

## Alertas de inativos

Nova policy `alertas_sessao_ativa`: **RESTRICTIVE SELECT**, exige sessão ativa e combina-se com todas as policies permissivas existentes. Destinatário pessoal, destinatario_role, obra_responsaveis residual ou responsabilidade antiga não podem contornar a condição de atividade. Histórico e responsabilidades permanecem intactos.

`fn_resolver_alerta(uuid)` também exige sessão ativa no início, porque SECURITY DEFINER não pode depender apenas de RLS. Os checks existentes de papel/obra e o contrato de resolução são preservados.

O frontend foi inspecionado: o painel consulta `alertas` diretamente por REST e usa `fn_resolver_alerta`; a vista consolidada também consulta a tabela. Ambos passam pela proteção backend. Nenhum ficheiro de aplicação frontend foi alterado. As regressões de isolamento de sessão continuam a limpar DOM/cache em mudança de identidade e logout.

Testes HTTP: Encarregado ativo autorizado mantém leitura; inativo obtém zero linhas para alertas de movimentação, viatura e agenda, incluindo uma responsabilidade residual sintética. Não houve eliminação de histórico para resolver autorização.

## Pacote de rollout consolidado

Não existe migration separada para aplicar depois do hotfix anterior. Os cinco scripts `supabase/encarregado_escopo_*` formam um único pacote consolidado a partir do catálogo real capturado, anterior ao hotfix. Não aplicar ambos os candidatos em sequência.

| Script | Conteúdo |
|---|---|
| `encarregado_escopo_precheck.sql` | permanece com fingerprint canónico completo `2be961099e9694bdd29ba95d3cc10173`; já inclui todas as definições/ACL/policies alteradas agora; aborta se o catálogo divergir |
| `encarregado_escopo_backup.sql` | permanece como snapshot privado do catálogo completo e ACL bruta de funções; inclui funções financeiras, policies de alertas, owners/search_path e grants de tabela/coluna |
| `encarregado_escopo_migration.sql` | hotfix anterior mais guardas desta tarefa, em uma transação; sem atualização de linhas operacionais |
| `encarregado_escopo_postcheck.sql` | comparação integral do catálogo fora da lista de alterações, ACL/owner/search_path, 24 policies, guarda de sessão/empresa; percorre identidades existentes somente em SELECT e prova zero alertas para inativos |
| `encarregado_escopo_rollback.sql` | restaura definições e ACLs equivalentes do snapshot; remove apenas policies/helpers desta entrega; aborta se houver drift; sem CASCADE |

O postcheck real é **somente leitura**. Não invoca pagamentos/recebimentos para testar escrita real. A autorização negativa/positiva das RPCs, atomicidade e concorrência foram provadas no ambiente local. A guarda pura de empresa é exercitada no postcheck sem os locks das RPCs. Este limite é explícito.

O backup é de catálogo para reversão do escopo; não é backup de dados operacionais. Persistem os P2 registados na auditoria anterior: o fingerprint não cobre todos os atributos de schema/roles/triggers/constraints/índices, e o rollback pode tornar explícitas ACLs antes implícitas. O teste de rollback recuperou o fingerprint canónico e os privilégios efetivos; próximos prechecks não devem assumir igualdade da representação bruta de ACLs.

Ordem futura, apenas com autorização: PRECHECK → BACKUP privado → MIGRATION consolidada → POSTCHECK somente leitura. Qualquer divergência ou exceção exige parar. Não executar rollback automaticamente se a instalação for correta. Estes scripts não foram executados na BD real.

## Testes e resultados

| Grupo | Resultado final |
|---|---|
| Correção: PostgreSQL 17.6 + PostgREST 16.4 local | **75 PASS, zero skip** |
| Regressões nativas Quadro/Cadastro RH/Medicina | **197 PASS, zero skip** |
| 22 ficheiros de regressão unitária/estática/PGlite | **63 PASS, 4 SKIP**, total 67 |
| Browser sessão | **7 cenários PASS** |
| Browser RNC | **7 cenários PASS** |
| Browser Quadro | **3 grupos PASS**, três viewports |
| Browser Medicina | **PASS**, quatro perfis, três viewports, histórico, inativos, idempotência e sem DML direto |

Total das três execuções Node com contagem formal: **339 testes, 335 PASS, 4 SKIP, zero falhas finais**. Browser é apresentado separadamente. Os quatro skips por dependência RH continuam sem aprovação. A cobertura nativa de RH não transforma esses skips em PASS.

As seis RPCs têm prova HTTP de baseline externa, prova equivalente recusada no candidato, operação própria por Financeiro/Gestão/Gerência, utilizador inativo, papel errado, ausência de perfil, UUID inexistente, UUID externo, anon e atomicidade. PUBLIC e service_role foram verificados por privilégios efetivos; helper privado não é executável por nenhum papel externo. O replay de recebimento valida empresa antes de devolver o documento.

Foram preservados triggers de previsão e preço, wrapper técnico de comparativo e chamada técnica do congelamento. Esses testes são locais, não execução de cron real. O harness usa corpos e RLS capturados e os triggers reais relevantes; não é uma clonagem completa de todos os defaults/constraints de produção.

O mock de `tests/medicine-browser.mjs` foi atualizado para reconhecer a RPC de leitura `fn_ausencias_equipa_encarregado`, já existente no candidato anterior. Essa alteração não simula escrita nem altera lógica funcional; resolve a falha de harness documentada na auditoria.

Regressões: Quadro, RH, Medicina, Subempreitadas, Financeiro/faturas, Planeamento, RNC, sessão, alertas, ausências/férias, documentos e Viaturas. Nenhum resultado local foi apresentado como validação em produção.

Comandos principais: `node --test tests/financeiro-cross-tenant.test.mjs`; `node --test tests/workforce-controlled.test.mjs tests/medicina-trabalho.test.mjs`; grupo de 22 ficheiros; browsers `session-boundary-browser`, `encarregado-rnc-browser`, `workforce-controlled-browser` e `medicine-browser`. Binários/dependências locais definidos por `QUADRO_PG_BIN`, `QUADRO_TEST_DEPS`, `QUADRO_POSTGREST`, `MEDICINA_PG_BIN`, `MEDICINA_TEST_DEPS` e `PLANNING_PLAYWRIGHT`.

## Entrega e limites

**GO LOCAL para solicitar nova auditoria independente do candidato consolidado.** Não foi iniciada essa nova auditoria nesta tarefa. Não há P0/P1 conhecido ainda aberto nos caminhos aqui reproduzidos; permanece a necessidade de revisão independente dos scripts ampliados e dos consumidores, incluindo os P2 existentes.

Nenhum SQL foi aplicado em produção. Nenhuma alteração de dados reais, frontend publicado, merge em main, teste real de Encarregado, marker B, backup B ou Fase B. A auditoria anterior permaneceu intacta no remoto.
