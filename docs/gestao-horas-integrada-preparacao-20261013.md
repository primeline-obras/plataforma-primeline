# Gestão integrada de horas — preparação local de 13/10/2026

> Relatório histórico. O estado atual está no relatório de retoma de 14/10/2026; os estados "não implementado" abaixo descrevem o checkpoint de 13/10.

## Identidade e limites

Branch: `feat/gestao-horas-integrada-20261013`.
Base exata: `481b2477fb886e4ca31e7094404afcb170f79603`.
Worktree: `C:\Users\Cristiana\Documents\plataforma-primeline-horas-integrada`.
AD-03/13/14/15 presentes na base e reexecutados na cadeia PostgreSQL sintética.

Não houve SQL real, ativação, alteração de dados reais, push, merge ou deploy. Não se montou interface nova em app.js/index.html. As branches de origem/main permaneceram intactas. Os scripts são candidatos locais para revisão; não constituem autorização ou GO de instalação em produção.

## Matriz única

| Requisito | Componentes/contrato | Scripts/dependências | Estado e evidência | Risco/próxima verificação |
|---|---|---|---|---|
| HE HR-27 informativa | diaria_ad14_valida, diaria_recalcular, diaria_gestao_preservada, fn_folha_diaria_gestao_v2, payroll_facts, fn_folha_gestao_v2 | folha_hr27*, AD-03/13/14/15 existentes | Implementado localmente; reconhecer não exige processamento monetário e não bloqueia por si só; he_process recusado | Rever separadamente caminhos manuais antigos de HE antes de rollout; nenhuma conversão/apagamento massivo |
| Faltou neutro | fn_folha_faltou_v2, ausencias, folha_historico, ledger | folha_faltou_neutro*, HR-27 | Implementado localmente; hoje/ontem, Encarregado/equipa interna, conflito com horas, classificação Admin, identidade do autor no preview, replay/concor­rência | Closure do writer legado é pré-condição; não se alteram policies gerais de ausencias |
| Horários sugeridos/editáveis | attendance-hours-domain.js | jornadas individuais/vigência histórica, contexto v3 | Domínio preparado e testado; técnico sexta 5h/3h; sem referência não inventa horas | UI não montada; sugestões precisam de confirmação operacional |
| Personalizado factual | intervalFacts/destinos no domínio; writer periods_save existente | AD-03 e folha_avaliacao_diaria | Limites 4/16, start/end intactos, NULL/personalizado, ausência de dupla jornada testados | Writer destino-only abaixo ainda não implementado; não anunciar suporte completo |
| Destino de outro Encarregado | proposta fn_folha_destino_operar_v3 | necessidade de novo writer isolado + leitura autorizada | Contrato preparado, NÃO implementado | Não usar periods_save integral para editar factos de obras às quais o ator não tem acesso |
| Normal com jornada individual | proposta avaliação diária normal_individual | diaria_factos/pessoal/recalcular/save_periodo/concurrency | Preparado, NÃO implementado | Sugestão técnica 5h de manhã não pode virar HE por comparação com um período de 4h da obra |
| Dia Normal internos/externos | normalDaySelection atual + testes de exclusão por ausências | writers atuais | Comportamento atual preservado; Faltou sai da seleção e conserva equipa | Novos modos ainda não ligados à ação montada |
| Horas da equipa sem HE | fn_folha_relatorio_horas_v3 | folha_horas_leituras*, autenticação/obra | Implementado localmente; diário/semanal/mensal até 31 dias; legado separado; externos por fornecedor | Não é uma exportação nem uma conferência; não inclui custo ou HE |
| Conferência mensal interna | fn_folha_conferencia_contexto_v3/fn_folha_conferencia_v3; conferencias/historico | folha_conferencia_mensal*, HR-27/leitores | Implementado localmente; confer/devolve/valida por pessoa/mês, revisão/fingerprint, histórico, invalidação por factos, prova positiva mês anterior | Integração efetiva dos mapas/fecho montados ainda não feita; aprovação mensal isolada não declara payroll fechado |
| Meses anteriores | políticas ADM atuais, conferências e source_change | locks e writers existentes | Correção factual testada invalida conferência; confirmação fora da janela continua administrativa | Novos writers devem manter explicitamente a restrição |
| Externos Excel + Diretor | proposta fn_folha_externos_confirmar_v3 | nova confirmação protegida, leitor factual, codec XLSX | Leitor implementado; confirmação/exportação apenas preparadas | Não existe writer de confirmação nem Excel certificado; não usar CSV ou validação RH como substituto |
| Horas provisórias/consolidadas | attendance-hours-map.js | snapshot mensal validado + IDs/revisões | Contrato de domínio implementado/testado, NÃO ligado a mapas atuais | Provisórias/consolidadas mutuamente exclusivas; externos separados; custos antigos excluídos |
| Estimativas com custo aprovado RH | financialAvailability | tarifa com autor/revisão/vigência/prova | Disponibilidade do contrato testada; sem tarifa => só horas | valor_hora atual não prova aprovação histórica; não calcular custo de HE |
| Garantia/Outra | identidade UUID da referência no domínio/modelo; associação ADM proposta | novo writer/associação antes da validação | Contrato/modelo preparado; referência original preservada | Sem persistência/associação implementada; não usar Escritório como destino substituto |
| Apresentação horas | formatMinutes | minutos técnicos intactos | Testado: 8h, 7h30, 30min, 155h30; relógio HH:mm | Sem alteração de schema por formatação |
| Modelos visuais | docs/prototipos/gestao-horas-integrada-20261013.html | navegador isolado, dados sintéticos | 31 capturas: 15 desktop + 8 operacionais em cada tablet; 3 suítes offline | Pendente aprovação visual; sem páginas RH otimizadas para tablet |

## Backend implementado e scripts completos

Cada prefixo tem cinco ficheiros SQL completos: `_precheck.sql`, `_backup.sql`, `.sql`, `_postcheck.sql`, `_rollback.sql`:

1. `supabase/folha_hr27`
2. `supabase/folha_faltou_neutro`
3. `supabase/folha_horas_leituras`
4. `supabase/folha_conferencia_mensal`

Ordem LOCAL exercitada: base AD-03/13/14/15 → HR-27 → Faltou → leitores → conferência mensal.
Os backups privados sintéticos são `primeline_hr27_backup`, `primeline_faltou_backup`, `primeline_horas_leituras_backup`, `primeline_monthly_backup`. Catálogos de ACL de schema/tabela/coluna, proprietários, hashes, RLS/triggers e imagens dos dados são verificados nos gates específicos. Rollback recusa deriva/uso que apagaria evidência. Não se escreveu qualquer backup de produção no Git.
Os generators `tests/attendance-*-package.mjs` produzem definições completas a partir de fontes versionadas, não fazem patch textual na BD.

### Faltou

RPC `fn_folha_faltou_v2(p_acao text,p_dados jsonb,p_confirmar boolean,p_versao text)`.
`absence_report`: version=2, request_id UUID, date, work_id, key {kind:primeline,person_id,date,work_id}, reason opcional; somente hoje/ontem e equipa permanente autorizada.
Não aceita escolha remuneratória. Cria `falta_reportada_pendente/ausente_pendente`.
`absence_classify`: id, expected_type, expected_state, classification e reason obrigatório; três classificações existentes, somente Admin/Gestão.
Preview sem escrita; token SHA-256 inclui ator/empresa/payload/antes/depois. Confirmar o token de outro ator é recusado. Ledger/história na transação; sem horas, saída ou transferência de equipa.

### Conferência mensal

RPC `fn_folha_conferencia_v3(p_acao text,p_dados jsonb,p_confirmar boolean,p_versao text)`.
Ações: `conferir`, `devolver`, `validar`.
Payload: version=3, request_id UUID, person_id, month primeiro dia, expected_revision; reason e records [{id,revision}] quando necessário.
Somente Admin/Gestão; interno/tenant; sem âmbito artificial por obra.
Estados: `conferida`, `devolvida`, `validada_para_integracao`, `requer_revalidacao`.
Referências congeladas por dia, não captura dias futuros; desconhecido permanece NULL/pendente. Referência administrativa corrigida explicitamente invalida/reavalia.
Validar exige mês terminado, fonte atual e nenhuma pendência/pedido de correção. HE reconhecida HR-27 é informativa. Mudanças de factos invalidam validação e preservam a prova anterior/autor/histórico. Não cria folha_he, vencimento, pagamento ou custo.

## Contratos ainda preparados: próxima implementação segura

### Registo numa obra de destino

Nova RPC dedicada, não remapear obra nem tomar acesso total ao dia:
- chave do destino autorizado; revisão desse registo e da avaliação diária;
- lock trabalhador/data e lock de ordem compatível com os existentes;
- leitura interna da jornada inteira para limites/sobreposição, sem expor factos privados de outras obras;
- guardar SOMENTE o destino pedido, preservando todos os outros;
- autorização do Encarregado de destino e trabalhador elegível do tenant, sem alterar permanência;
- personalizados NULL/personalizado; normais manha/tarde permanecem factuais;
- referência diária individual uma vez, com marcador server-side normal_individual quando necessário; fingerprint novo apenas para factos com essa marca, preservando dados antigos;
- preview ligado a ator/empresa e snapshot completo para detectar alterações concorrentes noutras obras;
- históricos e idempotência; externos permanecem fora da avaliação interna/RH;
- testes: origem inacessível preservada, destino permitido, sobreposição com obra oculta, stale do dia, Friday 5h/3h sem HE artificial, limites4/16, replay, actor spoof, sem transferência.

### Garantia/Outra

O domínio distingue obra ativa e referência livre com UUID. Para referência livre, preparar factos num destino tipado com identidade própria (não NULL Escritório), motivo/referência original imutável e associação administrativa separada, auditada e revisionada. A associação deve revalidar conferências/preview sem reescrever os factos originais. Pendência antes da associação bloqueia validação. Persistência desta extensão ainda NÃO foi implementada.

### Externos/Diretor/Excel

Confirmação por empresa+obra+fornecedor+competência, hash de IDs/revisões/intervalos, autor Diretor autorizado, data, revisão/request UUID, história protegida. Source_change invalida. Exportação exige confirmação atual sobre hash atual; workbook por fornecedor/obra, horas factuais, sem preço inventado, salários ou HE. O codec XLSX não estava disponível nos runtimes examinados; não foi certificado ficheiro Excel, nem houve fallback CSV. Esta é uma dependência técnica, não uma nova decisão funcional.

### Mapas e custos

O domínio distingue factos provisórios de revisões incluídas na conferência validada. Dados externos são uma série separada. Não soma ambas as versões de um facto nem importa custos de lancamentos_mao_obra.
O adaptador SQL/leitura autenticada dos mapas ainda não existe. O contrato de domínio é preparação testada, não prova de acesso/RLS.
Uma tarifa requer prova RH aprovada, identidade/revisão, vigência e autor/data. O campo valor_hora isolado não a demonstra. Sem prova, apresentar horas.

## Bloqueadores funcionais reais e pendências técnicas

1. Visual: aprovação dos modelos atualizados antes de montar a UI (instrução expressa).
2. Custo em dia com excedente/multiobra: HR-27 proíbe valorizar HE; a regra ainda não define quais minutos por obra compõem a base ordinária quando existe excedente. Não escolher arbitrariamente uma obra nem ratear. Até decisão, `base_valorizacao_excedente_por_definir`, horas apenas.
3. Garantia em obra encerrada: confirmar elegibilidade do destino encerrado antes de relaxar regra atual em_curso. Outra com obra ativa já está definida.
4. Engenharia por concluir, NÃO confundir com bloqueador funcional: writer destino-only, normal com jornada individual, persistência/associação de refs livres, confirmação externa/Excel, tarifa aprovada e adapters de mapas. As propostas acima permitem continuar sem reabrir regras já aprovadas.

## Testes e limitações de evidência

- PostgreSQL nativo **17.6**, clusters efémeros, duas ligações independentes: **233 PASS, 0 FAIL, 0 SKIP**. A cadeia inclui 195 testes antecedentes e 38 testes acrescentados; os testes da regra antiga executam antes da alteração HR-27, novos testes depois.
- Unit/static/cliente/domínio/mapas/session regressions: **79 PASS, 0 FAIL, 0 SKIP**.
- Total testes Node aprovados: **312**; apresentar separadamente **31 estados visuais + 3 suítes de interação/offline**, não somar screenshots como testes Node.
- Navegador Edge headless, perfis/contextos isolados, dados sintéticos; sem sessão Chrome real. 1440×1000,1024×768,768×1024, controlos>=44px, sem overflow; personalizado retrato <850px no contentor de intervalos. Sem erros JS.
- `git diff --check`: PASS.
- Ajuste único de teste existente: ausência de `dia_especial_pendente` agora confrontada com `special_day && !special_reviewed_at` do facto, evitando depender do dia da semana em que o teste corre. Não altera código funcional existente.
- Bootstrap sintético usa identidade claim substituta, não prova JWT real/PostgREST/RLS em produção. Relações financeiras de conflito são mínimas; não é auditoria completa do Financeiro.
- O capture antigo tinha EXECUTE legado aberto; a fixture local fecha-o explicitamente antes do precheck. Acesso negado real sob authenticated é testado; NÃO se afirma que produção foi verificada/alterada.
- A conferência mensal tem fixture positiva de mês anterior com documentação sintética de referência administrativa por dia e folga legítima; não se inferiu horário atual como prova histórica.
- Não houve regressão executada do novo Excel: ausente, não contado como PASS.

## Próxima etapa

Revisão adversarial LOCAL destes quatro packages, enquanto se aprova o ZIP visual. Continuar writer operacional destino-only/normal_individual e refs livres em cadeia local, com testes antes de montar UI. Depois confirmação externa/Excel e adapters dos mapas. Nenhum package deve ser instalado em produção nesta etapa.

**Estado:** preparação local substantiva, com quatro packages e contratos testados; a entrega operacional integrada completa ainda NÃO está pronta. GO para revisão local; NO-GO para instalação/publicação deste conjunto neste estado.

### Ficheiros SQL completos para revisão

| Package | Precheck | Backup | Migration | Post-check | Rollback |
|---|---|---|---|---|---|
| HR-27 | [precheck](../supabase/folha_hr27_precheck.sql) | [backup](../supabase/folha_hr27_backup.sql) | [migration](../supabase/folha_hr27.sql) | [post-check](../supabase/folha_hr27_postcheck.sql) | [rollback](../supabase/folha_hr27_rollback.sql) |
| Faltou | [precheck](../supabase/folha_faltou_neutro_precheck.sql) | [backup](../supabase/folha_faltou_neutro_backup.sql) | [migration](../supabase/folha_faltou_neutro.sql) | [post-check](../supabase/folha_faltou_neutro_postcheck.sql) | [rollback](../supabase/folha_faltou_neutro_rollback.sql) |
| Leitores | [precheck](../supabase/folha_horas_leituras_precheck.sql) | [backup](../supabase/folha_horas_leituras_backup.sql) | [migration](../supabase/folha_horas_leituras.sql) | [post-check](../supabase/folha_horas_leituras_postcheck.sql) | [rollback](../supabase/folha_horas_leituras_rollback.sql) |
| Conferência mensal | [precheck](../supabase/folha_conferencia_mensal_precheck.sql) | [backup](../supabase/folha_conferencia_mensal_backup.sql) | [migration](../supabase/folha_conferencia_mensal.sql) | [post-check](../supabase/folha_conferencia_mensal_postcheck.sql) | [rollback](../supabase/folha_conferencia_mensal_rollback.sql) |
