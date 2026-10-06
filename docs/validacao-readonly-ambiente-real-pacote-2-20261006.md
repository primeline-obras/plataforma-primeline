# Validação READ ONLY do ambiente real — Pacote 2

## Evidência e limite

Candidato: `5e0feb3454243bdf11fe09292bd9e3db2d40e9b3`.
Auditoria preservada: `f1520ea307518a29b07c5f57284b9170b77061b3`.
Main de referência: `3df019a2f2813c0cbf7f36a8d13000431d33dd50`.

A aba existente do Chrome foi reutilizada. Dashboard autenticado confirmado:
Primeline-Obras, projeto `znttyadndpkxuekhjamd`, main PRODUCTION.
Não foi consultado o catálogo da BD. O MCP recusou o clique no SQL Editor
com `Element with uid 1_38 no longer exists on the page`, apesar de esse
elemento estar presente no snapshot. O acesso automatizado foi interrompido;
não se tentou API alternativa, extrair credenciais ou contornar a limitação.

**VALIDAÇÃO BLOQUEADA PELO AMBIENTE.** Nenhuma consulta real executada.
Não se conclui que a sessão expirou nem que o P1 está ativo por esta falha.

## Entrega manual

Ficheiro único: `supabase/pacote2_readonly_manual_20261006.sql`.

1. Na mesma aba, abrir manualmente o SQL Editor do projeto indicado.
2. Executar somente o BLOCO 1, de BEGIN até ao primeiro ROLLBACK.
3. Exportar a linha `readonly_catalog` completa como JSON/CSV local e anexar
   o resultado aqui. Não enviar tokens, passwords, URLs ou conteúdo de ficheiros.
4. Devolver também qualquer erro completo desse bloco. Se falhar, parar.
5. O BLOCO 2 contém integralmente o precheck já aprovado. Aguardar a revisão
   do resultado do bloco 1 antes de executá-lo separadamente. Devolver notices,
   status final ou exceção completa; se falhar, parar. Não alterar o SQL para passar.

O bloco 1 recolhe policies completas de metadata/Storage/anexos, bucket privado,
catálogo estrutural, ACLs/grants, funções com definições para fingerprints locais,
novos objetos esperados, candidatos a calendário e cinco contagens agregadas.
Não consulta linhas pessoais nem objetos binários. O count dinâmico é gerado
exclusivamente para cinco nomes fixos de tabelas public e só executa SELECT count(*).
Tudo está dentro de transação READ ONLY. O bloco 2 preserva os gates do precheck,
incluindo contexto de identidades somente para SELECT e configurações transacionais.

## Matriz de readiness

| Item | Estado real | Esperado / ação | Bloqueia? |
|---|---|---|---|
| Policy documentos | INCONCLUSIVE | Comparar todas as expressões com cec13e621af6cb299bcc23e0536a2a6531efa784 | Sim |
| Storage RH | INCONCLUSIVE | Bucket privado e guards em todos os caminhos OR | Sim |
| Catálogo base / funções / triggers / RLS | INCONCLUSIVE | Comparar estrutura e definições integrais | Sim |
| Ausências / legado / HE manual / alocações | INCONCLUSIVE | Devolver contagens sem pessoas e avaliar gates | Sim |
| Novos objetos V2 | Existência não consultada | Ausência pré-instalação será EXPECTED_ABSENT; lista exata no SQL | Sim até confirmar |
| Fingerprints | INCONCLUSIVE real | FINGERPRINT_UPDATE_REQUIRED_AFTER_DOCUMENT_HOTFIX, se hotfix documental for aplicado antes do precheck atual | Sim |
| Quadro / Fase B | RECHECK_AFTER_HOTFIX | Gate separado exige catálogo aprovado e backend/frontend validados; não executar | Sim para B |
| Calendário | INCONCLUSIVE | Inventariar fonte e depois comprovar completude/anos; não inventar feriados | Sim |
| Configuração futura | Proposta local, não instalada nem consultada | correction_days=1; calendar_complete/anos/datas após validação; HE monetária e exportadores desativados | Sim para ativação dependente |
| Despesas gerais bloqueadas | Não reconfirmado na BD | Rever definição real de fn_importar_mapa_financeiro_xlsx sem chamar writer | Sim até confirmar |
| Rollbacks | PASS local na auditoria preservada | Reconferir compatibilidade do catálogo real e ordem | Sim até confirmar |

## Sequência e decisão

**NO-GO para preparação final do rollout com base no ambiente real:** falta evidência
do catálogo. P1 documental real: **C. INCONCLUSIVO**, não confirmado nem excluído.
Não atribuir CALENDAR_READY ou CALENDAR_CONFIGURATION_REQUIRED sem consultar a fonte.

Única sequência recomendada agora: execução manual do bloco 1 → comparação local
das policies e catálogo → decisão sobre execução do precheck integral → readiness.
Se a policy vulnerável for confirmada, separar hotfix documental com PRECHECK →
BACKUP privado necessário → MIGRATION → POSTCHECK e ROLLBACK disponível, todos
do commit isolado cec13e621af6cb299bcc23e0536a2a6531efa784; depois nova validação
READ ONLY e revisão explícita dos fingerprints antes do Pacote 2.
Esse plano não autoriza executar nenhuma dessas alterações.

Nenhum produto, dado, perfil, main, deploy, migration real ou Fase B alterado.
