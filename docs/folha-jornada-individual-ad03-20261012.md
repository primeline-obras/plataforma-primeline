# AD-03 — Jornadas individuais de referência
Data: 12/10/2026. Preparação local; interface definitiva sujeita a aprovação visual.

## Base e isolamento
- Base: fix/folha-horarios-coerencia-20261012 — 31695cf75bb7dc03967fc654567db2956bcd9c0c.
- Branch de entrega: feat/folha-jornada-individual-ad03-20261012.
- A base contém AD-15 e AD-14. Os ficheiros das três correções anteriores permanecem inalterados.
- Nenhum ficheiro de src/ ou index.html foi alterado. Não houve SQL real, ativação real, dados reais, push, main, merge ou deploy.
- Instalações, atribuições e ativações das fixtures de teste ocorreram exclusivamente em PostgreSQL descartável, com pessoas e empresas sintéticas.

## Diagnóstico e separação dos dois contratos
A referência automática anterior dependia de uma permanência operacional única e de uma versão de horário da obra. O caso anterior foi reproduzido: técnico sem permanência => referência pendente e esperado NULL.
Responsabilidade por obra, perfil de login, cargo RH, local visitado e carga de escritório não são utilizados para inventar a referência individual.

A jornada individual serve à avaliação. Os valores iniciais editáveis do formulário de ponto são outro contrato. Nenhuma edição de um lançamento altera uma jornada individual.

### Horários sugeridos — verificação do frontend atual
| Comportamento pedido | Estado observado no código V2 |
|---|---|
| Dia Normal 08–12 / 13–17 | A ação coletiva usa context.schedule, o horário da obra. Coincide com esses valores quando a obra tem essa configuração; não constitui sugestão fixa independente da configuração |
| Manhã 08–12 / Tarde 13–17 | normalIntervals seleciona os períodos configurados; não existem atalhos individuais visíveis Manhã/Tarde no editor atual |
| Registo novo já preenchido com sugestões editáveis | Lacuna: openEditor em attendance-sheet.js inicia os campos vazios quando não existe lançamento |
| Editar os horários reais | Disponível no editor contextual; persiste factos por periods_save (internos) ou save (externos) |
| Editar lançamento sem alterar configuração habitual | Preservado; esses writers não configuram jornadas |
| Externos separados de salário/HE internos | Preservado; AD-03 não lhes atribui referência de colaborador nem altera o contrato externo |

attendance.js contém defaults antigos, mas isso não prova o comportamento do editor V2 usado pela Folha. A análise acima usa attendance-sheet.js e attendance-domain.js.
Implementação necessária para completar o esclarecimento: valores iniciais fixos editáveis no registo novo e seleção explícita Dia Normal/Manhã/Tarde, mantendo confirmação, validação factual, cancelamento, locais por período e contrato externo. Não importar a jornada técnica 09–13/14–18 para esses atalhos.
Essa implementação não foi acrescentada silenciosamente ao AD-03. A decisão de integrar esses atalhos deve ser explícita; o frontend atual foi preservado.

## Backend preparado
### A — Jornada habitual individual
- Nova public.folha_jornadas_individuais_versoes: empresa, colaborador, modelo, semana, revisão, vigência [desde,até), autor, timestamp, request_id, motivo e evidência.
- Semana com sete dias explícitos: prevista, folga ou desconhecida.
- Operacional: segunda–sexta 08–12/13–17, 480 minutos; sábado/domingo folga, 0 minutos.
- Técnica: segunda–quinta 09–13/14–18; sexta 08–13/14–17; 480 minutos; sábado/domingo folga, 0 minutos.
- Personalizado: distribuição documentada, incluindo jornada reduzida ou referência desconhecida.
- SQL NULL e JSON null não se confundem: desconhecida usa esperado JSON null e intervalos vazios; folga usa zero e intervalos vazios.
- Modelos identificados operacional/técnica devem corresponder à sua semana; uma adaptação utiliza personalizado.
- Sem atribuição automática na migration. A primeira atribuição usa o corte de ativação já autorizado; antes desse corte não há inferência por cargo.
- Fonte individual confirmada tem prioridade para uma nova avaliação. Uma jornada individual desconhecida não herda escritório/obra.
- Pessoas sem fonte individual preservam a resolução operacional existente.
- Uma avaliação já congelada conserva a origem/snapshot anterior mesmo depois de uma atribuição individual inicial.

### RPC e permissões
public.fn_folha_jornadas_v2(text,jsonb,boolean,text):
- propose: Administrativo/Gestão; lista ativos do tenant, sugere modelos por correspondências explícitas, exige revisão do cargo e identifica jornadas já aprovadas.
- assign: Administrativo/Gestão; lote de até 500 pessoas; valida todos os alvos antes do replay; preview com nome, cargo, semana, vigência e revisão; confirmação atómica com token; histórico e idempotência.
- read: Administrativo/Gestão/Gerência no tenant; Encarregado/Diretor/Adjunto/Preparador apenas a própria ligação RH.
- Gerência não altera jornadas ou referências excecionais.
- empresa do ator é a autoridade; empresa/work_id enviados pelo cliente não ampliam âmbito.
- Tabela com RLS e sem grants diretos para roles da aplicação; acesso funcional por RPC. Helpers privados sem EXECUTE externo.
- Versionamento serializado com o lock operacional existente; revisão/token recusam previews antigos.
- Cargo desconhecido/ambíguo não recebe atribuição automática. O Administrativo pode escolher e confirmar explicitamente o modelo apropriado.
- Autor histórico inativo continua no trilho; uma Gestão ativa pode criar uma versão futura. Ator inativo não escreve.

### C — Referência excecional diária
Reutiliza daily_reference_correct, com evidência, motivo, preview, revisão, auditoria e tenant.
Pode confirmar jornada prevista ou folga conhecida. A correção limpa os resultados anteriores da avaliação antes do recálculo atómico e regista invalidação de decisões HE existentes.
Não modifica horas, destinos ou a jornada habitual. Mantém a proteção de competência fechada.
Esta ação atua numa avaliação diária ativa existente; não foi introduzida uma agenda de exceções futuras sem factos/avaliação.

### Avaliação, fecho e regressões preservadas
- Avaliação única por empresa+colaborador+data; realizado soma destinos sem duplicar esperado.
- Individual capturada guarda FK para a versão e snapshot do dia, evidência e identificação do modelo/revisão.
- Referência desconhecida conserva falta/excedente NULL e HE não avaliável; fecho bloqueado.
- Folga não se confunde com desconhecida: esperado 0; ausência de factos não cria falta.
- Trabalho fora da jornada não gera HE monetária. Excedente mantém decisão e gates existentes.
- Dias exclusivamente normais e factos existentes não foram convertidos.
- elegivel_equipa(), permissões de equipa, jornadas de obra, cargos e ligações RH não foram ampliados.
- Alternativa de obra principal em standby: não implementada.
- Nenhum cálculo salarial alterado.

## SQL completo e dependências
Os cinco ficheiros novos são completos, commitados com a entrega:
1. supabase/folha_jornada_ad03_precheck.sql — READ ONLY, AD03_PRECHECK_OK.
2. supabase/folha_jornada_ad03_backup.sql — backup privado de funções/constraints/dados/ledger, AD03_BACKUP_OK.
3. supabase/folha_jornada_ad03.sql — instalação transacional sem atribuições/ativação, AD03_MIGRATION_OK.
4. supabase/folha_jornada_ad03_postcheck.sql — READ ONLY, AD03_POSTCHECK_OK.
5. supabase/folha_jornada_ad03_rollback.sql — AD03_ROLLBACK_OK somente quando seguro; nunca automático.

Dependência: Folha diária preparada + AD-15 → AD-14 → AD-13 → AD-03. O precheck exige a baseline local anterior exata; estes scripts não podem ser tratados como instalação isolada sobre a produção atual.
O backup não é sobrescrito. Reinstalação após rollback local foi testada reutilizando o backup intacto.
Migration/postcheck verificam dados preservados, descontando somente a nova coluna nula jornada_versao_id nas avaliações anteriores.
Rollback após utilização ou drift aborta e conserva o trilho, sem apagar dados usados.
Os scripts exigem owner, hashes normalizados dos corpos, metadados, ACLs e constraints; instalação parcial/drift não é reparada automaticamente.
tests/attendance-jornada-ad03-package.mjs gera os ficheiros a partir dos fontes AD anteriores e do core local. O SQL entregue não depende de executar o gerador em produção.

## Testes e provas
| Conjunto | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| PostgreSQL 17.6: matriz diária + AD-15/14/13 + AD-03 | 195 | 0 | 0 |
| Domínio, contratos estáticos, sessão e cadastro RH | 64 | 0 | 1 |
| Total das suites automatizadas | 259 | 0 | 1 |

SKIP: caso de reimportação do ficheiro RH real de 47 linhas, dependente de RH_XLSX, não disponibilizado. Não corresponde a uma verificação AD-03.
Além disso: 24 estados/viewport visuais PASS, 3 capturas adicionais da semana técnica; seleção de modelo, preview e consulta própria verificados nos três tamanhos. Sem overflow horizontal ou erros JavaScript.
Provas adicionais:
- original sem permanência vs referência individual atribuída;
- técnico multiobra 2h+6h => realizado 480 e esperado 480 uma só vez;
- dia misto, horas em falta e edição preservam referência/versões;
- desconhecida permite trabalho e bloqueia fecho sem diferenças fictícias;
- exceção diária e folga preservam factos, sem HE monetária;
- próprio Encarregado com RH único, sem permanência fictícia;
- lote com alvo já aprovado ou de outra empresa aborta integralmente;
- concorrência entre atribuição e preview de ponto: preview aguarda lock e o anterior fica stale;
- replay igual e payload diferente; referências históricas/futuras;
- recusas AD-14 e AD-15 repetidas após AD-03;
- drift de ACL, SECURITY DEFINER, trigger e backup privado recusado pelo postcheck;
- precheck/backup/migration/postcheck/rollback/reinstalação PASS local.

O teste estático antigo recebeu somente normalização BOM/CRLF no leitor. As suas assertions não foram relaxadas; isto remove um falso negativo específico do checkout Windows.

## Proposta visual — gate obrigatório
- docs/prototipos/folha-jornada-ad03.html: oito estados navegáveis, dados sintéticos, sem backend.
- docs/prototipos/folha-jornada-ad03-capturas.html: galeria.
- docs/prototipos/ad03-capturas/: 27 PNGs + resultado.json.
- Desktop 1440×1000; tablet 1024×768; tablet 768×1024.
- Cadastro, modelos, semana, lote protegido, edição individual, exceção diária, pendência e consulta própria.
- Campos da primeira vigência apresentados como corte autorizado; cancelamento/preview são simulações.
- Inspeção visual feita sobre as capturas das telas obrigatórias; proporção corrigida no protótipo, sem alteração da aplicação.

A interface administrativa definitiva e a consulta integrada no frontend aguardam APROVAÇÃO VISUAL EXPLÍCITA.

## Reproduzir localmente
Definir QUADRO_PG_BIN (binários PostgreSQL 17), QUADRO_TEST_DEPS (node_modules com pg), RH_TEST_DEPS (tests/runtime) e, se necessário, PLANNING_PLAYWRIGHT. O teste visual usa Microsoft Edge headless instalado.
- node tests/attendance-jornada-ad03-package.mjs
- node tests/attendance-jornada-ad03.test.mjs
- node --test tests/attendance-domain.test.mjs tests/attendance-daily-static.test.mjs tests/attendance-v2-static.test.mjs tests/session-boundary.test.mjs tests/session-isolation.test.mjs tests/rh-cadastro.test.mjs
- node tests/attendance-jornada-ad03-visual.mjs
- node tests/attendance-jornada-ad03-preview.mjs (servidor apenas local, conteúdo do protótipo/CSS/capturas)

## Estado e limitações
BACKEND AD-03 PREPARADO E TESTADO LOCALMENTE.
PROPOSTA VISUAL PRONTA PARA APROVAÇÃO.
Frontend definitivo não integrado; não declarar rollout pronto.
Sem catálogo ou UAT real nesta tarefa. Ninguém recebeu jornada por uma escrita real.
A primeira atribuição segue o corte aprovado; colaboradores admitidos depois desse corte não recebem automaticamente uma jornada anterior à admissão.
Exceções administrativas reutilizam avaliações ativas. Jornadas futuras são versionadas; referências anteriores não são recapturadas.
Mão de obra externa fica fora do modelo interno de avaliação/HE/vencimentos.
Lacunas de preenchimento automático identificadas separadamente; nenhuma correção funcional desses atalhos foi efetuada.
Trabalho preservado num commit local desta branch; sem push. Working tree verificado no encerramento.
