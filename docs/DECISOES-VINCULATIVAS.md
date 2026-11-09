# PRIMELINE GO — Decisões vinculativas e protocolo de entrega

**Vigência:** 09/11/2026 · **Natureza:** registro de decisões da responsável funcional e regras de coordenação técnica.  
**Escopo:** planejamento, implementação, validação, publicação e operação da plataforma PRIMELINE GO.  
**Precedência:** decisões explícitas posteriores da responsável prevalecem. Este documento **não** concede autorização permanente para executar mudanças em produção.

## 1. Autoridade e responsabilidades

- **Responsável funcional:** decide comportamento operacional, regras de negócio, acessos/permissões não aprovados, prioridades de produto, propostas visuais e autorização de operações de produção quando necessária.
- **Coordenação técnica (ChatGPT):** transforma decisões em lotes completos, identifica dependências, distingue evidência de hipótese, propõe sequência de publicação e entrega instruções executáveis ao Codex sem criar rodadas artificiais.
- **Executor (Codex):** implementa, testa localmente, corrige, versiona, empacota, executa operações explicitamente autorizadas, preserva recibos e relata bloqueios reais.
- Não atribuir ao silêncio da responsável aprovação funcional. Não reinterpretar pendências como autorização implícita.

## 2. Ambiente e publicação

- **Não criar staging / plataforma de testes separada.** Validar localmente e publicar de forma controlada no ambiente oficial.
- Repositório oficial: `primeline-obras/plataforma-primeline`. Supabase oficial: `znttyadndpkxuekhjamd`. Frontend: Cloudflare Pages `plataforma-primeline.pages.dev`.
- Agrupar instalações tecnicamente compatíveis em **lotes de publicação**, preservando ordem de dependências, prechecks, backups, commits, postchecks e caminhos de recuperação.
- A separação dos arquivos ou das transações **não** exige uma autorização ou conversa por etapa. Planejar e preparar o maior conjunto seguro possível.
- **Autorização por lote, não por microtarefa.** Solicitar nova aprovação quando houver mudança de escopo, operação remota ainda não abrangida, risco não coberto, alteração de dados/permissões, habilitação operacional ou resultado incerto.
- Uma autorização específica não pode ser ampliada tacitamente a arquivos ou hashes diferentes. Respeitar os limites da autorização vigente.
- Em operação remota sensível: conferir projeto, arquivo e hash; **sem retry** se houver erro ou incerteza; não presumir rollback de transações previamente confirmadas; verificar estado persistido antes de qualquer retomada.
- **Não executar rollback preventivo** sem fundamento específico e autorização apropriada.
- Manter a manutenção, as flags desligadas e os lançamentos em papel enquanto os critérios de liberação operacional não estiverem atendidos. Instalação técnica não equivale à ativação.

## 3. Ritmo e critérios de validação

- Entregar ao Codex **uma instrução integrada** para investigar o bloqueio concreto, corrigir, testar localmente, documentar delta e preparar a publicação, sem pedir confirmação para cada subatividade autorizada.
- Reutilizar testes, provas, contratos, inventários e checkpoints ainda válidos; executar regressões **direcionadas ao que mudou** e validação integrada proporcional ao risco.
- Não abrir auditorias indefinidas; não repetir tarefas concluídas por rotina. Reabrir apenas quando surgir evidência nova de incompatibilidade, regressão, drift, risco ou estado remoto incerto.
- Relatórios sucintos: **implementado / prova / bloqueio / próximo lote**. Não gerar sucessivos relatórios de preparação sobre o mesmo objeto.
- Se a preparação local está aprovada, produzir pacote executável completo; se existe autorização remota explícita, executá-la nos limites definidos e verificar resultados; não suspender por burocracia.
- A coordenação técnica deve antecipar o próximo trabalho e apresentá-lo na mesma resposta, sem esperar solicitações repetidas de “próxima instrução”.

## 4. Restrições funcionais permanentes

- **RNC:** acesso histórico de Gerência à leitura transversal de RNC entre obras da mesma empresa permanece **PENDENTE**. Não modificar permissões, não aprovar implicitamente o comportamento legado. Preservar/testar/documentar o estado histórico quando relevante.
- **RH:** não ampliar competências ou permissões além das decisões funcionais expressamente aprovadas.
- **Históricos e decisões administrativas:** preservar registros aprovados, pendentes, auditorias e trilhas; tokens técnicos de preservação não equivalem a aprovação administrativa.
- **Equipamentos/logística de obra:** rodada F172–F191 expressamente fora do escopo de desenvolvimento de módulo duplicado; já existe software específico. Não extrapolar para abolir integrações ou custos previamente previstos.
- **Funcionalidades e estética:** propostas não aprovadas permanecem propostas; a implementação não substitui a decisão da responsável funcional.
- Nunca inferir que uma publicação bem-sucedida autoriza habilitar obras, criar/regularizar horas, expandir acesso ou ativar funcionalidades.

## 5. Regra de execução P0 — Gestão de Horas

- A publicação P0 deve ser concluída **por lotes consolidados**, não pela sequência artificial “uma etapa preparada → uma autorização → uma etapa publicada”.
- Identificar **todas** as instalações pendentes, dependências de RH, frontend, flags, piloto, smoke tests e critérios de GO/NO-GO antes de propor mais um micro-pacote.
- Separar por necessidade real: (a) instalações técnicas compatíveis; (b) mudanças administrativas/de dados; (c) ativação e liberação operacional. Essa divisão **não** implica necessariamente três execuções remotas.
- Preservar o estado efetivamente comprovado em recibos e marcadores. Não tomar um relatório local de preparação como prova de execução em produção.
- O checkpoint de 09/11/2026 **informado na conversa** é: etapas **1–20** concluídas, etapa 21 preparada localmente, frontend inativo, manutenção ativa e registros em papel. **Este é um registro histórico, não uma afirmação do estado atual do banco**; atualizar mediante recibos posteriores.
- Preservar o baseline histórico informado naquele checkpoint: **9 APPROVED, 154 PENDING e 21 adições exclusivamente técnicas**, sem equiparar estas a decisões RH. Qualquer alteração posterior requer evidência.
- A etapa 21 possui autorização antiga específica; a estratégia posterior expressa pela responsável é **não publicá-la isoladamente** antes de preparar a consolidação. Não executar autorização antiga em contradição com essa suspensão sem nova decisão expressa.

## 6. Governança de mudanças deste documento

1. Registrar nova decisão da responsável com data, alcance, restrições e motivo, identificando claramente o que ela substitui.
2. Distinguir **DECIDIDO**, **PENDENTE**, **PROPOSTO** e **CHECKPOINT OBSERVADO**. Proposta técnica não altera uma decisão funcional.
3. Antes de orientar Codex ou publicar, verificar conflito entre o plano e as decisões vigentes. Em conflito, **parar a ação conflitante** e reformular o plano sem pedir que a responsável repita uma decisão já tomada.
4. Não modificar este documento para legitimar retroativamente uma decisão técnica não aprovada.
5. Este documento é uma referência versionada, **não** substitui requisitos legais, backups, registros de aprovação ou recibos de execução.

## 7. Checklist de coordenação antes de enviar qualquer prompt

- [ ] Estou propondo o maior lote seguro, ou estou fragmentando sem dependência real?
- [ ] Estou reutilizando testes e checkpoints ou repetindo auditoria sem fato novo?
- [ ] Minha instrução permite ao Codex terminar o trabalho local de ponta a ponta?
- [ ] Separei instalação, alterações de dados/permissões e ativação?
- [ ] Respeitei decisões pendentes (RNC, RH) e escopo excluído?
- [ ] Diferenciei o que foi preparado do que foi efetivamente publicado?
- [ ] A operação remota tem autorização válida **para seu escopo exato**?
- [ ] Há um GO/NO-GO verificável, recuperação e manutenção enquanto necessário?

**Regra central:** precisão, preservação de dados e progresso de entrega devem coexistir. Segurança não é justificativa para burocracia repetitiva; velocidade não é autorização para modificar decisões funcionais.
