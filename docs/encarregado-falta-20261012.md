# Botão Falta contextual — implementação local — 12/10/2026

Branch: `fix/encarregado-falta-20261012`. Base: `1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0`.

## Regra e implementação

Botão secundário FALTA junto de REGISTAR/EDITAR, formulário dentro do cartão, um painel aberto de cada vez. Opções JUSTIFICADA/INJUSTIFICADA com altura mínima 44px. Não aparece para externos, próprio Encarregado, apoio temporário ou datas fora de hoje/ontem.

RPC nova isolada: `fn_folha_falta_v2(text,jsonb,boolean,text)`, seguindo preview/confirmação V2. Ação `absence_report` apenas para perfil Encarregado ativo, obra autorizada, colaborador ativo da mesma empresa e permanência válida na equipa. Não altera equipa/permanência ou horas. Qualquer Folha, ponto legado, lançamento de mão de obra ou horas extra no mesmo dia bloqueia. Ausência existente também bloqueia. Depois da gravação, a Folha recarrega; o Dia Normal existente exclui a pessoa pelo campo absence.

JUSTIFICADA: `tipo=falta_justificada_pendente`, `estado=ausente_pendente`. É neutra: não decide remuneração. As constraints existentes são preservadas e ampliadas apenas para esta combinação. O normalizador existente continua em uso.

INJUSTIFICADA: `tipo=falta_injustificada`, `estado=ausente_pendente`, segundo o fluxo existente. A interface mostra FALTA INJUSTIFICADA; a validação administrativa existente é preservada.

Na confirmação administrativa da própria Folha, o tipo neutro exige classificação explícita com/sem remuneração e motivo. A ação `absence_classify` usa a mesma RPC isolada e exige `folha_privado.adm()`. Não permite transformar o tipo neutro apenas num estado confirmado sem classificação. Com remuneração passa a confirmada; sem remuneração passa a justificada, respeitando o modelo anterior. Não foi alterado qualquer cálculo salarial.

Locks: mesmo lock global e lock por pessoa/data existentes. Idempotência reutiliza `folha_privado.operacoes`, com request_id por operação; payload diferente recusa. Preview token depende dos dados atuais; confirmação stale recusa. Auditoria existente de ausencias permanece e acrescenta-se histórico factual em folha_historico. Não cria tabela operacional nova nem abre grants/policies de ausencias. Writer legado permanece CLOSED.

## Scripts propostos, NÃO aplicados

1. `supabase/folha_falta_v2_precheck.sql` — leitura de catálogo; rever condições e drift antes de autorizar.
2. `supabase/folha_falta_v2_backup.sql` — cópia privada de ausências, constraints, policies e grants. Exige autorização separada.
3. `supabase/folha_falta_v2.sql` — migration transacional mínima.
4. `supabase/folha_falta_v2_postcheck.sql` — compara dados, policies/grants e verifica writer legado.
5. `supabase/folha_falta_v2_rollback.sql` — restaura constraints do backup; recusa se existirem ocorrências neutras pendentes; preserva histórico/backups.

Precheck operacional obrigatório antes de rollout: confirmar schema instalado, presença dos helpers, nomes novos livres, campos data/colaborador das quatro fontes de horas, gatilhos de auditoria/reconciliação, constraints e grants. O SQL local não certifica produção. Nunca publicar frontend antes de instalar/validar backend com autorização expressa. Não executar automaticamente rollback ou limpeza de ocorrências.

## Testes locais

- `node --test tests/attendance-absence.test.mjs`: 15 testes PASS, PGlite instalado em pasta temporária externa; fixture sintética com constraints, normalizador e auditoria capturados; helpers de contexto/autorizações sintetizados. Não é teste da BD real nem de duas ligações concorrentes.
- `node --test tests/attendance-domain.test.mjs tests/attendance-v2-static.test.mjs tests/absences-workflow.test.mjs`: 31 PASS.
- `node tests/attendance-absence-browser.mjs`: 75 cenários PASS, incluindo regressão do runner original, tablet 768x1024, 1024x768 e mobile 390x844; zero pageErrors. Backend simulado, sem credenciais reais.
- Parse JavaScript: PASS; git diff --check: PASS.

Cobertura: neutra/injustificada, cancelar sem RPC, preview sem gravação, hoje/ontem, datas antiga/futura recusadas, externo e obra/pessoa sem autorização, ponto/horas bloqueados e intactos, permanência intacta, exclusão do Dia Normal, idempotência, auditoria, classificações administrativas com/sem remuneração, retorno estrutural e writer legado CLOSED. REGISTAR/EDITAR continuam passando no navegador.

Capturas finais locais: pasta temporária `primeline-falta-v2-synthetic`, `falta-768x1024.png` e `falta-1024x768.png`. Dados inteiramente sintéticos; nenhum screenshot de produção.

## Estado de entrega

Implementado/testado LOCALMENTE. Nenhum SQL na BD real, deploy, push ou merge. Main e restantes módulos mantidos; modificações limitadas à Folha, respetivo cliente/classificação administrativa, estilos, cache-busting e scripts/testes deste reporte.

Antes da publicação: autorização separada para precheck real, backup/migration/postcheck e rollout do frontend; smoke autenticado sem factos fictícios. NÃO declarar funcionamento em produção antes dessas etapas.
