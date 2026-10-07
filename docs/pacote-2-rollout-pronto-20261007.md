# Pacote 2 — rollout preparado, 07/10/2026

## Estado e candidato

Branch: fix/pacote-2-documental-rollout-final-20261007, a partir de 3b44c165a04169f76b6c4f8dc16db0b46bd12f10. O commit final da branch é indicado na entrega. Não se executou SQL real, backup real, deploy, main, cutover real, marcador ou Fase B.

Baseline factual recebida: PostgreSQL 17.6; alocações 227; movimentos 100; ausências 579; ponto legado 0; HE 0. Os 13 objetos V2 estão ausentes. Os 28 writers económicos correspondem aos hashes conhecidos. Guardas do hotfix anterior presentes. Writer legado ativo é esperado antes do cutover. A fonte de calendário existe; configuração V2 ainda não existe.

O hotfix documental corrige fn_apagar_documento_entidade(uuid) e 12 RPCs correlatas, incluindo documentos de obra/RNC, anexos/imóveis/pedidos e frota. Não depende de RLS para proteger SECURITY DEFINER. A guarda restritiva de Storage também valida a empresa nos namespaces já existentes, sem novos grants, buckets, ficheiros ou paths. Inventário e limites: pacote-2-security-definer-documental-20261007.md.

## PRÓXIMO E ÚNICO SQL MANUAL, antes de autorização de rollout

Executar integralmente **supabase/pacote2_precheck_real_final_20261007.sql** no SQL Editor do projeto Primeline-Obras, ref znttyadndpkxuekhjamd. Não executar qualquer outro script nesta fase. Copiar/exportar a única linha precheck_real_final.

É REPEATABLE READ READ ONLY e termina com ROLLBACK. Usa somente catálogo, contagens, coerência agregada e fingerprints privados. Não chama RPC mutante, não cria objetos, não altera dados/grants e não devolve PII, URLs ou montantes. Não depende de NOTICE.

A vulnerabilidade real conhecida ainda estará instalada: **P1_KNOWN_BASELINE_READY_FOR_HOTFIX** é aceitável. Verifica SHA-256, owner, SECURITY DEFINER, ACL/config e todo o catálogo congelado. Qualquer variante/delta imprevisto é BLOCKED. Funções fora da classe documental são congeladas por metadata/hash; isso não é certificação universal de segurança dos seus módulos.

READY_FOR_DOCUMENTAL_AND_V2_ROLLOUT significa somente que a baseline esperada pode receber os scripts preparados, depois de autorização expressa. Não autoriza execução automática. Resultado BLOCKED: parar, apresentar TODO o array de blockers e não adaptar a BD.

## Ordem exata após autorização própria

### Etapa A — documental

1. supabase/documentos_rh_tenant_precheck.sql
2. supabase/documentos_rh_tenant_backup.sql
3. supabase/documentos_rh_tenant.sql
4. supabase/documentos_rh_tenant_postcheck.sql

Backup privado captura dados documentais/anexos/objetos e definições/owner/ACL/config das 13 RPCs. Migration conserva dados, assinaturas e capacidades legítimas, exigindo ator ativo e tenant correto. Postcheck compara dados integralmente e certifica policies, grants, helpers, RPCs, bucket e catálogo.

Compatibilidade: supabase/documentos_rh_tenant_rollback.sql → supabase/documentos_rh_tenant_rollback_postcheck.sql. Este rollback conserva a proteção; nunca reinstala os writers vulneráveis. Não o executar automaticamente.

### Etapa B — backend Folha V2 (não é a Fase B do Quadro)

1. supabase/folha_ponto_v2_precheck.sql
2. supabase/folha_ponto_v2_backup.sql
3. supabase/folha_ponto_v2.sql
4. supabase/folha_ponto_v2_gestao.sql
5. supabase/folha_ponto_v2_postcheck.sql

O precheck herda o hotfix económico instalado e compõe APENAS o delta documental certificado. Não depende de outra branch nem de ficheiro ignorado/local. Os scripts usam os artefactos commitados deste candidato.

Rollback, somente se as suas próprias precondições permitirem: supabase/folha_ponto_v2_gestao_rollback.sql → supabase/folha_ponto_v2_rollback.sql. Factos/história/revisões impedem rollback destrutivo; exige plano específico se existirem. Não remover dados para fazer rollback passar.

### Etapa C — frontend / UAT curta

Publicação/UAT não são automáticas. Backend deve passar antes de publicar o frontend. Usar preview do commit de entrega exato e executar a checklist abaixo com contas reais disponíveis. Qualquer escrita real precisa de autorização específica, dados de teste escolhidos, snapshot, previsão de alertas/história e reposição; nunca criar consultas de Medicina/documentos reais para testar.

Depois da UAT aprovada, publicar SOMENTE o commit entregue pela integração Git já existente, mediante autorização própria. Não reaplicar SQL pelo deploy. Confirmar assets pelo manifesto commitado e verificar leitura/perfis em produção. Não marcar gates privados automaticamente.

### Etapa D — cutover legado separado

Somente DEPOIS do frontend V2 validado:

1. supabase/folha_v2_legacy_cutover_precheck.sql
2. supabase/folha_v2_legacy_cutover.sql
3. supabase/folha_v2_legacy_cutover_postcheck.sql

Rollback disponível: supabase/folha_v2_legacy_cutover_rollback.sql, sujeito às suas guardas. Zero pontos legados simplifica a instalação, mas não elimina suporte histórico. Preservar zero linhas, sem converter história inexistente. Não fechar writer antigo enquanto o frontend V2 não estiver validado.

**FASE B DO QUADRO fica fora deste rollout inicial.** Não executar marcador privado, backup B ou scripts quadro_fase_b_pos_hotfix*. A sua existência no repo não autoriza execução nem impede a instalação/publicação factual da Folha.

## STOP obrigatório em cada etapa

- PRECHECK PASS: pode seguir apenas dentro da etapa autorizada. FAIL: STOP.
- BACKUP PASS: pode seguir. FAIL: STOP; não repetir/substituir backup sem decisão.
- MIGRATION erro: STOP, confirmar rollback da transação e avaliar o rollback correspondente. Não corrigir produção/adaptar SQL em improviso.
- POSTCHECK FAIL: STOP. Não prosseguir à etapa seguinte.
- Mesmo com PASS, não avançar a uma etapa ainda não autorizada.
- Evitar operações documentais/Folha concorrentes durante a janela aprovada de backup/instalação; os scripts não substituem uma janela operacional controlada.
- Login/MFA/consentimento: reutilizar a aba existente; se necessário, parar para autenticação manual da Jordane. Nunca repetir login em loop.

## UAT real curta (planeada, não executada)

| Conta | Verificação mínima |
|---|---|
| Gestão Plataforma | Abre Folha, seleciona obra, acesso de superutilizador funcional; uma ação administrativa aprovada, com tenant/revisão/auditoria preservados. |
| Administrativo | Folha; férias/ausência; correção fora da janela com motivo; Vencimentos abre; HE administrativa no âmbito permitido. |
| Encarregado | Somente obras/equipa autorizadas; um registo factual aprovado; MARCAR EQUIPA PRESENTE, COMPLETAR EQUIPA e DIA NORMAL com preview/confirm; histórico; sem custos/Vencimentos/RH administrativo. |
| Diretor/Adjunto | Leitura operacional; HE approve/reject no âmbito autorizado; sem processamento administrativo. |
| Sessão | Diretor → Encarregado e Gestão → Encarregado; nenhum resíduo privado/financeiro, resposta antiga descartada. |

Não retestar toda a plataforma. Usar desktop e um dispositivo tablet/mobile representativo. Registrar request_id, revisão, alertas e resíduos técnicos das escritas autorizadas, sem PII no relatório. Não prometer zero vestígio: história/auditoria são preservadas.

## Frontend exato

O código frontend NÃO foi alterado nesta tarefa. Conteúdo idêntico ao commit **3b44c165a04169f76b6c4f8dc16db0b46bd12f10**. O commit de entrega acrescenta scripts/testes/documentação deste fecho. Usar esse commit completo para a futura publicação; o seu SHA consta da entrega.

Manifesto: docs/pacote-2-frontend-assets-20261007.json (59 ficheiros JS/CSS/index/config, hashes SHA-256). Módulos Folha: src/attendance-sheet.js, attendance-client.js, attendance-domain.js, attendance-management.js e respectivos estilos. Confirmar nomes existentes pelo manifesto; não inferir module path.

Cache atual: app.js?v=186; styles.css?v=104; workforce-calendar.css?v=9; attendance-sheet.css?v=3; import attendance-sheet.js?v=8; attendance-domain.js?v=7; attendance-client.js?v=5; attendance-management.js?v=6. Nome visível: **FOLHA DE PONTO**, aba Equipa → attendance, acesso operacional diário do Encarregado. O legado ponto_pessoal_obra continua disponível para leitura/histórico e writer até ao cutover. Não existe migração de dados no frontend.

## Calendário e automatismos

Instalação estrutural/factual funciona sem calendário validado. Defaults: correction_days=1; overtime_enabled=false; calendar_complete=false; calendar_validated_years vazio; holiday_dates vazio. Gestão adiciona gates de regras/exportação; exportador oficial continua recusado e não se inventa modelo. HE monetária/exportadores permanecem desativados até configuração validada. Não inferir feriados/completude por existir fonte.

## Verificação local final

Resultados e commit de entrega são registrados ao concluir as suites integrais e a segunda worktree limpa. Teste de decisão READY usa baseline explicitamente sintética para exercitar o motor; a baseline factual de produção permanece congelada e não é substituída. A sequência de rollout usa os scripts exatos e dados locais, sem cutover na UAT. Cutover/rollback são exercitados separadamente nas suites; não são executados em produção.

## Gate externo restante

Uma execução manual do SQL read-only acima, seguida da análise de todos os blockers e autorização expressa. Nada deste documento constitui autorização de rollout real.

