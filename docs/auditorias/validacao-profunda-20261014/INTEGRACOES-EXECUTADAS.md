# Integrações executadas

| Percurso | Prova | Limite |
|---|---|---|
| Preview numérico → RPC Mapa Financeiro → ajuste mensal | EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json | Base local; entradas inválidas convertidas persistem |
| XLSX binário → SheetJS → preview → writer → ajuste | Mesmo ficheiro, FIN-BINARY-DUPLICATE-UNKNOWN | Contradição de duas linhas120 resulta num ajuste200 |
| JWT sintético → PostgREST → recebimento → ledger/saldo | EVIDENCIAS-REST-SEGUNDA-PASSAGEM.json | Não é login GoTrue nem produção |
| Plano/FALTOU → factos → conferência/custos/alertas | EVIDENCIAS-HORAS-PERFIS.json;RESULTADO-RH-LOCAL.txt | Fixture cumulativa; cadastro inicialmente semeado |
| Documento → carregamento e contexto | EVIDENCIAS-DOCUMENTOS-CONTEXTO.json | Cliente real/transporte sintético; Storage não certificado |
| Recursos → TEE → preço final | FRONTE-07-TEE-ADMINISTRACAO.md | Proposta conceptual; ligação granular não implementada |

As integrações não ligadas permanecem por verificar. Um writer/backend validado não certifica automaticamente todos os consumidores, exports, anexos e estados.
