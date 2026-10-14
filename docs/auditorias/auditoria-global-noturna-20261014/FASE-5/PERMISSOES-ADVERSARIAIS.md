# Permissões defensivas por perfil

Provas sintéticas, sem SQL hospedado e sem técnicas novas de exploração. Oito papéis reais preservados.

RH7-ROLES executa reader/import como authenticated, com auth.uid de fixture e utilizadores ativos por empresa. Gestão/Gerência/Admin leem; só Gestão importa; Financeiro/técnicos/Encarregado não recebem cadastro RH completo; outra empresa retorna0; inativo rejeitado. Cadastro/import usam fn_rh_empresa, independente de helperadmin legado.

Folha/harness: caller/tenant/obra e revisões; ator inativo após lock e mudança de empresa recusados; mesma request concorrente idempotente; outra obra/empresa recusa sem parcial. TASK-ROLES: Adjunto confirma; Preparador não; revisão antiga e replay revogado recusados. ROLE financeiro monetário não foi testado por esta suite: helpers foram stubs permitidos.

Frontend8: insertInvoices,approveInvoices,payInvoices,editWork seguem accessFor; Encarregado não se torna Gerência com isAdmin=true. Teste de booleans não certifica backend. Quadro mantém leitura do Encarregado; não concedemos tarifa/preços/custos novos.

JWT/Auth hospedado e identidade inválida criptográfica não exercitados nesta extensão; testes de troca/401/403 usam respostas sintéticas. A prova PostgREST anterior permanece histórica, não novo resultado. Não marcar estes itens PASS ou BLOQUEADO por proteção inexistente; são NÃO EXECUTADOS/fora da missão real.

Não encontrado bloqueio de segurança essencial nos testes locais concluídos. Qualquer lacuna de fixture/contrato está separada da proibição de produção.
