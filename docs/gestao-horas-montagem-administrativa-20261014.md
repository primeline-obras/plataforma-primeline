# Gestão Integrada de Horas — montagem administrativa local, 14/10/2026

## Checkpoint e limites

Branch `feat/gestao-horas-integrada-20261013`. Base preservada: `384f9af6ef0bb2dd2b0fe0942f727c530f3ed69f`.
Este relatório sucede aos relatórios de retoma e de revisão dos painéis. As contagens históricas destes documentos não substituem os resultados repetidos abaixo.
Nenhum SQL real, alteração de produção, push, merge ou deploy foi realizado. O commit desta entrega é exclusivamente local; o SHA encontra-se no HEAD do checkpoint.

## Matriz única de implementação desta etapa

| Fluxo | Estado local | Entrada e autorização |
|---|---|---|
| Editor e equipa operacional | Preservados e regredidos | Equipa → Folha de Ponto; cartões e Dia Normal |
| Conferência mensal RH | Montada | Folha de Ponto → Gestão Integrada de Horas → Conferência RH; colaborador UUID/competência |
| FALTOU/classificação | Montada no mês e no mapa de Ausências | Classificação explícita, motivo, capacidade administrativa do DTO |
| HE diária HR-27 | Montada, informativa | Reconhecimento/não consideração administrativa; sem folha_he, pagamento ou bloqueio próprio |
| Externos/Excel HR-30 | Montado | Obra/fornecedor UUID; revisão atual confirmada, motivo de retificação, histórico |
| Horas/estimativa HR-31 | Montado | Horas da Obra; tarifa vigente aprovada; custo pendente continua NULL |
| Associação Garantia/Outra | Preparada, NÃO montada | Modelo separado para aprovação; referência, horários, autor/revisão/histórico preservados |
| Aprovação tarifa RH | Preparada, NÃO montada | Modelo separado para aprovação; valor/vigência/evidência/motivo explícitos |
| Produção/auth real | Não validada nesta etapa | MCP Chrome não disponível na sessão; testes de navegador offline e JWTs sintéticos locais |

Os seletores recebem UUIDs e capacidades do backend; não existe correspondência por nome/email. O responsável autenticado continua sujeito às autorizações transacionais dos escritores existentes. Não foi substituído o writer por PATCH/INSERT browser ou por payroll_validate.
Os painéis não inventam estado local de sucesso. Cancelamento, erros e revisões desatualizadas preservam o contexto; não há repetição automática. Os controlos de contexto ficam indisponíveis durante decisões administrativas.

## Pendências e história funcional

A validação mensal considera pendências reais do snapshot e faltas neutras, intervalos abertos, referência desconhecida, conflito falta/horas, horas em falta e pedidos de correção. FALTOU não pode coexistir com zero pendências obrigatórias. A classificação começa vazia.
HR-31 pendente e HE reconhecida HR-27 não bloqueiam por si só a conferência factual. Nenhuma decisão HR-27/30/31 foi modificada.
O leitor mensal passa a reunir histórias já persistidas de conferência, factos/faltas, decisões diárias e referências. Não é criado histórico no browser. Autores, data/hora portuguesa, motivos e revisões disponíveis são exibidos; não existe `revisão undefined`.
Uma confirmação externa atual não oferece reconfirmação redundante. A exportação reconsulta autorização/revisão/fingerprint; revisão diferente exige recarregar, não exportar a versão antiga. As versões anteriores permanecem no backend.

## FALTOU → Equipa → Ausências

O writer neutro local já existente insere uma única linha em `public.ausencias`, tipo `falta_reportada_pendente`, estado `ausente_pendente`. A classificação controlada atualiza essa mesma linha pelo UUID original. O mapa não cria outra ocorrência/tabela.
O novo leitor readonly do mapa associa o evento `absence_report` pelo UUID gravado no histórico. Assim conserva obra de origem, autor e data, mesmo após classificação administrativa. Nomes históricos são resolvidos pelo UUID; pessoas inativas não são reinseridas na equipa ou nos candidatos.
No mapa, a linha neutra perde os antigos botões/formulários genéricos de PATCH; apresenta a classificação controlada apenas quando `can_classify` é verdadeiro. Sem backend/capacidade, a ocorrência continua visível sem writer alternativo. As ausências comuns mantêm os fluxos anteriores.
A ligação foi provada em PostgreSQL descartável: reporte → consulta do mapa → classificação → consulta do mesmo UUID; uma ocorrência, origem intacta, histórias de reporte/classificação presentes. Isso prova o pacote local, não a instalação real do Supabase.

## Permissões e privacidade

| Perfil | Comportamento verificado |
|---|---|
| Administrativo/Gestão | Contexto RH e ações autorizadas; classificação controlada |
| Gerência | Consulta administrativa; sem escrita RH operacional |
| Diretor responsável | Consulta de obra; confirmação externa conforme capacidade própria; sem tarifa/remuneração individual |
| Adjunto responsável | Consulta de obra, sem aprovação mensal/externa; estimativas monetárias mascaradas |
| Preparador | Helper atual `folha_privado.obra` recusa os leitores de obra testados; mantida a recusa, sem ampliar permissões |
| Encarregado | Fluxo operacional preservado; nova revisão administrativa recusada |

Se for necessário liberar estes leitores ao Preparador, esse ponto requer revisão explícita de autorização. Não foi aproximado usando outro perfil ou writer. Obra fora de responsabilidade/empresa é recusada. As estimativas pessoais continuam mascaradas para leitores operacionais.

## SQL completo local e ciclo de aplicação

Só o último pacote de leitores foi ampliado. São dois novos leitores SECURITY DEFINER STABLE readonly, metadados de navegação e mapa de Ausências, e duas substituições readonly: história mensal e contexto/história/capacidade de referências.
Não foram alterados os writers aprovados, as regras de salários, a unidade minutos, os limites 4/16, os horários personalizados ou as permanências.

- [Precheck completo](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_precheck.sql)
- [Backup privado completo](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_backup.sql)
- [Migration completa](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos.sql)
- [Postcheck completo](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_postcheck.sql)
- [Rollback completo](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_rollback.sql)

Estes ficheiros contêm as definições completas, grants e guardas de deriva. O backup inclui os leitores originais e o rollback restaura-os. O ciclo precheck/backup/install/postcheck/rollback/reinstall foi executado apenas em PostgreSQL local.
A ordem global dos dez pacotes e os restantes SQLs completos estão no relatório de retoma preservado. Nada deve ser aplicado automaticamente: primeiro preflight real autorizado, depois revisão de dependências/hash e autorização separada por estágio.
O postcheck de igualdade da fotografia é imediato à instalação, antes do uso funcional; alterações legítimas posteriores no ledger produzem ADDON_DATA_DRIFT. O teste negativo continua recusando essa deriva, seguido de rollback isolado.

## Testes repetidos nesta entrega

| Grupo | Resultado |
|---|---|
| PostgreSQL 17.6 integrado | 286/286; duas ligações independentes, AD-03/13/14/15, concorrência, idempotência, tenant, lifecycle/rollback, HR27/30/31, novos leitores/mapa/histórias |
| Unitários/contratos/sessões | 103/103; novos testes de mapa, seleção explícita e falha fechada incluídos |
| Medicina/Viaturas/Planeamento/RH/wrapper | 49 aprovados, 0 falhas, 3 skips RH por runtime específico não configurado |
| Navegador legado Folha | 57/57 cenários; 0 erros JS |
| Editor operacional | 3 suites: 768×1024, 1024×768, 390×844; gravação/recuperação, cancelamento, stale e permissões; 0 erros JS |
| Equipa operacional | 3 suites nos mesmos tamanhos, incluindo Folha integrada, data visual e chamadas factuais; 0 erros JS |
| Revisão desktop/montagem | 1 suite 1440×1000: RH/externos/mapa, histórico, validação, cancel/stale, Excel real, navegação e HR31; 0 erros JS |
| Novos modelos preparados | 1 suite desktop: referência intacta, obra encerrada, motivo, tarifa/vigência/evidência, histórico, stale e consulta; 0 erros JS |
| git diff --check | PASS |

Os três skips RH são: cadastro PostgreSQL específico, formulário preservando dados, aviso contratual na interface. Não são contados como aprovados. A importação Excel real de 47 colaboradores não foi exercitada neste grupo. O relatório externo Excel foi exercitado com SheetJS real e dados sintéticos, assinatura ZIP/XLSX e revisão r3.
Warnings de MODULE_TYPELESS_PACKAGE_JSON no Node são preexistentes; nenhum ficheiro package global foi alterado para os suprimir.
Na preparação houve duas falhas locais corrigidas: substituição do leitor existente devia usar CREATE OR REPLACE; os utilizadores sintéticos dos perfis precisam de email obrigatório. A suíte final passou sem ocultar erros ou deriva. A espera de data no browser foi ligada à chamada de equipa correta, pois metadados administrativos são outra leitura válida.

## Ficheiros desta etapa

Aplicação: `index.html`, `src/app.js`, `src/attendance-sheet.js`, `src/attendance-hours-client.js`, `src/attendance-hours-review.js`, `src/attendance-hours-review.css`, novos `src/attendance-hours-admin.js` e `src/attendance-hours-absence.js`.
SQL: os cinco ficheiros `supabase/folha_operacional_contextos*.sql` acima.
Geração/fixtures: `tests/attendance-operational-readers-package.mjs`, `tests/fixtures/attendance-operational-readers-core.sql`, `tests/fixtures/attendance-operational-readers-suite.txt`.
Testes: `tests/attendance-hours-review-browser.mjs`, `tests/attendance-hours-team-browser.mjs`, novos `tests/attendance-hours-review.test.mjs`, `tests/attendance-hours-admin.test.mjs`, `tests/attendance-hours-prepared-browser.mjs`.
Documentação: relatório de revisão dos painéis preservado e este relatório único de entrega.

## Modelos e próxima UAT

[ZIP dos dois novos modelos, seis capturas](C:/Users/Cristiana/.codex/visualizations/2026/09/29/01a0ec35-6391-74e1-adf3-642847f49889/primeline-horas-associacao-tarifa-20261014.zip).
As capturas só contêm dados sintéticos e estão fora do Git. Estes dois painéis NÃO estão montados na navegação; aguardam aprovação visual.
Os cinco painéis revistos aprovados estão montados localmente, dentro da Folha de Ponto. Férias, Horário e Gestão legada continuam disponíveis, sem serem usados como substituto da conferência integrada.

Próximo passo: rever o ZIP de associação/tarifa; depois testar em UAT autenticada, com cada perfil e com os contratos backend disponíveis num ambiente explicitamente autorizado. Rever os três skips RH e o limite Preparador. Só após isso preparar autorização de aplicação/publicação.
Estado final: montagem aprovada concluída LOCALMENTE; nenhum GO de produção. Restam a aprovação/montagem dos dois modelos novos, UAT real e preflight/rollout autorizados.
