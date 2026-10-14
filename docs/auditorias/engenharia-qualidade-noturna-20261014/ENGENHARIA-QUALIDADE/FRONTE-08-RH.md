# Frente 8 — RH

Estado: **PARCIAL**.

## Verificações

Regressão cumulativa AD15/14/13/03 e HR27–31; 72 pares adicionais por perfil e6 casos de identidade;370 contagens Node na regressão cumulativa; não somar como cenários únicos.

## Evidências

../../validacao-profunda-20261014/RESULTADO-RH-LOCAL.txt;../../validacao-profunda-20261014/EVIDENCIAS-HORAS-PERFIS.json

## Limites e próximo passo

Tabelas seed sintéticas não equivalem a todos os percursos de cadastro/importação/RH. FP28/29 preservados em standby.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Writer RH nativo e privacidade

Cinco cenários adicionais com funções capturadas reais, sem fn_e_admin=true: preview sem escrita; alteração e auditoria única; versão antiga recusada por P0001/Cadastro alterado entretanto; repetição na versão atual sem alteração; lote misto cancelado sem primeira linha; leitura RH confidencial recusada a Diretor/Adjunto/Preparador. Os dois primeiros percursos são agregados em um cenário; total5 cenários/9 contagens Node PASS.

Prova: EVIDENCIAS-RH-WRITER-NATIVO.json e logs/RH-WRITER-NATIVO.txt. A primeira execução mascarava mensagens por RESET ROLE em transação abortada; arquivos RH-FIRST-INCONCLUSIVE documentam esse limite e não contam como aprovação do motivo. Códigos/mensagens específicos são exigidos agora. Não foi lido o Excel real opcional de47 linhas.

Limites: snapshot histórico/hotfix reconstruído, defaults/constraints/triggers parciais, sem login hospedado. O fluxo não substitui HR38 nem a auditoria de todos os caminhos de tarifa. Cadastro/contrato/permanências semeados não equivalem a criação/desativação real de contas Auth.
