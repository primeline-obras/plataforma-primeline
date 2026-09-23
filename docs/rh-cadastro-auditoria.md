# Cadastro de colaboradores / RH — diagnóstico de 23-09-2026

Estado: implementação local preparada na branch agent/rh-cadastro-importacao.
Migração, publicação e validação em produção ainda pendentes.

## Estrutura confirmada pelo SQL de produção

- Colaboradores: nome, função, nível, valor/hora, admissão, nascimento, saída,
  NIF, email, contacto, morada, código RH, observações e permite_multiplas_obras.
- Conformidade: `registo_trabalhador_ok`, `seguro_ok`, `seguranca_social_ok`.
  São indicadores booleanos; não guardam o número de Segurança Social.
- Contratos: colaborador, tipo, início, fim previsto, estado e data de criação.
- Tipos permitidos: `a_prazo`, `tempo_indeterminado`.
- Estados permitidos: `ativo`, `renovado`, `encerrado`.

## Lacunas funcionais no código local

- A criação e edição não oferecem campos de contrato.
- A edição não apresenta os campos de conformidade existentes na criação.
- “N.º S.S.” está incorretamente associado a uma resposta Sim/Não.
- O código de criação usa nomes de conformidade diferentes dos confirmados na base.
- Não existe importação Excel de cadastro RH na interface analisada.
- A data de admissão vazia num cadastro existente é substituída por hoje no formulário:
  deve deixar de presumir essa data.

## Cadastro proposto

Um formulário e um botão Guardar, com secções de identificação/contactos,
vínculo/contrato, conformidade, observações e alocação inicial na criação.
NISS deve ser um campo textual protegido, separado do indicador de inscrição.
Documentos PDF complementam o cadastro; não substituem tipo e datas estruturadas.
Medicina e EPI devem manter os seus registos históricos nas áreas próprias.
Não recolher dados clínicos nem tornar dados adicionais obrigatórios sem necessidade.

Obrigatórios na criação: nome, função, admissão e alocação (obra ativa ou escritório).
O contrato pode ficar por preencher; ao registá-lo, tipo e início são obrigatórios,
e o fim previsto é obrigatório apenas para contrato a prazo.
Os restantes campos de identificação/contactos, nível, valor/hora, código RH,
NIF, NISS, nascimento, conformidade e notas são opcionais.
Data de saída é uma operação explícita no formulário, nunca no Excel.

## Importação proposta — primeira entrega

Gestão da Plataforma exporta um modelo pré-preenchido com ID e versão do cadastro.
Importação atualiza apenas colaboradores existentes, sem correspondência automática por nome.
Datas, valores, identificadores, contratos e conflitos devem ser validados no servidor.
Células vazias preservam dados; não há inativação nem mudança de alocação implícita.
Pré-visualização apresenta alterações por pessoa e campo, sem gravação.
Confirmação atómica, verificação de alterações concorrentes e auditoria de autor/valores.
Reimportação do mesmo ficheiro deve ser testada como sem alterações.

## Implementado nesta entrega

- Novo módulo `src/rh-cadastro.js`: formulário único, com dados carregados por RPC
  protegida antes de abrir, contrato ativo, histórico consultável, NISS e conformidade.
- Um Guardar grava cadastro/contrato na mesma transação e fecha o formulário.
- A aba Contratos permite abrir diretamente o cadastro para edição.
- Campos RH passam a usar os nomes reais `*_ok` da produção.
- NISS guardado em tabela própria sem acesso direto pelos papéis anon/authenticated.
- Modelo XLSX pré-preenchido, instruções, ID e versão do cadastro.
- Importação exclusiva de Gestão da Plataforma: até 1000 linhas, preview por campo,
  validação no servidor, preservação de vazios, proteção de empresa e versão,
  gravação atómica e auditoria com autor/antes/depois.
- Administrativo e Gerência podem editar individualmente; não importar Excel.
- Criação mantém alocação inicial, entrega EPI e consulta inicial quando preenchidas.
- Formulário em duas colunas no desktop e uma no telemóvel, sem scroll horizontal.

## Limites explícitos / pendências

- O Excel completa cadastros EXISTENTES. Não cria novos colaboradores nem importa PDFs.
- PDFs continuam no botão Documentos do colaborador; não há extração automática de contratos.
- Editar o contrato ativo é correção dos seus dados, auditada. Um fluxo dedicado
  de renovação/encerramento contratual continua pendente.
- Mudança para tempo indeterminado faz-se no formulário individual para limpar
  explicitamente o fim previsto. Excel vazio nunca apaga a data.
- EPI e medicina históricos continuam nas respetivas áreas; os campos de entrega/
  consulta inicial só aparecem na criação. Não importar datas repetidas como novos eventos.
- Não foram criados campos de salário mensal, subsídios, horário/regime, IBAN,
  documentos de identidade ou contacto de emergência. Confirmar necessidade e
  permissões antes de ampliar o conjunto de dados pessoais.
- Os alertas contratuais existentes só geram avisos em dias de antecedência exatos.
  A revisão de alertas já pendentes após corrigir datas e dos contratos inseridos
  depois desses limiares continua pendente; não declarar essa integração validada.
- Não foram alterados dados de produção.

## Evidências de teste local

- 38 testes passaram no conjunto dirigido de RH/quadro de pessoal.
- Inclui PostgreSQL via PGlite com estrutura de colaboradores/contratos reproduzida
  do SQL enviado, migração repetida, preview sem gravação, lote revertido em caso
  de erro, reimportação sem alterações, contrato inválido sem edição parcial,
  histórico, autor de auditoria, isolamento de empresa e permissões reais de roles.
- O teste PostgreSQL usa substitutos das funções de sessão; não substitui RLS
  e autenticação de uma sessão real em produção.
- Chromium isolado, API simulada: campos preservados, um Guardar, fecho do formulário,
  ficheiro XLSX real, preview, confirmar e reimportar; 1366px e 390px sem overflow.
- Revisão visual encontrou e corrigiu notas desalinhadas e margens da importação.
- Testes:
  `RH_TEST_DEPS=/pasta/dependencias node --test tests/rh-cadastro.test.mjs`
  (dependências de teste: @electric-sql/pglite 0.3.14 e jsdom 26.1.0).
  Browser: `RH_TEST_DEPS=/pasta/dependencias node tests/rh-cadastro-browser.mjs`
  (playwright 1.51.1, Chromium e xlsx.full.min.js 0.20.3 na pasta de dependências).
  Sem RH_TEST_DEPS, os testes de base/DOM ficam explicitamente skipped.

## Ordem de publicação

1. Copiar `supabase/rh_cadastro_importacao.sql` e executar no SQL Editor do Supabase.
   Não executar SQL diretamente no PowerShell.
2. Confirmar a existência das RPCs com a consulta no final da migração.
3. Enviar a branch, criar PR para main e rever/mesclar.
4. Testar em produção como Gestão da Plataforma e Administrativo; validar também
   que o diretor/encarregado não conseguem obter NISS pelas novas RPCs.
5. Exportar modelo, alterar uma pessoa conhecida, pré-visualizar, confirmar e repetir:
   segunda execução deve indicar zero a atualizar. Conferir contrato e histórico.

## Validações necessárias antes da publicação

- Criar e editar preservando todos os campos; guardar fecha o formulário.
- Manter histórico de contratos; não criar contratos ativos duplicados.
- Administrativo edita cadastro; importação reservada à Gestão da Plataforma.
- Utilizadores técnicos não recebem dados privados nem podem escrever via RPC.
- Empresa e obra de alocação conferidas no servidor.
- Excel: vazios, datas inválidas, IDs repetidos, conflito de versão, reimportação,
  falha numa linha sem gravação parcial e tentativa de acesso a outra empresa.
- Conferir reflexos no quadro de pessoal, ponto, férias, contratos e alertas.
- Testes SQL e de navegador; não considerar apenas testes de texto como prova funcional.
