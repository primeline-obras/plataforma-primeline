# Segurança, permissões, integridade e versões

## Conclusão e limites

Não certifica segurança global de produção. Esta missão não consultou o catálogo real nem autenticou contas reais. CONFIRMADO local, PROVÁVEL e NÃO VERIFICADO são usados separadamente. O produto não foi alterado. Nenhuma permissão, SQL, main ou deploy foi modificado.

## Achado novo N-SEC-01 — P1, HTML ativo no número da fatura

**CONFIRMADO no código e browser isolado**; persistência/alcance/exploração em produção NÃO VERIFICADOS.

- Entrada: `src/app.js:4644` lê número da fatura como string trim para o rascunho; não escapa o dado persistido (escaping deve ocorrer na saída, não corromper o dado).
- Saída: `src/app.js:4676`, `openPaymentDialog`: interpola `billing.numero_fatura` diretamente em `innerHTML`.
- Prova: `tests/night-global-browser-security.test.mjs` extrai a função real desse checkpoint, cria uma fatura exclusivamente sintética e abre o diálogo num browser sem rede e origin null. O número cria um elemento HTML; handler local só altera um marcador booleano. Nenhuma API, token, documento ou ator real é usado.
- Resultado: `17-PROVA-HTML-INJECTION.json`, elemento/handler true. Isso demonstra um sink com execução ativa e potencial stored XSS quando o valor persistido chega ao diálogo. Não se executou ação privilegiada nem se inventou prova contra produção.
- Impacto potencial: código executado no contexto do utilizador que consulta o dado pode usar a sua sessão/capacidades. RLS não corrige um frontend que executa conteúdo como esse utilizador. CSP real não foi consultada; uma CSP restritiva poderia bloquear o handler, mas não torna o sink correto.
- Próxima tarefa: saída por textContent/escaping contextual, revisar sinks semelhantes, regressão HTML/atributos e prova de roundtrip em BD sintética. CSP/Trusted Types como defesa adicional após validar compatibilidade. **Não corrigido** nesta missão, que proíbe alterações funcionais.

## HR-38 — vulnerabilidade já comprovada, não repetida

Reutiliza `docs/auditoria-gestao-horas-integrada-final-20261014.md` e SHA `12d86584`. P1: agregado diário/subtotal/composição de obras revela tarifa RH apesar de ocultar campos individuais. A prova de pessoa única, diferença, equipa, parcial e sistema de três obras não foi repetida.

Decisão recente: custos-padrão por função/nível aprovados em princípio, independentes das tarifas RH; tarifa RH individual confidencial aplicada em todas as obras, aprovação pelo Administrativo autorizado. Fonte da tabela-padrão, aprovador, vigências, função/nível efetivos e migração continuam por fechar. Não implementar HR-38/40/41/42.

Recomendação conceptual:

- Dois ledgers com proveniência explícita, não duas arquiteturas de tenant. Padrão operativo da empresa por função/nível/vigência/aprovação vs valor RH por pessoa/vigência/evidência confidencial.
- O mapa técnico deve usar preço padrão aprovado, nunca reverter silenciosamente para RH quando faltar padrão. Pendente permanece NULL com motivo mínimo.
- Um colaborador com cargo formal distinto de função operacional exige classificação de valorização explícita; não inferir do nome, cargo/login ou obra visitada.
- Preservar snapshots e consultas históricas: não revalorizar referências congeladas automaticamente quando a tabela mudar.
- Autorizar empresa/obra antes do cálculo e do replay; retirar `individual_costs_included:false` como alegação de privacidade, mantendo documentação do significado do DTO.
- Recursos sem função/nível/preço comprovados continuam pendentes. HE monetária e cálculos salariais permanecem fora do âmbito.

## Matriz por capacidade — não apenas menu

| Perfil | Base frontend observada | Verificação necessária |
| --- | --- | --- |
| Gestão da Plataforma | Vistas totais; papel preservado | Superutilizador funcional com tenant/revisão; N-ADM-07 mostra exclusão local indevida em RNC |
| Gerência | Vistas totais; agrupada por alguns helpers | Não herdar automaticamente aprovação RH/payroll/tarifa; consultar capability própria |
| Administrativo | RH/documentos/ausências; vários módulos | Tenant atual, identidade ligada e aprovação administrativa explícita |
| Financeiro | Fluxos financeiros; pagamento | Empresa, obra, total/saldo/revisão; não basta `fn_e_financeiro()` global |
| Diretor/Adjunto/Preparador | Obras autorizadas e leitura técnica | Tarifas/evidências RH não acessíveis; HR-38 ainda bloqueante para agregado atual |
| Encarregado | Folha/Plano/Planeamento/documentos/RNC/agenda; Quadro leitura | Leitores mínimos, sem custos/gestão global; dados de outra obra só pontuais conforme regra |

Fonte de vistas: `src/access-control.js:8`. Gating funcional: `app.js:849`/`:879`, `planning.js:7`/`:96`, RNC e clientes V3. Menu não é autorização backend.

## RLS/ACL/SECURITY DEFINER

CONFIRMADO: `supabase/encarregado_escopo_migration.sql:62`/`:64` instala guardas RESTRICTIVE nos acessos diretos a colaboradores/SUB; writers económicos receberam guardas por obra; helpers privados sem execução externa e owner/search_path/ACL verificados por postchecks. Os leitores novos usam actor ativo/empresa/obra; suíte anterior já testou revogação, Auth subject e tarifa privada.

N-SEC-02 — **P1 risco de reinstalação, CONFIRMADO artefacto histórico; presença atual NÃO VERIFICADA**: `autos_faturacao_workflow.sql:55`/`:59` define policies permissivas `using(true)`/`with check(true)`, e `rls_cashflow_fontes_reais.sql:16` permite `OR fn_e_financeiro()` sem tenant explícito. SQL histórico não é plano de rollout atual. Uma policy permissiva nova pode alargar outra permissiva; guards restritivas/revokes posteriores podem neutralizá-la. Não declarar exposição atual sem catálogo/replay exato da ordem instalada. Não executar esses scripts isoladamente para “resolver schema em falta”.

Pendência débitos tenant-safe já existe na branch separada; não duplicar desenvolvimento nem retirar o bloqueio de importação. Leitura/INSERT históricos administrativos de débitos não demonstram isolamento tenant (`debitos_diretos_financeiro.sql:21`). Reconciliar o pacote preparado antes de qualquer uso/rollout autorizado.

SECURITY DEFINER não é vulnerabilidade sozinho: exige owner confiável, search_path fixo, guardas explícitas, tabelas qualificadas, ACL mínima e tenant antes de replay. RLS pode ser bypassada legitimamente pelo owner do helper; autorização tem de existir dentro do contrato. `FORCE RLS` não deve ser imposto indiscriminadamente para “corrigir” funções já validadas.

## Revisão / concorrência / idempotência

- Novos V2/V3: request/token, revisão de factos/referência/conferência, advisory/row locks, replay vinculado ao autor e fingerprint. Auditoria anterior preservada; não se repetiram centenas de testes da Gestão de Horas.
- Medicina/Viaturas: 46 PASS nativos desta missão, duas conexões e invariáveis com saída RH/revisão/tenant; sem PGlite para simular concorrência.
- N-FIN-01: múltiplos POSTs sem transação global/idempotência do rascunho; confirmação UI não garante atomicidade backend.
- N-FIN-05: lock existe, mas regra de saldo/parcial não é correta para prestações; concorrência segura não torna o contrato financeiro completo.
- Aviso de fatura semelhante antes de guardar não equivale constraint/dedup atómica; corrida simultânea não foi provada nesta missão. PROVÁVEL investigação adicional, não duplicado real demonstrado.

## Documentos / Storage / supply chain

- Guardas RH/viaturas/ausência e Storage já preparadas/publicadas conforme histórico fornecido; não reabrir problema de ownership resolvido nem trocar para `SET ROLE`. Catálogo real atual NÃO VERIFICADO.
- Metadata, bytes e links de índices são três camadas. `documents.js:219` upload→POST metadata em operações diferentes tem potencial de órfão em falha; confirmação/compensação/reconciliação é pendência a investigar.
- `index.html:26`/`:27`: dois scripts CDN com versão explícita mas sem SRI no HTML. `_headers`/CSP de Cloudflare não encontrados no snapshot percorrido; configuração no serviço NÃO VERIFICADA. P2 hardening de dependências/headers, sem alegar CDN comprometida.
- Sem ficheiros Git de nome `.env/.pem/.p12/.pfx/.key` encontrados nesta árvore. Não foi feito scan integral de histórico de segredos. `config.js` não foi copiado para relatórios; a palavra service_role em comentários/config não é prova de segredo. Config de cliente deve conter apenas chave pública, nunca service_role.
- Scripts de seed/dados identificados por nome não foram exportados; scanner inicial extraiu só metadados de declarações, sem valores. Revisão funcional e inventário final excluem artefactos de seed real; nenhum dado pessoal integra o pacote desta auditoria.

## Versões e ordem de migrations

`13-DEFINICOES-SQL.csv` e `14-SOBREPOSICOES-SQL.csv` enumeram ocorrências e sobreposições (incluem rollback/restauro, não objetos instalados). Não executar todos os SQL por ordem alfabética. A mesma rotina `fn_executar_rotinas_diarias` é redefinida por Viaturas/Contratos/Alertas/Imóveis; o resumo de custos tem várias definições sucessivas.

Gestão de Horas tem cadeia explícita de dependências/fingerprints: avaliação diária→AD15→AD14→AD13→AD03→HR27/FALTOU→leitores→conferência→destino→externos→referências→tarifas/mapas→plano integrado→contextos operacionais. Ordem concreta deve continuar a ser a do runner/prechecks do candidato; os nomes aqui são mapa, não autorização SQL. A Fase B atualizada está separada em `b7bf4c1`; o script antigo não deve “passar” por enfraquecimento de gate.

N-SEC-03 — P2 CONFIRMADO falta de manifest único executável/compatibilidade global: muitos SQL avulsos/manual, gates fortes recentes e instruções históricas distintas. Recomendação de futuro: manifest declarativo versão/base/destino/dependências, hashes normais, arquivo de scripts históricos, fail-closed. Não remover os scripts antigos nem alterar gates nesta missão.

## Pendências de auditoria real

Catálogo/RLS/ACL/owners atuais, document Storage e bytes, jobs/email, CSP/headers reais, limites/paginação PostgREST, casos históricos inconsistentes e UAT Auth hospedada permanecem NÃO VERIFICADOS. Testes sintéticos e source review não permitem afirmar “zero vulnerabilidades de toda a produção”.

### Aprofundamento N-SEC-01

Após a prova inicial, dois pontos relacionados foram comprovados com funções reais e browser sem rede: `renderWorks` (`app.js:1593`) insere nome da obra como HTML; `financeCard` (`app.js:1247`) insere nome do fornecedor sem escaping, enquanto campos adjacentes usam escaping. Ambos executam apenas marcador sintético. Provas em20-PROVAS-SINKS-ADICIONAIS.json. É a mesma classe P1, não três vulnerabilidades independentes contadas para inflacionar o resultado. Corrigir/rever sinks legados transversalmente; não basta corrigir apenas o diálogo.

A comparação em18-BASE-IMPORTS.json confirmou também esses renderizadores iguais na main local e no candidato; não é regressão demonstrada da Gestão de Horas. Continua sem prova de exploração/instalação/CSP em produção.
