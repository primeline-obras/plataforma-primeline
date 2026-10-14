import json,re,csv
from pathlib import Path
Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE');R=Path('docs/auditorias/validacao-profunda-20261014')
def doc(name,text):(Q/name).write_text(text.strip()+'\n',encoding='utf-8')
fronts=[
(1,'INTERFACES','PARCIAL','21 vistas/80 estados na aplicação inteira;45 capturas de estados adicionais; Folha170+34 checks; editor/equipa/painéis/RH/Medicina/Quadro/RNC/Viaturas/Planeamento em browser local.','screenshots/resultado.json;REGISTO-REGRESSOES.json','Fluxos completos dos restantes módulos, estados de carregamento/erro e screenshot por formulário ainda por expandir.'),
(2,'IMPORTADORES','PARCIAL','CSV real com 1000 linhas, BOM, multilinha e aspas; parsers operacionais e Mapa Financeiro ligados ao writer local.','EVIDENCIAS-IMPORT-COMERCIAL.json;EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json','XLSX binários já descodificados; roundtrip de todos os exportadores e commits de todas as famílias ainda por ampliar.'),
(3,'DOCUMENTOS','PARCIAL','Upload/consulta com contexto trocado reproduzidos; extensão/tamanho recusados pelo cliente; bytes vazios e MIME divergente chegam ao transporte.','EVIDENCIAS-DOCUMENTOS-CONTEXTO.json','Storage real local indisponível; ciclo integral de todas as entidades e revisão/remoção ainda não certificado.'),
(4,'ALERTAS','PARCIAL','Filtros reais preservam eventos distintos e retiram obra revogada; produtor Quadro e idempotência/retry: 28 contagens Node.','EVIDENCIAS-ALERTAS-FILTROS.json;logs/ALERTAS-PRODUTOR-LOCAL.txt','Rotinas globais de Medicina/contratos/documentos/Financeiro não ligadas ponta a ponta. Nenhum alerta real lido/apagado.'),
(5,'FINANCEIRO','PARCIAL','Recebimento real via REST: parcelas100+400 =500, saldo43, replay sem terceiro movimento; importação repetida mantém um ajuste.','../validacao-profunda-20261014/EVIDENCIAS-REST-SEGUNDA-PASSAGEM.json;EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json','Casos de adiantamento/retenção/crédito/anulação/investimento e distribuições contratuais devem ser ampliados; P1 anteriores preservados.'),
(6,'FORNECEDORES','PARCIAL','Completude sem especialidade; múltiplas especialidades; entidade ambos; nomes normalizados não fundem IDs; cotação excluída/não comparável não vence.','EVIDENCIAS-FORNECEDORES.json;EVIDENCIAS-IMPORT-COMERCIAL.json','Unidade/IVA/moeda/validade/transporte/mínimos não são campos decididos automaticamente pelo helper de melhor preço. Nenhuma interface nova concedida ao Encarregado.'),
(7,'TEE-ADMINISTRACAO','CONCLUÍDA','Estudo conceptual sintético com factos/custos/preço separados, abaixo.','FRONTE-07-TEE-ADMINISTRACAO.md','Proposta sujeita a decisão; nenhum mecanismo ou tarifa implementado.'),
(8,'RH','PARCIAL','Regressão cumulativa AD15/14/13/03 e HR27–31; 72 pares adicionais por perfil e6 casos de identidade;370 contagens Node na regressão cumulativa; não somar como cenários únicos.','../../validacao-profunda-20261014/RESULTADO-RH-LOCAL.txt;../../validacao-profunda-20261014/EVIDENCIAS-HORAS-PERFIS.json','Tabelas seed sintéticas não equivalem a todos os percursos de cadastro/importação/RH. FP28/29 preservados em standby.'),
(9,'VISUAL','PARCIAL','170 checks em 768×1024,1024×768,820×1180,375×812,1440×900; mais34 em1280×720. Screenshots inspecionadas explicitamente em tablet/mobile.','screenshots/resultado.json;compact-screenshots/METRICAS-VISUAIS.json','Quadro/Financeiro/Documentos não têm nesta missão a mesma matriz visual completa. Browser sintético não é UAT autenticada em produção.'),
(10,'ASSINCRONIA','PARCIAL','Dois novos problemas em documentos; P2 anterior de Compras preservado. Sessão e stale/cancel nos painéis preparados passaram.','EVIDENCIAS-DOCUMENTOS-CONTEXTO.json;REGISTO-REGRESSOES.json','Trocas de mês/pessoa/aba, todas as combinações de latência e cache ainda requerem expansão. Não concluir bypass de tenant a partir de troca de contexto.'),
(11,'BRANCHES','CONCLUÍDA','Seis refs locais comparadas; branches Financeiro/FaseB/Planeamento mantidas independentes.','COMPARACAO-BRANCHES.csv','Comparação estática/ancestralidade não certifica integração futura; sem fetch/merge/deploy.'),
(12,'AUTO-REVISAO','EM EXECUÇÃO','Chaves originais203 preservadas; contagens Node separadas de resultados funcionais e de reproduções de falha.','../../validacao-profunda-20261014/CONTAGENS-203.json','Autorrevisão final, validação dos links e CSVs ainda pendentes.')]
for n,title,state,done,proof,limit in fronts:
 if n in [7,11]:continue
 doc(f'FRONTE-{n:02d}-{title}.md',f'# Frente {n} — {title}\n\nEstado: **{state}**.\n\n## Verificações\n\n{done}\n\n## Evidências\n\n{proof}\n\n## Limites e próximo passo\n\n{limit}\n\nNão houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.')
doc('FRONTE-07-TEE-ADMINISTRACAO.md','''# Frente 7 — TEE por administração direta: cenário sintético 128

Estado: estudo conceptual concluído; nenhuma implementação. A obra e todos os valores abaixo são sintéticos, sem acesso à Obra128 real.

## Separação obrigatória

| Camada | Exemplo sintético | Fonte/controlo proposto |
|---|---|---|
| Estimativa | Custo previsto700; venda prevista1000 | Orçamento identificado; revisão própria |
| Autorização | Serviço autorizado com limite e descrição | Decisão comercial registada; não equivale a fatura |
| Trabalho realizado | 2 dias; intervalos e quantidades reais | Factos operacionais preservados e rastreáveis |
| Materiais reais | 80 | Documento/quantidade efetivamente aplicada |
| Equipamento real | 40 | Uso/contrato/unidade explícitos |
| Mão de obra real | Por apurar | Sem tarifa comprovada: NULL; nunca zero inferido |
| Custo conhecido | 120 parcial | Mostrar incompletude; custo total permanece pendente |
| Preço contratual final | Por decidir | Contrato/aditamento aprovado e vigência |
| Valor faturável | Pendente | Não copiar custo real, estimativa ou autorização para faturação |

## Percurso

Estimativa → aprovação com âmbito → registo diário por recurso/obra → revisão técnica → reconciliação dos custos comprovados → decisão de preço contratual → medição/faturação segundo contrato.

Interrupção e aumento de quantidade não podem reescrever factos anteriores. Cada alteração requer revisão, autor e motivo. Corrigir um recurso não apaga o registo original nem muda automaticamente o preço do cliente.

## Proposta de apresentação administrativa

- Cabeçalho: TEE/obra/estado comercial/revisão.
- Coluna Estimativa: custos/venda e fonte.
- Coluna Execução: dias, pessoas, materiais, equipamento e documentos.
- Coluna Reconciliação: custo conhecido, parcelas pendentes, custo total por confirmar.
- Coluna Comercial: preço contratual e faturável, separados e pendentes quando necessário.
- Histórico: revisões e autorizações; referências aos factos, sem tarifas RH expostas à equipa técnica.

## Decisões necessárias

Quem aprova o preço final; como o contrato prevê administração direta; critérios de afetação de equipamento/transporte; tratamento comercial de interrupções e excedentes. Nenhuma inferência automática de salário/tarifa. Não foi criado writer, tabela, ecrã, migration ou cálculo salarial.
''')
with(Q/'COBERTURA-REAL.csv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.DictWriter(f,fieldnames=['frente','nome','estado','executado','evidencia','limite_proximo_passo']);w.writeheader();w.writerows(dict(zip(w.fieldnames,x))for x in fronts)
doc('INDICE-EXECUCAO.md','# Engenharia de qualidade — índice em execução\n\n'+ '\n'.join(f'- Frente{n:02d}: {title} — {state}'for n,title,state,*_ in fronts)+'\n\nVer COBERTURA-REAL.csv para provas/limites. Esta é uma execução parcial; frentes com trabalho independente pendente continuam na fila. Não chamar todas as frentes concluídas por existir um relatório.')
doc('RETOMA.md','''# Retoma da engenharia de qualidade

Branch codex/validacao-profunda-203-20261014; checkpoint local c4799aa contém primeira bateria. Manter produção e produto intactos. Consultar CONTROLO-EXECUCAO-NOTURNA.md na pasta validacao-profunda-20261014.

Próximos: ampliar estados das interfaces/importadores e invariantes restantes; segunda passagem económica em execução; consolidar achados sem duplicar N-FOR/N-FIN anteriores; validar links/contagens e congelar um novo checkpoint local.

24 pares dependem de Auth/Storage locais e não foram certificados por mocks. PostgREST funciona com QUADRO_PG_BIN no PATH do processo. A tentativa anterior de encerrar PID foi rejeitada; não repetir essa ação. O harness corrigido encerra apenas o child que ele próprio cria. Nenhum SQL real/push/merge/deploy.
''')
print('12 frentes com estado explícito; nenhuma cobertura completa inventada.')
