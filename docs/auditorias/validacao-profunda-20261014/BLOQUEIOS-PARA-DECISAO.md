# Bloqueios para decisão

## Serviços locais

DEPENDÊNCIA TÉCNICA: Login requer GoTrue real local; Documento/Download requerem Storage local, Auth e políticas correspondentes. Docker, Podman e Supabase CLI não foram encontrados no PATH. PostgreSQL e PostgREST locais não substituem o fluxo de login nem o serviço de bytes. 24 pares ficam BLOQUEADO, sem falso PASS. Não usar produção nem mocks de permissões para os certificar.

## Encerramento do harness REST

A primeira tentativa ficou presa no teardown após saída do processo PostgREST. A revisão automática rejeitou encerrar o PID 15136 porque a evidência apresentada não identificava o alvo com segurança. Não repetir nem contornar a ação rejeitada. O teardown do teste novo foi corrigido e uma execução independente pode seguir; o processo anterior não foi encerrado por esta tarefa. DEPENDÊNCIA TÉCNICA para limpeza desse processo, sem impacto demonstrado no produto.

## Decisões anteriores preservadas

AGUARDA DECISÃO: mitigação HR38, conceitos financeiros e TEE pendentes do backlog anterior; nenhuma mudança de contrato realizada. FALTOU recusa Gestão no código atual por exigir literalmente Encarregado; confrontar com regra global de superutilizador funcional antes de alterar. Esta verificação de contrato não se converte automaticamente em autorização para mudar a regra.

## Fidelidade tipográfica local

DEPENDÊNCIA TÉCNICA: fontes Google bloqueadas pelo isolamento. CDP confirmou fallback; geometria local não certifica produção. Ver LIMITE-TIPOGRAFIA.md. Não impede testes de dados, autorização e semântica acessível.
