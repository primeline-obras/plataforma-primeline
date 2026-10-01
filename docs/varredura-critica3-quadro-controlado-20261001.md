# Terceira varredura crítica — Pacote 1 Quadro controlado

**Atualização final: checks limitados do P1 concluídos com autorização separada. 29 testes locais passaram; defeito permanece P1. A varredura completa continua interrompida. A secção final abaixo supera as limitações de instrumentação descritas no registo inicial.**

## Decisão e âmbito

**P1 confirmado. Varredura interrompida conforme a instrução de parar ao encontrar P0/P1. Nenhuma correção do candidato. Não há GO para Fase A, frontend ou Fase B.**

- Candidato: feat/quadro-controlado-20261001, `b681d76cf6b32306e4f3302696de122b2e7a0cfc`.
- Auditoria: audit/quadro-controlado-pacote1-critica3-20261001, criada exatamente desse candidato.
- Base de produção indicada pelo utilizador: `9e0e6c40b439160201289823db8cfee0b9adad02`.
- Apenas relatório, teste adicional e fixture de metadata foram criados na auditoria. Sem commit/push nesta etapa.

## P1-01 — Emissão de notificações incompatível com o índice unique de alertas

### Evidência de schema

Foi consultada a captura read-only anterior guardada localmente, não a BD real nesta sessão:

- `ponto-extra-parsed.json`: definição de alertas_ocorrencia_unica_idx.
- `ponto-schema-parsed.json`: ocorrencia_chave uuid, nullable, sem default.
- Metadata mínima reproduzível: tests/fixtures/quadro-alertas-indice-real.json. Não contém dados pessoais/reais.

Índice capturado:

```sql
CREATE UNIQUE INDEX alertas_ocorrencia_unica_idx
ON public.alertas USING btree (
 tipo,
 entidade_tipo,
 entidade_id,
 data_evento_referencia,
 COALESCE(antecedencia_dias, '-1'::integer),
 COALESCE(ocorrencia_chave, '00000000-0000-0000-0000-000000000000'::uuid)
);
```

A fixture quadro-base.sql inclui ocorrencia_chave sem default, mas **não instala esse índice**. Isso permite que os testes habituais aceitem linhas que o schema capturado rejeita.

Limite: o índice foi confirmado no levantamento anterior; não foi reconfirmado ao vivo nesta auditoria. A reprodução local demonstra a incompatibilidade com esse contrato real capturado, não uma escrita/teste em produção.

### Função e instrução

`supabase/quadro_controlado_fase_a.sql`, função fn_quadro_notificar_controlado_v1, INSERT em public.alertas na linha 1031. A definição equivalente acompanha o forward-fix A.

O INSERT emite uma linha por destinatário. Mantém, para todos eles:

- tipo = movimentacao_equipa;
- entidade_tipo = quadro_pessoal_alocacao;
- entidade_id = p_alocacao;
- data_evento_referencia = p_data;
- antecedencia_dias = 0;
- ocorrencia_chave = NULL, pois não é preenchida nem tem default.

Os destinatários são diferentes, mas destinatario_utilizador_id **não pertence ao índice**. DISTINCT ON elimina duplicação do mesmo utilizador, mas não evita a colisão entre dois utilizadores distintos.

### Reprodução local capturada

PostgreSQL 17.6 descartável, SQL integral do candidato, Fase B instalada pelo fluxo privado de validação. Dados sintéticos:

1. Actor Encarregado 13 autorizado na obra 100.
2. Pessoa 30, dia 2026-10-05, sem alocação.
3. Obra tem Diretor 14 e a empresa tem Administrativo 10; ambos ativos, com login, distintos do actor.
4. Instalar no teste o índice capturado acima.
5. Preview v1 da alocação é válido e committed=false.
6. Confirmar o mesmo preview.

Resultado real do PostgreSQL local:

```text
SQLSTATE 23505
constraint: alertas_ocorrencia_unica_idx
Key (...)=
(movimentacao_equipa, quadro_pessoal_alocacao,
 <UUID sintético da alocação>, 2026-10-05, 0,
 00000000-0000-0000-0000-000000000000) already exists.
```

Stack capturado:

```text
fn_quadro_notificar_controlado_v1(uuid,date,uuid,uuid,uuid)
  line 69 at SQL statement
fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)
  line 71 at PERFORM
fn_quadro_operar_v1(text,jsonb,boolean,text)
  line 75 at assignment
```

A função emite o INSERT sem ON CONFLICT. A confirmação falha; não é apenas uma notificação perdida. A mensagem SQL chega ao cliente como erro.

A implementação do emissor é comum a A e B, portanto a incompatibilidade não é resolvida pelo hardening B. A reprodução foi feita em B; não foi iniciada outra reprodução em A após o P1.

### Atomicidade e limite do teste adicional

O erro foi capturado com assert de SQLSTATE/constraint e rollback para SAVEPOINT. A leitura subsequente de alocações confirmou zero linhas para a pessoa/dia sintéticos. A tentativa seguinte de contar quadro_operacoes como authenticated falhou corretamente com permission denied, pois a tabela é privada.

Essa falha de inspeção do teste impediu completar os asserts finais de operações/histórico/alertas. O finally do teste fez ROLLBACK da transação inteira; o cluster foi encerrado. Não afirmar que esses asserts adicionais passaram.

A repetição para ajustar apenas o papel usado na inspeção foi **recusada pela revisão automática**, por exceder a ordem de parar após P1. Não foi contornada. O teste permanece como estava na primeira captura. A prova 23505 independe dessa falha posterior de inspeção.

### Impacto e recomendação técnica

Uma operação legítima de Encarregado com dois destinatários pode não ser guardada. Um único destinatário pode passar; outro alerta para a mesma chave também pode colidir. A origem preexistente ou nova da incompatibilidade não muda o bloqueio funcional do candidato.

Correção a desenhar noutra tarefa: alinhar a identidade/deduplicação da notificação com os destinatários e com o evento lógico, de forma determinística e idempotente, preservando as regras dos outros alertas. Não remover a proteção unique, não usar UUID aleatório para esconder colisões e não usar DO NOTHING que suprima silenciosamente um destinatário. Nenhuma solução foi implementada.

## Resultados executados nesta sessão

Comando local: node --test tests/workforce-critica3.test.mjs tests/workforce-allocation-client.test.mjs, com QUADRO_PG_BIN e QUADRO_TEST_DEPS definidos para PostgreSQL 17.6/pg locais.

**116 testes contabilizados pelo runner: 114 pass, 2 fail, 0 skip.** As duas falhas são o teste adversarial adicional (inspeção de quadro_operacoes com role indevido, depois de capturar 23505) e o seu teste-pai. Não são duas falhas independentes de produto.

Os testes do candidato copiados na auditoria e o client passaram. A fixture do índice existe apenas dentro da transação do teste adicional e é revertida; os casos habituais de notificação continuam a executar sem índice, o que não os torna uma prova válida de compatibilidade com o schema capturado.

Não foram repetidos browsers/regressões integrais depois do P1. Resultados das sessões anteriores não são contados como execuções desta auditoria.

## Achados anteriores — estado individual

| Achado | Estado/evidência nesta auditoria |
|---|---|
| Rollout antigo/novo incompatível | PASS nos testes SQL antigo/antigo, antigo/A, novo/A, novo/B e antiga/B recusada. Cache, propagação parcial e abas reais ainda não certificados. |
| Ponto sem cobertura explícita | PASS transitório: teste preserva herança temporal e verifica que A não redefine as duas RPCs. **Dívida transitória intencional — remover no Pacote 2.** |
| Gerência com escrita global indevida | PASS nos testes: consulta/RH preservados; novo Quadro não concede escrita global. |
| Revisão após vazio | PASS: manhã/tarde/dia inteiro, reload/replay e concorrência de Encarregado. |
| Notificações restauradas | **FAIL/P1** contra índice capturado real; casos anteriores omitiam o índice. |
| Backup incompleto | Parcial: scripts A/B e rollback da suíte passam; inventário e consistência integral sob concorrência não encerrados. |
| Postcheck de permissões | PASS nos ataques locais existentes: grant privado/helper/policy permissiva recusados. Não certifica toda a estrutura nem a funcionalidade de notificações com índice. |
| GUC como trust boundary | PASS: falsificação não autoriza B; script não usa o GUC como gate. |
| Gate privado inacessível à aplicação | PASS nos ataques locais: anon/authenticated/service_role sem leitura/DML/EXECUTE; script de marcação recusa esses roles. |
| Validação nova após rollback B | PASS: autorização anterior invalidada; forward-fix sem nova validação recusado; nova validação owner aceita. |

## Segurança, permissões, writers e temporalidade

Passaram os testes locais existentes de empresa divergente, utilizador inativo, Encarregado autorizado/origem não autorizada, Diretor/Adjunto leitura limitada, Preparador recusado, Administrativo/Gestão e Gerência sem escrita global. DML direto e sinalizador de escrita falsificado foram recusados. Nenhum bypass de tenant foi demonstrado no trecho executado.

Isso não equivale a revisão integral de todas as SECURITY DEFINER, grants indiretos, SQL dinâmico e requests cruzados entre autores. A varredura de todos os writers instalada/histórica ficou pendente ao parar por P1. Não declarar inexistência de writers esquecidos.

Novo Quadro mantém data explícita nos testes. Ponto legado preserva temporariamente a herança; nenhuma alocação futura foi inventada na instalação sintética. Não houve manipulação de dados 03–14/10.

## Locks e concorrência

Duas ligações reais locais testaram: mesma pessoa/revisão → uma confirmação e uma STALE; mesmo request/payload → replay idempotente; payload diferente → conflito; Encarregado após remoção total → revisão/concorrência coerentes. Preview/replay não geraram gravações adicionais nos casos existentes.

Não foram concluídos testes de pessoas diferentes, antigo+novo, cadastro+mover, renomear+mover, ausência+mover, timeout/starvation/contensão ou resposta perdida durante rollback. **Não há certificação de aceitabilidade do lock global em produção.**

## Cadastro RH, Ponto e notificações

Passaram cadastro com/sem alocação, ausência/conflito/erro após criação com rollback, importação de IDs existentes e erro de lote. Não foi completada toda a matriz A/B/rollbacks, erro após contrato, replay e concorrência RH.

O Ponto legado foi preservado pelos testes executados. Não se concluiu ainda a revisão de todos os efeitos indiretos de helpers novos.

Notificações: preview zero, replay/rollback/remoção básicos passam na fixture habitual; **a confirmação com dois destinatários falha quando o índice real é incluído**. Split/merge, escritório, matriz completa de destinatários/roles e alertas órfãos ainda não certificados.

## Backup, postcheck, rollback e gate

A sequência de scripts A→marcação owner→precheck/backup B→B→postcheck foi executada sinteticamente. Marcador ausente/errado, timestamp errado, instalação errada, drift de ACL/helper, duplicação e spoof GUC/payload foram recusados nos casos locais existentes. Falha injetada após consumo reverteu consumo e DDL B juntos.

Rollback B preservou operações e compatibilidade A; exigiu nova validação no forward-fix. Rollback/forward-fix A preservaram os dados sintéticos testados. Não certifica todas as respostas perdidas, replay após retirada, colisões de backup, todas as constraints/copias nem reconstrução sem intervenção manual em qualquer estado possível.

## Dados legados e regressões

A referência 227 alocações / 98 movimentos / 27 pares / 2 coexistências não foi relida da BD nesta sessão. A fixture contém 227/98, mas não replica integralmente os 27 pares reais. Os testes preservam o snapshot sintético; isso não prova todos os dados reais nas quatro transições.

Browsers desktop/tablet/mobile, original de Medicina, Viaturas, Planeamento, Férias e regressões integrais não foram repetidos após a instrução de parar por P1. Não contar como aprovados. UX de Encarregado em tablet permanece não certificada por esta terceira auditoria.

## P0/P1/P2/P3 e decisão final

- P0 novo confirmado: nenhum no trecho executado. Auditoria incompleta não prova ausência.
- P1 confirmado: incompatibilidade do emissor de notificações com alertas_ocorrencia_unica_idx.
- P2 anteriores (UX, obra encerrada, cadastro novo sem idempotência, consumidores/ausência posterior): não revalidados integralmente, não declarar resolvidos.
- P3: sem conclusão nova.

| Etapa | Decisão |
|---|---|
| Fase A | NO-GO para aprovação do Pacote 1: emissor já instalado em A é incompatível com o índice capturado; auditoria interrompida. |
| Frontend | NO-GO: confirmação legítima de Encarregado pode falhar. |
| Fase B | NO-GO: o gate privado passou os ataques executados, mas não corrige a falha funcional. |

Não há sequência aprovada de instalação/publicação. Próximo passo: rever o achado, autorizar correção separada e voltar à varredura completa. Para concluir os asserts finais do teste adicional é necessária autorização separada após a recusa automática; não realizar isso silenciosamente nesta tarefa.

Nenhuma escrita em produção, nenhuma migration real, nenhum deploy, nenhum merge. Candidato intacto. Apenas ficheiros de auditoria locais.


## Caracterização final do P1 — colisão de alertas

### Âmbito e resultado final

Etapa separada autorizada, limitada ao P1. Nenhuma correção no candidato nem retomada da varredura completa. Executado exclusivamente PostgreSQL 17.6 local/sintético, tanto na Fase A como na Fase B, com o índice capturado no levantamento real anterior. Não foi feita nova consulta à BD real; a origem e a definição do índice permanecem documentadas na fixture de metadata.

**29 testes passaram, 0 falhas, 0 skips.** O teste antigo foi ajustado apenas na branch de auditoria: as inspeções privadas passaram a usar owner local, sem enfraquecer permissões. As falhas instrumentais do registo inicial ficaram superadas nesta etapa expressamente autorizada.

### A/B/C — causa, índice e linhas em colisão

A confirmação válida por Encarregado chama fn_quadro_notificar_controlado_v1. O INSERT gera linhas por utilizador, mas omite ocorrencia_chave. O índice é global, sem WHERE: tipo, entidade_tipo, entidade_id, data_evento_referencia, COALESCE(antecedencia_dias,-1), COALESCE(ocorrencia_chave,UUID zero). Destinatário/obra/role não fazem parte da chave. Não foi alterado.

As duas linhas tentadas no teste B são reproduzidas exatamente abaixo; todos os UUIDs são sintéticos:

| Campo | Administrativo | Diretor |
|---|---|---|
| tipo | movimentacao_equipa | movimentacao_equipa |
| entidade_tipo | quadro_pessoal_alocacao | quadro_pessoal_alocacao |
| entidade_id | 37dd9dd0-a92b-44fd-87f6-7ca6d6f3264b | 37dd9dd0-a92b-44fd-87f6-7ca6d6f3264b |
| data_evento_referencia | 2026-10-05 | 2026-10-05 |
| antecedencia_dias | 0 | 0 |
| ocorrencia_chave | NULL | NULL |
| destinatario_role | administrativo | diretor_obra |
| destinatario_utilizador_id | 00000000-0000-4000-8000-000000000010 | 00000000-0000-4000-8000-000000000014 |
| destinatario_colaborador_id | NULL | NULL |
| obra_id | 00000000-0000-4000-8000-000000000100 | 00000000-0000-4000-8000-000000000100 |


Um trigger temporário de instrumentação LOCAL emitiu NOTICE com NEW antes da verificação unique; o listener do teste capturou as duas linhas mesmo quando o statement foi revertido. Não alterou a função do candidato nem o índice. Ambas possuem a mesma chave de seis componentes; o segundo INSERT provoca SQLSTATE 23505. A ordem observada foi Administrativo e Diretor, mas não é contrato de ordenação do SELECT.

### D — atomicidade, rollback e request

Snapshots completos antes/depois do statement falhado foram iguais para:

- quadro_pessoal_alocacao;
- quadro_dias_revisoes;
- quadro_pessoal_movimentos;
- alertas, incluindo o primeiro alerta tentado;
- quadro_operacoes;
- log_auditoria;
- quadro_escrita_interna.

A confirmação falhada não deixou alocação, revisão, movimento, alerta, auditoria ou permissão temporária parcial; não registou/consumiu request_id. A igualdade foi demonstrada inclusive em mover/split/merge com dados anteriores existentes, não apenas numa tabela inicialmente vazia.

Após rollback para SAVEPOINT, reduziu-se a elegibilidade a um destinatário SOMENTE na fixture local. O mesmo request/payload/token foi confirmado com sucesso, idempotent=false. Replay do request confirmado foi idempotent=true e preservou exatamente revisão, histórico e alertas. Isso prova que a falha não impede retry legítimo após a futura correção; não é uma correção do emissor nem autorização para manipular destinatários reais.

Todos os cenários terminaram em ROLLBACK integral; o cluster local foi encerrado. **Sem estado parcial observado: permanece P1, não sobe para P0.**

### E/F — alcance funcional e perfis

| Operação/actor | Notificação implementada | Colisão |
|---|---|---|
| Alocar por Encarregado | Sim, destino obra diferente de origem | Sim com 2+ destinatários; testado A/B |
| Mover A→B por Encarregado | Sim, por par origem/destino | Sim; testado A/B |
| Split por Encarregado | Sim para os pares de obra que mudam | Sim; testado A/B |
| Merge por Encarregado | Pode emitir por vários pares de origem/destino | Sim, inclusive um único destinatário comum aos pares; testado A/B |
| Remover | Nenhum novo alerta | Não por este emissor; alertas anteriores ficam preservados |
| Renomear linha | Só Administrativo/Gestão autorizados; emissor não notifica esses actores | Não; caso Administrativo testado A/B |
| Cadastro RH com alocação inicial | Pelos perfis de Cadastro; emissor só aceita actor Encarregado | Não no caso Administrativo com alocação em obra testado A/B |
| Alocar/mover/split/merge por Administrativo | Emissor retorna antes do INSERT | Sem alertas/23505 deste caminho; testado A/B |
| Alocar/mover/split/merge por Gestão | Emissor retorna antes do INSERT | Sem alertas/23505 deste caminho; testado A/B |
| Destino escritório/sem obra | Emissor retorna quando p_destino é NULL | Não por este caminho; regra inspecionada, sem alargar permissões de Encarregado |

No Cadastro RH, não se assume que todos os perfis possam chamar a criação: continuam as permissões existentes. O defeito depende de o actor efetivo ser Encarregado e de haver destino obra diferente; os actores legítimos de Cadastro Administrativo/Gestão/Gerência não satisfazem esse filtro. Não foi reaberta a matriz inteira de Cadastro.

Remover uma alocação conserva os alertas antigos. A referência de entidade pode deixar de apontar para uma alocação existente; não se declarou esse ciclo de vida correto nem se alteraram/resolveram alertas nesta tarefa. A decisão de preservação/estado desses avisos deve entrar na revisão da futura correção.

### G — destinatários e limite exato

Regra real implementada, união e deduplicação por utilizador:

1. Encarregados vinculados à obra de origem (prioridade 1).
2. Diretores vinculados à origem (prioridade 2).
3. Diretores vinculados ao destino (prioridade 3).
4. Todos os Administrativos ativos da empresa, com login (prioridade 4).

Autor excluído; destinatários finais devem estar ativos, na empresa e com auth_user_id. Mesmo utilizador em vários grupos recebe uma linha, com obra_ref do grupo de maior prioridade. Adjunto não é um grupo elegível por esse papel; pode receber se também possuir um vínculo elegível. A seleção dos vínculos usa obra_responsaveis.papel; a label destinatario_role usa utilizadores.funcao, não uma nova verificação de correspondência entre ambos.

Administrativo e Diretor elegíveis devem ambos receber segundo o SELECT atual. Diretores podem ser da origem, destino ou ambos. Encarregado só é incluído pelo vínculo na origem, excluindo o autor. Não há destinatário automático Encarregado do destino.

A constraint capturada de obra_responsaveis é UNIQUE(obra_id,utilizador_id,papel), não UNIQUE(obra_id,papel); admite vários Diretores/Encarregados distintos. O teste criou dois Administrativos elegíveis e confirmou a colisão. Não existe teto numérico fixo nessa consulta/modelo: máximo é a cardinalidade da união deduplicada desses grupos, limitada aos utilizadores elegíveis da empresa, excluído o autor. Em termos globais, não supera N utilizadores ativos com login da empresa menos o autor.

Casos A e B:

- zero destinatários: guarda sem alertas;
- um destinatário numa chave ainda não usada: guarda um alerta;
- Administrativo + Diretor: falha na segunda linha;
- dois Administrativos, sem Diretor: falha na segunda linha;
- Diretor origem + Diretor destino + Administrativo + outro Encarregado origem: quatro elegíveis; falha já na segunda linha;
- um destinatário, mas chave de alocação/dia já alertada: nova movimentação também falha;
- merge de duas origens para outro destino: um destinatário por par pode colidir entre as duas chamadas que reutilizam a entidade agregada.

Portanto, o limite não é simplesmente “dois destinatários”: basta a segunda linha com a mesma chave, dentro do INSERT, entre chamadas do mesmo merge ou contra um alerta prévio. Ocorrência de domínio atual não distingue movimentações sucessivas da mesma alocação/dia.

### Replay e novo request

Replay confirmado não cria segundo alerta, revisão ou histórico. Novo request com revisão atual para a mesma alocação já desejada é no-op, sem novo alerta/revisão/histórico; não contorna a unicidade. Um novo request para movimentação realmente distinta que reutiliza a mesma alocação/dia pode falhar mesmo com um destinatário. A futura chave deve distinguir o evento lógico, além do destinatário.

### H — impacto do índice global

O índice sem predicado cobre todos os tipos de public.alertas, não apenas movimentacao_equipa. A leitura dos scripts do repositório identificou, entre outros:

| Área | Uso observado/risco de alteração global |
|---|---|
| Viaturas | seguro_viatura e inspecao_viatura usam entidade/validade; atribuição retargeta destinatários pendentes. Incluir utilizador na unicidade faria a chave mudar na troca de responsável e pode permitir outra linha para a mesma validade. |
| Medicina | primeira_consulta_medicina e consulta_medicina; candidato de Medicina usa ocorrencia_chave ligada ao ciclo e ON CONFLICT DO NOTHING. Não transportar regras novas nem modificar deduplicação por ciclo. |
| Agenda/salas | reserva_sala usa entidade_id do participante da reserva, já distinto por destinatário; não necessita alteração global para este P1. |
| Documentos/EPI | validade_documento e validade_epi usam entidade/data/antecedência e ON CONFLICT DO NOTHING; vários desses alertas são por role, sem utilizador individual. |
| Outros | O índice abrange qualquer tipo atual/futuro com componentes preenchidos; não foi feito inventário exaustivo de todos os módulos instalados nesta etapa limitada. |

Estas são dependências estruturais constatadas nos scripts e metadata previamente levantada, não certificação de todas as versões atualmente instaladas. Não houve alteração nem teste de escrita real em nenhum desses módulos.

Adicionar destinatario_utilizador_id diretamente ao índice introduziria NULL-distinct: os alertas por role com utilizador NULL poderiam duplicar apesar de ON CONFLICT DO NOTHING. COALESCE/NULLS NOT DISTINCT evitaria esse caso, mas ainda mudaria a identidade no retarget de Viaturas e separaria ocorrências de domínio por destinatário. Não fazer essa alteração global como correção rápida.

### I/J — opções e recomendação, sem implementação

| Opção | Impacto, idempotência/histórico/compatibilidade | Migration/risco |
|---|---|---|
| A: incluir utilizador na unicidade global | Muda todos os tipos, retarget e NULL; não distingue dois eventos sucessivos para a mesma alocação/dia. Exige rever emissores e dados duplicados. | Migration do índice e testes de todos os módulos; risco alto para este pacote. |
| B: ocorrencia_chave determinística por evento + destinatário, apenas Quadro | Preserva índice e outros módulos. Deve representar evento lógico/request, pessoa/data, par origem/destino e destinatário; replay mantém a mesma identidade. No-op não cria ocorrência nova. Distingue movimentos sucessivos e grupos de merge. Preserva autor, origem/destino e histórico existentes. | SQL completo das funções afetadas, testes com índice real e revisão do fingerprint/rollout; sem migration global do índice. Menor alteração, risco controlável. |
| C: ocorrência de domínio + destinatários em tabela filha | Separa domínio e entrega de forma clara, suporta muitos destinatários e histórico por destinatário. Exige migração de leitura/RLS/resolução e compatibilidade com todos os consumidores. | Migration e alteração estrutural/API/UX; risco/escopo maiores que este Pacote 1. |
| D: solução seletiva por tipo no índice | Índice/predicado próprio só para movimentacao_equipa preserva parte dos outros tipos, mas requer excluir este tipo do índice global e definir identidade de evento. Continua a exigir migration e análise de dados. | Alternativa a discutir; maior impacto que usar o campo de ocorrência existente. |

**Recomendação para Pacote 1: B**, com chave determinística que inclua evento lógico e destinatário; não apenas destinatário isolado e não UUID aleatório para fugir da unicidade. O request_id já é controlado/idempotente, mas o helper precisa receber/obter esse contexto de forma privada e coerente; definir explicitamente pares de origem/destino no merge. Não aplicar ON CONFLICT DO NOTHING indiscriminado para suprimir destinatários legítimos. Deve evitar notificações duplicadas no replay e permitir uma ocorrência nova apenas para outra alteração real.

A implementação exige autorização separada. Não foi alterado emissor, índice, frontend, regra de destinatários nem candidato.

### K — classificação e encerramento seguro

**Permanece P1. Não há motivo demonstrado para P0: a falha é atómica e não deixa estado parcial.** O Pacote 1 continua sem GO; a terceira varredura completa continua interrompida, não concluída por estes 29 testes focados.

Pendente para amanhã:

1. Rever/aprovar o desenho B e autorizar a correção do emissor no candidato, em tarefa separada.
2. Implementar e testar a correção com o índice real, movimentos sucessivos, merge/split, destinatários múltiplos, replay e ciclo de vida dos alertas após remoção.
3. Retomar uma varredura crítica completa desde o início sobre o novo SHA, incluindo as áreas não concluídas no relatório inicial. Não substituir essa varredura por estes checks focados.
4. Nenhuma instalação/publicação está autorizada; só avaliar rollout após nova revisão e autorização explícita.

Os únicos ficheiros para commit/push nesta etapa são relatório e testes/fixture da branch de auditoria. Candidato continua exatamente em b681d76cf6b32306e4f3302696de122b2e7a0cfc. Nenhuma escrita em produção, nenhuma migration real, nenhum deploy, nenhum merge.
