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
