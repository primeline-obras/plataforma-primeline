# Auditoria final — Gestão Integrada de Horas

Data: 14/10/2026. **NO-GO para publicação do candidato completo.**

## Base e âmbito

- Repositório: `primeline-obras/plataforma-primeline`.
- Candidato auditado: `feat/gestao-horas-integrada-20261013`, SHA `2ae1f8a194f23d77bf0692d0a6d586566227298c`.
- Branch isolada de auditoria: `codex/audit-gestao-horas-integrada-20261014`, criada exatamente desse SHA.
- Só foram acrescentados testes, evidências sintéticas e este relatório. Nenhum ficheiro de produto, contrato, permissão, SQL de instalação ou regra funcional foi alterado.
- Nenhum acesso a produção, dado pessoal real, credencial de produção, SQL real, push, merge ou deploy. FP-28/FP-29 permanecem em standby.

Jordane esclareceu nesta auditoria que HR-29 autoriza Diretor, Adjunto e Preparador a consultar custos operacionais agregados das obras autorizadas, mas não tarifas individuais, salários ou evidências confidenciais RH. HR-38 é a avaliação pendente do risco de inferência; não existe limiar de trabalhadores, supressão ou janela temporal já aprovada.

## 1. Achados

### GI-01 — P1: inferência de tarifas RH através de agregados autorizados

**Confirmado localmente. Bloqueador de confidencialidade para publicação deste contrato.** Não exige acesso cruzado, privilégio novo ou consulta direta ao RH. Exige conhecer quem trabalhou e as horas efetivas, informação disponível no trabalho operacional e, para Diretor, no relatório factual autorizado. O ator consulta somente obras permitidas.

`fn_folha_custos_operacionais_contexto_v3(uuid,date)` protege empresa/obra/papel e remove os campos individuais. Contudo, publica somas monetárias exatas por dia, minutos e subtotais conhecidos. O cálculo privado deriva os custos das versões de tarifa RH aprovadas. A identidade `C = Σ(horas × tarifa)` permite recuperar incógnitas quando há informação suficiente.

Referências: `supabase/folha_operacional_contextos.sql`; implementação correspondente em `tests/fixtures/attendance-operational-readers-core.sql`; cálculo em `tests/fixtures/attendance-cost-map-core.sql`; DTO em `src/attendance-hours-client.js`. `individual_costs_included:false` descreve a estrutura da resposta; não garante impossibilidade de inferência.

| Cenário sintético comprovado | Respostas autorizadas | Resultado recuperado |
| --- | --- | --- |
| Uma pessoa, 8h | 159 €; 480 minutos | 159/8 = **19,875 €/h** |
| Dia 1: A+B, 8h cada; dia 2: só A, 8h | 400 €; 160 € | B = (400−160)/8 = **30 €/h** |
| Saída legítima de B da equipa; A mantém 8h | 464 € antes; 192 € depois | B = (464−192)/8 = **34 €/h** |
| Duas pessoas de 8h; só uma valorizada | Total NULL; subtotal conhecido 176 €; 1 grupo pendente | Se o participante valorizado for conhecido: **22 €/h** |
| Três obras autorizadas: AB, AC e BC, 4h por pessoa/obra | 132 €, 172 €, 212 € | Tarifas A/B/C = **11,5 / 21,5 / 31,5 €/h** |

No último cenário cada pessoa trabalha 8h ao todo e cada obra tem duas pessoas. A = (C_AB+C_AC−C_BC)/8; as outras tarifas seguem pelas equações equivalentes. Não há sobreposição de intervalos nem HE artificial. Um limiar de duas pessoas não protege contra composição de consultas.

O cenário de pessoa única foi executado independentemente nos três perfis técnicos. Os cenários de diferenças/composição foram executados como Diretor; os três perfis usam o mesmo leitor agregado. Não se declara uma execução independente de todas as combinações para todos os perfis.

Condições: tarifas vigentes comparáveis, custos sem pendência no grupo observado e conhecimento suficiente da composição/horas. No caso parcial, é necessário conhecer quem tem valorização; o agregado isolado não identifica esse participante. Arredondamento pode limitar a precisão noutros conjuntos, mas estes exemplos recuperam exatamente a tarifa aprovada.

Impacto: exposição inferida de **custo hora RH**, não demonstração de salário líquido, evidência documental ou remuneração total. Não foi identificada quebra de tenant nos testes desta classe. A retirada preserva as horas/histórico corretamente; o problema é a informação revelada pelas somas.

### GI-02 — sinal individual de pendência HR-31, requer decisão funcional

Num agregado com uma pessoa, 540 minutos e `hr31_pending_groups:1` revelam a classificação de excedente desse dia. O valor monetário permanece NULL. O leitor não cria pagamento nem custo de HE. O conhecimento das horas pode já permitir essa conclusão, pelo que não se classifica automaticamente como novo P1/P2 sem uma regra aprovada de confidencialidade desta classificação. O sinal deve integrar a decisão HR-38 e eventual política de supressão.

### Outras verificações de segurança

PASS local para empresa/obra, tarifa confidencial e aprovação RH negadas aos perfis técnicos, ajudantes privados fechados, DML direto fechado nos contratos novos e revogação aplicada à consulta seguinte. JWT de Encarregado não ganha custos com uma alegação `funcao:gestao_plataforma`. Actor inativo, token expirado, assinatura inválida e tentativa de assumir o papel PostgreSQL são recusados no transporte local.

Não há P0 adicional confirmado nesta auditoria. Isto não certifica todas as policies legadas de produção: o catálogo real não foi consultado e o bootstrap contém fixtures/helpers sintéticos explicitamente delimitados.

## 2. Alternativas para decisão HR-38

| Opção | Utilidade | Limitação |
| --- | --- | --- |
| Número mínimo de pessoas + ocultação de grupos pequenos | Simples; mantém parte dos mapas | Insuficiente sozinho: diferenças, subtotais, concentração de custo e três obras recuperam tarifas |
| Agregação mensal + remover dias/subtotais parciais | Reduz comparações e preserva visão mensal | Pessoa única mensal e composição entre obras continuam possíveis; não garante confidencialidade |
| Supressão primária e complementar coordenada entre relatórios/obras/períodos | Mantém valores reais apenas nas células consideradas seguras | Complexidade e perda de disponibilidade; requer tratar histórico de divulgações e conhecimento externo; limiar fixo não basta |
| Custos operacionais com preços de orçamento/padrão separados das tarifas RH | Preserva mapas e comparações exatos sem derivação direta da tarifa pessoal | Altera a semântica da estimativa; exige fonte, aprovação e rótulo claros; não é custo RH real |
| Faixas/arredondamento/perturbação estável | Mantém indicação aproximada | Pode ainda permitir aproximações; ruído variável pode ser eliminado por repetição; prejudica reconciliação contabilística |
| Valores monetários RH só para perfis RH autorizados; técnicos mantêm horas/estado operacional | Proteção mais direta até aprovar outro modelo | Reduz utilidade técnica e altera visibilidade aprovada; depende de autorização expressa |

**Recomendação:** decidir primeiro se a equipa técnica precisa de custo real RH ou de estimativa operacional de orçamento. Para preservar a utilidade sem revelar tarifas pessoais, a opção de preço padrão/orçamental independente do RH oferece o contrato mais claro, se essa mudança funcional for aceite. Se o valor tem de continuar baseado na tarifa RH, não prometer confidencialidade com simples limiar ou mudança para mês: será necessário aprovar perda de granularidade/visibilidade e testar divulgações combinadas, ou aceitar explicitamente o risco residual. Manter o candidato completo sem publicação enquanto essa decisão estiver pendente.

Nenhuma destas alternativas foi implementada. Não se retirou acesso aprovado nem se modificou o cálculo.

## 3. Coerência técnica e regressões

| Fluxo | Evidência local e resultado |
| --- | --- |
| Tablet, Dia Normal/Manhã/Tarde/Personalizado | Domínio/cliente e browser em 768×1024, 1024×768 e 390×844: sugestões por referência legítima, edição factual, cancelar, intervalos reais, sem overflow e sem erros JS |
| Obra de destino e multiobra | Encarregado autorizado no destino; permanência de origem preservada; conflitos globais/ocultos recusados; esperado contado uma vez; plano final atómico |
| Garantia/Outra | Obra original preservada, referência livre sem obra fictícia; associação administrativa explícita com motivo/revisão/histórico; sem alterar horas originais |
| FALTOU→Ausências→Conferência | Ocorrência neutra, UUID/autoria/obra conservados; classificação administrativa; ponto existente bloqueia ausência; correção invalida conferência |
| HR-27 informativa | Reconhecimento factual sem pagamento/valor HE; pendências obrigatórias distintas continuam bloqueantes |
| HR-30 externo/Excel | Confirmação Diretora por revisão/fingerprint; alterações invalidam exportação; XLSX real preserva relógios, soma >24h e texto sem fórmula; externo sem salário/HE interna |
| HR-31 | Factos de 9h mantidos; custo pendente NULL; total parcial não apresentado como zero; não há lançamento financeiro automático |
| Tarifas RH | Aprovação administrativa explícita, prova/motivo/vigência/revisão; versões futuras sem sobreposição; versão anterior/histórico preservados |
| Concorrência/idempotência | Duas conexões; um efeito para o mesmo pedido; payload diferente/conflito de revisão recusados; revogação/tenant relidos após lock nos writers testados |
| AD-13/14/15 e AD-03 | Incluídos no bootstrap encadeado: coerência de jornada, constraints diárias, isolamento HE, referência individual e congelamento histórico continuam aprovados |
| Scripts locais | Ciclos precheck→backup→migration→postcheck→rollback→reinstalação dos estágios preparados passaram; rollback após uso recusa destruir história |
| Sessão | Regresso de respostas antigas, logout, refresh concorrente e identidade substituída testados sem contaminar sessão seguinte |

Não se reabriram regras aprovadas, incluindo a confirmação HR-30 pelo Diretor. Não foram alterados almoço, tolerância de 15 minutos, salários ou factos existentes.

## 4. Testes e reprodução

- Suite PostgreSQL/JWT final: **308 PASS / 0 FAIL / 0 SKIP**. Inclui a suite existente de 292 testes, os casos adicionais de inferência e transporte.
- Domínio/cliente/Excel/sessão: **68 PASS / 0 FAIL / 0 SKIP**.
- Total automatizado Node destas execuções finais: **376 PASS / 0 FAIL / 0 SKIP**. Execuções intermediárias/baseline repetidas não são somadas.
- Browser: **8 suites aprovadas**, separadas dos totais Node: editor 3, equipa 3, revisão desktop 1, painéis administrativos/HR29 1. Zero erros JS nessas páginas sintéticas.

**PASS de teste de inferência significa que a vulnerabilidade foi reproduzida. O gate de confidencialidade é FAIL**, conforme `security_gate` nas evidências. Suites verdes não anulam GI-01.

Durante a preparação do teste houve um caminho de importação temporário incorreto, corrigido no harness de auditoria. Excel/browser inicialmente não localizaram a dependência SheetJS nesta máquina; a execução final usou a instalação local existente em `tests/runtime/node_modules/xlsx`. Esses erros de ambiente não foram tratados como falhas funcionais nem ficaram ocultos no resultado final. Nenhuma expectativa de segurança foi relaxada.

Reprodução Windows, somente BD descartável:

```powershell
$env:QUADRO_PG_BIN="$env:TEMP\primeline-doc-guard-pg176\package\native\bin"
$env:QUADRO_TEST_DEPS="$env:TEMP\primeline-medicina-test-deps\runtime\node_modules"
$env:QUADRO_POSTGREST="$env:TEMP\primeline-authorization-postgrest\postgrest.exe"
$env:PATH="$env:QUADRO_PG_BIN;C:\Program Files\PostgreSQL\17\bin;$env:PATH"
node tests/attendance-hours-final-audit.test.mjs
$env:HOURS_XLSX=(Resolve-Path tests/runtime/node_modules/xlsx).Path
node --test tests/attendance-hours-domain.test.mjs tests/attendance-hours-client.test.mjs tests/attendance-hours-map.test.mjs tests/attendance-hours-operational.test.mjs tests/attendance-hours-excel.test.mjs tests/attendance-hours-admin.test.mjs tests/attendance-hours-review.test.mjs tests/attendance-monthly-client.test.mjs tests/attendance-external-month-client.test.mjs tests/session-isolation.test.mjs tests/session-boundary.test.mjs
```

Browser: definir `PLANNING_PLAYWRIGHT` para a instalação Playwright local, `PLANNING_CHROMIUM_EXE` para Edge/Chromium e, no browser de revisão, `HOURS_XLSX` para `tests/runtime/node_modules/xlsx/dist/xlsx.full.min.js`. Executar os quatro scripts `attendance-hours-{editor,team,review,prepared}-browser.mjs`. Não requer contas reais. Capturas temporárias são reproduzíveis; foram inspecionadas visualmente amostras do editor tablet e mapa desktop.

Evidências versionáveis: `docs/auditoria-gestao-horas-evidencias-20261014.json`. Apenas pessoas, empresas, JWTs e obras sintéticas; tokens/segredos não são gravados. Nenhum snapshot de produção.

## 5. UAT autenticada

**Ambiente isolado disponível e executado:** PostgreSQL 17.6 + PostgREST 16.4, listen apenas em localhost, JWT HS256 assinado com segredo aleatório efémero, utilizadores sintéticos. Papel autenticador `NOINHERIT/NOBYPASSRLS`, sem acesso ao papel postgres; sujeito Auth diferente do ID interno, mapeado explicitamente. O cliente real de Gestão de Horas fez leituras HTTP de agregado/equipa. Writer integrado fez preview sem facto, confirmação de um facto sintético e replay sem duplicação.

A adaptação dos helpers `auth.uid()` e mapeamento Auth pertence exclusivamente à fixture descartável. Não altera a aplicação nem a BD real. PostgREST valida assinatura/expiração; a autorização funcional continua a consultar a função/empresa/obra do utilizador na BD.

**Limites:** não houve servidor Supabase Auth/GoTrue nem teste de login, refresh ou logout do serviço hospedado. Browser usou respostas sintéticas; não se declara UAT integral browser→Supabase Auth→PostgREST. Políticas/tarifas reais, dados históricos reais e compatibilidade do catálogo instalado continuam sem validação nesta tarefa. Workbook RH real opcional não foi utilizado.

Matriz preparada para ambiente autenticado de homologação/autorizado, após a decisão HR-38:

| Perfil | Leituras | Escritas controladas apenas com dados de UAT | Negativas/limites |
| --- | --- | --- | --- |
| Administrativo | Referências, tarifas/evidências, faltas e conferência RH do tenant | Aprovar vigência, classificar ocorrência, conferência/retorno | Outro tenant; revisão antiga; preview/cancel não grava |
| Gestão da Plataforma | Capacidades atuais, contexto e painéis legítimos | Fluxos administrativos aprovados | Respeitar tenant e auditoria; não presumir equivalência com Gerência |
| Gerência | Consultas atuais | Não presumir alterações administrativas permitidas | Verificar recusa segundo capabilities atuais |
| Diretor | Obras autorizadas, relatório factual, agregado conforme decisão HR-38, externo | Confirmação externa atual, correção autorizada | Tarifa/evidência RH negada; outra obra/tenant negados |
| Adjunto/Preparador | Só obras autorizadas e contratos de leitura aprovados | Somente capabilities existentes | Tarifa RH/ledger mensal individual negados; não ampliar acesso |
| Encarregado | Próprio/equipa e destinos autorizados; tablet | Normal/Manhã/Tarde/Personalizado, FALTOU, multiobra com dados sintéticos | Zero custos/tarifa; sem classificação administrativa; quadro conforme política atual |
| Actor revogado/inativo/empresa B | Nova consulta não revela a obra da empresa A | Nenhuma confirmação após revogação | Mesmo JWT e preview antigo; sem efeitos parciais |

Transversal: troca Gestão→Encarregado e Diretor→Encarregado; token expirado/refresh; cache/DOM sem dados antigos; duas sessões; validação dos contratos novos com catálogo de homologação; Network/Console e viewports tablet/mobile. Só depois, preflight e rollout separadamente autorizados. Esta matriz não autoriza escrita em produção.

## 6. Publicação e estado final

Bloqueios: **GI-01/HR-38 exige decisão funcional e mitigação aprovada**; completar UAT hospedada e catálogo/preflight autorizado. Não existe razão para alterar automaticamente os contratos só para obter uma suite verde.

Produto auditado continua exatamente no SHA indicado. A branch de auditoria preserva a base, acrescenta três ficheiros de teste, evidências JSON e este relatório. O SHA da auditoria é o commit que contém este relatório; consultar `git rev-parse HEAD`. Verificação final de working tree e `git diff --check` registada na entrega. Sem push.

**Recomendação: NO-GO para publicar o candidato completo; GO apenas para decidir a mitigação HR-38 e preparar a próxima validação local.** Não há novo desenvolvimento autorizado por este relatório.
