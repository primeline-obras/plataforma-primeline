# Retoma da engenharia de qualidade

Branch codex/validacao-profunda-203-20261014; checkpoint local 9e28c96 contém primeira bateria. Manter produção e produto intactos. Consultar CONTROLO-EXECUCAO-NOTURNA.md na pasta validacao-profunda-20261014.

Próximos: ampliar estados das interfaces/importadores e invariantes restantes; segunda passagem económica em execução; consolidar achados sem duplicar N-FOR/N-FIN anteriores; validar links/contagens e congelar um novo checkpoint local.

24 pares dependem de Auth/Storage locais e não foram certificados por mocks. PostgREST funciona com QUADRO_PG_BIN no PATH do processo. A tentativa anterior de encerrar PID foi rejeitada; não repetir essa ação. O harness corrigido encerra apenas o child que ele próprio cria. Nenhum SQL real/push/merge/deploy.
