# Revisão dos painéis administrativos — 14/10/2026

Branch: feat/gestao-horas-integrada-20261013.
Checkpoint preservado: 384f9af6ef0bb2dd2b0fe0942f727c530f3ed69f.
Alterações desta revisão ainda locais, sem novo commit. Não montar definitivamente os painéis.

## Correções e evidência

A fixture antiga limpava snapshot.pending mas conservava uma falta neutra pendente. Não era prova de um caso válido. A fixture agora classifica efetivamente a ausência ao mostrar zero pendências. Um cenário adversarial mantém pending=[] e a falta pendente: a validação continua bloqueada.

O painel calcula a união das pendências declaradas com as verificáveis nos factos: faltas pendentes, HE não decidida, intervalos abertos, referência desconhecida, falta de horas sem ausência classificada, conflito horas/ausência e pedidos de correção. Razões desconhecidas obrigatórias não são descartadas. HE reconhecida HR-27 e valorização HR-31 não bloqueiam por si só. O backend continua como autoridade final; nenhum SQL ou regra backend foi alterado.

A classificação começa em Selecionar classificação. Ausência de escolha ou permissão é recusada antes de chamar a RPC. Remuneração continua decisão administrativa explícita, nunca do Encarregado.

Revisão usa conference.revision (0 quando não existe conferência). Pendências e estados são apresentados em português; controlos têm rótulos e dados de calendário são dd/mm/aaaa. Timestamps usam Europe/Lisbon e relógios factuais permanecem HH:mm. Durações continuam 8h, 7h30 e 30min.

Externos: versão atual confirmada distingue-se de versão atual por confirmar e última confirmação. Motivo obrigatório nas retificações antes do preview. História mostra todas as confirmações devolvidas pelo backend, revisão, autor/data/motivo. Exportação requer confirmação atual, leitura fresca e mesma revisão/fingerprint da consulta; corrida concorrente bloqueia a exportação. XLSX real, sem CSV.

Identidade: folhas existentes styles.css e visual-identity-final.css carregadas no modelo; painel usa tokens de cartão, texto, linha e ação da Primeline. Nenhuma alteração nesses estilos globais. Fontes externas são bloqueadas no teste offline, com fallback de fonte.

## Testes

98 testes unitários/estáticos: PASS, 0 FAIL, 0 SKIP (93 preservados + 5 novos).
Suíte desktop RH/externos/mapa: PASS, 0 erros JS, sem overflow.
Inclui ausência de pré-seleção, zero pendências contraditório, decisão administrativa explícita, HE reconhecida, HR-31, motivo, XLSX real, revisão concorrente, cancel/stale e perfis sem capacidade de escrita.
Os 282 testes PostgreSQL anteriores continuam preservados no checkpoint; não foram repetidos porque nenhum SQL/backend mudou nesta revisão. Não apresentar essa execução histórica como nova execução.

As cinco capturas novas usam dados sintéticos e perfis simulados. Não houve validação real autenticada. Chrome DevTools MCP não está disponível nas ferramentas desta sessão. É necessário um mecanismo de acesso à sessão autenticada e contexto autorizado para certificar esse ponto; não usar mocks como prova de autorização real.

ZIP: C:/Users/Cristiana/.codex/visualizations/2026/09/29/01a0ec35-6391-74e1-adf3-642847f49889/primeline-horas-paineis-revistos-20261014.zip.

## Preparação local — associação Garantia/Outra

Leitor existente: fn_folha_referencias_contexto_v3(data,obra_id), com UUIDs e âmbito de empresa/obra. O DTO atual não expõe capacidade de associação; antes da montagem, resolver essa capacidade pelo contrato autenticado, sem inferir autorização pelo nome/email. O writer já exige Administrativo/Gestão para associate_reference.

Formulário proposto: pessoa/data, tipo, referência original, obra original e horários SOMENTE LEITURA; obra de associação escolhida explicitamente dentre destinos da mesma empresa autorizados; motivo obrigatório. Associação é separada da identidade original, inclusive obra encerrada; não transformar a referência original em ponto de outra obra.

Chamada existente: executeReference(action=associate_reference, data={id,person_id,kind,date,work_id,associate_work_id,expected_revision,expected_daily_revision,reason}). Obter revisão diária fresca pelo leitor do dia, preservar revisão do registo e novo request_id por operação; preview/confirmação, nunca retry automático. O backend mantém histórico e invalida/reconcilia avaliações/conferências. Nenhuma associação real feita.

Testes futuros da interface: Admin/Gestão versus consulta; mesma empresa; alvo autorizado; original imutável; revisão antiga; conflito com alteração simultânea; cancelamento; resultado não committed; histórico; conferência/relatório invalidado conforme fonte. Não reescrever regras existentes.

## Preparação local — aprovação da tarifa RH

Leitor existente: fn_folha_custo_hora_contexto_v3(colaborador_id), com versions/history, expected_revision incluindo versão futura e can_approve. Gerência consulta; Administrativo/Gestão aprova conforme o backend. Colaborador identificado exclusivamente por UUID.

Formulário proposto: trabalhador e versões anteriores em consulta; custo/hora EUR explicitamente preenchido, data efetiva explícita, documento/referência de prova RH e motivo. Não preencher com valor_hora, salário/cargo ou horas realizadas. Mostrar intervalo de vigência proposto e alteração antes de confirmar.

Chamada existente: approveHourlyCost({personId,effectiveFrom,expectedRevision,hourlyCost,evidence,reason}). Não escolher uma obra: tarifa pertence ao trabalhador e vigência. História/autor/revisão preservados. Não recalcular salários, HE, pagamentos nem alterar factos/conferência por valorização HR-31 pendente. UI destas duas operações ainda não montada; preparação nesta sessão é desenho baseado nos contratos existentes.

## Estado final

Checkpoint intacto. Alterados apenas painel preparado, CSS próprio e testes/modelos, além desta documentação. app.js/index.html, editor/equipa montados e SQLs permanecem iguais ao checkpoint. Nenhuma mudança de HR-27/HR-30/HR-31. Sem SQL real, push, merge ou deploy.

Próximo passo: revisão das cinco capturas e aprovação separada; depois montagem autorizada e validação da sessão real, mantendo a autoridade das permissões backend.
