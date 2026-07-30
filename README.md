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
