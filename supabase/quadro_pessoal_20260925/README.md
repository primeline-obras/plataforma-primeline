# Quadro de Pessoal — entrega local

Preparação iniciada em 25/09 e retomada em 28/09/2026. Nenhum destes SQLs foi executado em produção pelo agente.

## Ordem de execução manual, após autorização

1. `00_precheck_leitura.sql`: somente leitura; conferir duplicados, versão e políticas inesperadas. Não prosseguir se bloquear.
2. `00_regras_movimentacoes.sql`: migração funcional, transacional. Reutiliza o histórico e restringe escrita. Aplicar primeiro em staging com o esquema real. Requer PostgreSQL 15+ e a estrutura histórica de `quadro_pessoal_operacional_relatorio.sql` já instalada. Não reaplicar esse SQL antigo depois deste.
3. `01_prevalidacao.sql`: somente leitura; exigir 95 posições, zero bloqueios, `PRONTO`. O manifesto é fixo, não ajustado silenciosamente.
4. `02_backup_gravacao.sql`: backup completo dos cadastros/alocações/ausências/obras/responsabilidades/movimentos da empresa, inserção apenas das posições em falta e correção de João Afonso. Tudo numa transação. Não faz DELETE/UPDATE de alocações. Backup com acesso negado à aplicação.
5. `03_conferencia.sql`: somente leitura; executar antes de fazer ajustes manuais. Esperado `CONCLUIDO`, 95 posições e verificações verdadeiras. Zero linhas significa que o lote não foi encontrado, não sucesso.
6. Publicar o frontend **apenas quando autorizado**, depois da migração 00. Testar com contas reais de Gestão, ADM, Encarregado e DO. Não publicar frontend antes da RPC existir.

Se uma execução abortar, não repetir à força nem retirar proteções. Num cliente SQL que mantenha a transação aberta após erro, executar ROLLBACK antes de nova consulta. Investigar o erro primeiro.

## Manifesto e limites

Fonte: `Supabase Snippet Untitled query (18).csv`, resultado da pré-visualização anterior com 100 posições. Foram retiradas exclusivamente as cinco posições do ID `ae4df908-5847-4fcd-bf14-f0fbb441cb74` (Wanderson). O manifesto versionado contém 95 datas/alocações, 19 pares pessoa/obra e 16 pessoas.

- Somente 28/09–02/10/2026; período `dia_inteiro`.
- João Afonso `81a195a3-d75f-4504-87a7-4060078b9f9e`: Servente → Pedreiro, mesmo ID.
- Nenhuma alteração de `permite_multiplas_obras` — incluindo Helder.
- Nenhuma alteração em `obra_responsaveis`.
- Manoel não consta do manifesto. Não é criado nem associado.
- Férias de Wanderson e demais ausências preservadas integralmente.
- Outras obras simultâneas e todas as alocações existentes são preservadas.
- Reexecução só é aceite se o lote já gravado permanecer exatamente inalterado; não sobrescreve backup.

## Regras funcionais

Gestão da Plataforma (`gestao_plataforma`) e ADM (`administrativo`) gerem o quadro. Gerência não ganha escrita por herdar poderes de outros módulos. Encarregado só usa `fn_quadro_operar('minha_obra',...)` com destino validado pelas responsabilidades existentes, perfil ativo e empresa.

Uma origem inequívoca é movida através de UPDATE do mesmo ID; não há DELETE seguido de POST. Nenhuma origem cria apenas destino. Múltiplas origens, sobreposição parcial ou destino já existente bloqueiam sem remover nada. A pré-visualização não grava; a confirmação compara a versão e revalida permissões/ausências. Não propaga para outras datas.

O trigger de segurança também atua sobre escritores SECURITY DEFINER antigos. A RPC usa autorização interna transitória inacessível ao cliente; não usa uma flag/GUC configurável pelo cliente como privilégio. SQL administrativo com identidade de banco privilegiada continua possível; não é confundido com permissões da aplicação.

O histórico existente recebe snapshots antes/depois, perfil e nome do autor, nome do colaborador, tipo de ação e IDs de origem/destino. Eventos antigos não recebem dados inventados. O histórico é inserido na mesma transação; qualquer falha anula o movimento. A aplicação não recebe escrita no histórico. O Encarregado consulta apenas eventos relacionados com as suas obras atualmente autorizadas.

Foi preservada a regra existente de ausência: qualquer registo nessa data bloqueia. Não foi alterada a interpretação de estados de ausência nem qualquer regra do MGO. A revisão de descrições administrativas atua apenas sobre IDs carregados, com um evento/transação por registo, não renomeia eventos históricos.

## Testes locais reproduzíveis

Node 22.16.0. Instalar dependências só para testes:

```sh
npm install --prefix tests/quadro-runtime
node --test tests/workforce-v3-database.test.mjs tests/workforce-v3-week.test.mjs tests/workforce-v3-interface.test.mjs tests/workforce-v3-dom.test.mjs
```

PGlite executa PostgreSQL em memória, com dados sintéticos e o manifesto autorizado. Não usa config.js, URL ou credenciais da produção. JSDOM testa o formulário, não o aspeto visual num browser real.

As variáveis opcionais `QUADRO_PGLITE` e `QUADRO_JSDOM` aceitam caminhos absolutos para os módulos de teste instalados fora do repositório. Foram usadas nesta sessão para manter dependências em `/tmp`.

## Pendências antes de produção

- Confirmar precheck/esquema real e ensaiar migração em staging; o teste local usa um esquema mínimo baseado nos ficheiros existentes.
- Validar visualmente e com as contas reais após publicação autorizada. Não foi efetuado deploy, commit nem push pelo agente.
- Teste local não simula várias conexões concorrentes reais; proteção SQL usa lock por colaborador, comparação de versão e índice UNIQUE com NULLS NOT DISTINCT.
- Guardar/copiar esta pasta e o handoff para outro computador. Ficheiros não commitados não chegam ao GitHub automaticamente.
