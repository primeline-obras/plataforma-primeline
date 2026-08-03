# PRIMELINE — Frontend de Faturas

Primeiro módulo da plataforma de gestão de obras. É uma aplicação web sem processo
de compilação e funciona em modo de demonstração enquanto não existirem credenciais.

## Configurar o Supabase

Editar `config.js` e preencher apenas:

```js
window.PRIMELINE_CONFIG = {
  supabaseUrl: "https://SEU-PROJETO.supabase.co",
  supabaseAnonKey: "SUA-ANON-PUBLIC-KEY",
};
```

Nunca colocar a `service_role key` no frontend.

## Executar localmente

Na pasta do projeto:

```powershell
python -m http.server 4173 --bind 127.0.0.1
```

Abrir `http://127.0.0.1:4173`.

## Autenticação e RLS

O frontend autentica por email e palavra-passe através do Supabase Auth. A sessão é
guardada localmente e o `access_token` do utilizador é enviado nas chamadas REST.

Antes de utilizar a aplicação com dados reais, executar
`supabase/rls_authenticated.sql` no SQL Editor do Supabase com uma conta owner. O
script:

- não concede qualquer acesso ao papel `anon`;
- permite ao papel `authenticated` ler as quatro tabelas usadas;
- permite inserir faturas pendentes;
- permite aprovar ou recusar faturas que ainda estejam pendentes.

## Operações utilizadas

- Leitura: `obras`, `fornecedores`, `subempreitadas` e `faturas`.
- Inserção: `faturas`.
- Atualização: `faturas.estado_aprovacao` e `faturas.data_aprovacao`.
- Não executa operações de schema.

É necessário criar os utilizadores no Supabase Auth antes do primeiro login.

O login inclui recuperação de palavra-passe. No Supabase, adicione
`https://plataforma-primeline.pages.dev/reset-password` à lista de Redirect URLs em
Authentication → URL Configuration.

## PDFs de faturas

O formulário permite anexar e pré-visualizar PDFs até 10 MB. Os documentos são
guardados no bucket privado `faturas` e `faturas.arquivo_url` recebe apenas o caminho
interno do objeto. O bucket deve aceitar `application/pdf` e ter políticas de
`insert` e `select` para `authenticated`.

Ao anexar um PDF com texto pesquisável, o navegador tenta extrair número do
documento, data, valor e fornecedor. O fornecedor só é preenchido quando o nome
corresponde exatamente a um registo já existente; nunca são criados fornecedores
automaticamente. A subempreitada nunca é pré-selecionada.

## Módulo Obras

A aba Obras apresenta a lista de obras e um detalhe com contrato, fases,
subempreitadas e autos de medição. Antes de usar os detalhes em produção, execute
`supabase/rls_obras_authenticated.sql` no SQL Editor para permitir as leituras ao
papel `authenticated`, mantendo `anon` sem acesso.

O separador Subempreitadas também apresenta pagamentos acumulados e consultas ainda
por adjudicar. Execute `supabase/rls_subempreitadas_authenticated.sql` para permitir
essas duas leituras ao papel `authenticated`.

O fluxo de autos de medição, faturação ao cliente e recebimentos é ativado pelo
conteúdo de `supabase/autos_faturacao_workflow.sql`. A migração cria a relação entre
autos e faturas, permite associar os PDFs através de `documentos` e mantém o papel
`anon` sem acesso.

## Planeamento detalhado

Executar `supabase/planeamento_detalhado.sql` no SQL Editor para criar as tarefas de
segundo nível, as dependências e as políticas de acesso. A migração impede
dependências circulares, recalcula atrasos `fim_inicio` apenas para a frente e
identifica visualmente as tarefas alteradas automaticamente.

Antes de importar planeamentos reais, suspender o trigger de recálculo e carregar os
dados:

```sql
alter table public.planeamento_itens disable trigger trg_recalcular_planeamento;
```

Depois executar obrigatoriamente:

```sql
select * from public.fn_auditar_ciclos_planeamento();
```

Todos os ciclos encontrados devem ser corrigidos. O trigger só pode ser reativado
quando a auditoria devolver zero linhas:

```sql
alter table public.planeamento_itens enable trigger trg_recalcular_planeamento;
```

## Mapas comparativos e subempreiteiros

Executar `supabase/subempreitadas_mapa_comparativo_workflow.sql` no SQL Editor para
ativar a adjudicação de candidatos, as permissões de escrita por obra, a sincronização
com o planeamento detalhado e a conclusão com avaliação obrigatória. O limite de
contrato está centralizado em `fn_limite_contrato_subempreitada()` e é atualmente
5.000 €.

Depois da migração, executar
`supabase/teste_bloqueio_conclusao_sem_avaliacao.sql`. O teste tenta concluir, sem
avaliação, uma subempreitada elegível e reverte qualquer alteração. O resultado
esperado é o aviso `TESTE PASSOU` e os dois triggers apresentados como ativos.

Para que o diretório geral mostre o histórico transversal de todas as obras a
qualquer utilizador autenticado, executar também
`supabase/rls_diretorio_subempreiteiros_authenticated.sql`. Este script concede
apenas leitura de `subempreitadas` e `avaliacoes_subempreiteiro`; não altera as
permissões de escrita nem concede acesso ao papel `anon`.

## Documentos por obra

Executar `supabase/documentos_obra_workflow.sql` no SQL Editor para ativar a aba
Documentos dentro de cada obra. O script mantém o bucket privado, cria o bucket
`documentos` com limite de 25 MB e protege tanto os metadados como os objetos de
Storage através de `fn_pode_ver_obra(obra_id)` e `fn_pode_editar_obra(obra_id)`.
O papel `anon` não recebe acesso.

As categorias disponíveis incluem contrato, orçamento, plantas/projeto, desenhos de
preparação, atas de reunião, PDEs/RFIs, PAMEs, licenças, planeamento detalhado e
outros documentos.

## Matriz final de permissões

Executar `supabase/rls_permissoes_finais.sql` integralmente no SQL Editor, com uma
conta owner, depois das migrações funcionais acima. O script substitui as políticas
RLS antigas das tabelas usadas pela aplicação, inclui `gerencia` no acesso total,
separa leitura e escrita por papel e expõe as operações sensíveis de faturas pelas
funções `fn_decidir_fatura` e `fn_marcar_fatura_paga`.

Depois, executar `supabase/auditoria_rls_permissoes_finais.sql`. A auditoria é apenas
de leitura e confirma funções, políticas, grants e a existência de contas para a
validação manual de cada papel.

Para permitir ao papel Financeiro consultar, sem editar, Subempreitadas, TEEs e
Planeamento de todas as obras numa base que já tenha a matriz final instalada,
executar também `supabase/rls_financeiro_detalhe_obras.sql`. A migração substitui
apenas políticas de leitura; as políticas de escrita continuam limitadas à equipa
responsável pela obra.

## Linhas especiais no Quadro de Pessoal

No modo de edição do Quadro de Pessoal, o botão `Nova linha` permite acrescentar
uma obra existente ou uma linha livre dos tipos Garantia e Pontual. As linhas
livres usam `quadro_pessoal_alocacao.tipo_alocacao` e `descricao_livre`, podem ser
renomeadas diretamente no quadro e ficam persistidas quando recebem a primeira
alocação. Não representam uma obra nem apresentam informação financeira.

## Segurança, índices e preços de materiais

Executar `supabase/rls_seguranca_indices_precos.sql` no SQL Editor depois de as
tabelas funcionais terem sido criadas. O script:

- protege incidentes e inspeções através de `fn_pode_ver_obra` e
  `fn_pode_editar_obra`;
- reserva EPI's a Administrativo/Gerência;
- permite consultar os índices automáticos de desenhos e PDEs;
- protege os artigos de faturas de material pela obra da respetiva fatura;
- acrescenta `faturas_itens.unidade`, a única coluna pedida pelo formulário que
  ainda não existia no schema confirmado.

O upload de Desenhos e PDEs grava `numero_documento` e `revisao` em
`documentos_obra`; o trigger existente `fn_sincronizar_indice_documento` continua
a ser o único responsável pela sincronização com `desenhos` e `rfis`.

Nas faturas de Material, a leitura do PDF tenta também reconhecer a tabela de
artigos pelas posições dos cabeçalhos e colunas. As linhas encontradas são apenas
sugestões editáveis; o Administrativo confirma-as antes de gravar em
`faturas_itens`. O comparativo não usa catálogo: pesquisa parcialmente com
`ILIKE` em `faturas_itens.designacao` e `despesas_estaleiro.designacao`, agrupando
os resultados por fornecedor.

## Documentos de RH e viaturas

Executar `supabase/documentos_rh_ativos.sql` no SQL Editor, depois da matriz final
de permissões. A migração reutiliza a tabela `documentos` e o bucket privado
`documentos`, permite tipos documentais em texto livre e reserva leitura/escrita
de ficheiros de colaboradores e viaturas a Administrativo/Gerência.

## Dados reais de Equipa

Executar `supabase/importar_dados_reais_equipa.sql` no SQL Editor para atualizar,
de forma idempotente, as 21 viaturas, os 34 registos atuais de medicina do trabalho
e as respetivas datas de nascimento. O script não cria colaboradores e cancela toda
a transação se algum UUID confirmado pela auditoria não existir ou estiver inativo. No final deve devolver
`34 / 34 / 21 / 21 / 34` nas cinco colunas de confirmação.

Executar também `supabase/viaturas_prazos_edicao.sql` para distinguir a data da
última revisão (`data_revisao`) da próxima revisão programada
(`data_proxima_revisao`). A área Equipa mostra seguro, inspeção e revisão
separadamente e permite a Administrativo/Gerência atualizar estes dados.

Os objetos são guardados sob `rh/{entidade_tipo}/{entidade_id}/...`. Documentos
com validade geram um alerta para `administrativo`, com gatilho 30 dias antes da
data indicada. A Visão Geral apresenta apenas alertas cuja data de gatilho já
tenha chegado.
