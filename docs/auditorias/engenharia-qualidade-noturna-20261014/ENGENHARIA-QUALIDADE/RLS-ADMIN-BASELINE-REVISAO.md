# Policies administrativas — inventário de candidatos

RLS-ADMIN-BASELINE-CANDIDATAS.csv é uma triagem estática da captura20261004. Não classifica todas as linhas como vulnerabilidades atuais e não acrescenta um P1 por tabela.

A policy permissiva com fn_e_admin() pode dar acesso por papel sem relação com a empresa da linha. A composição efetiva depende também de grants de coluna/tabela, policies restritivas, definição dos helpers e alterações posteriores. Uma coluna obra_id/empresa_id é um ponto para análise; não prova sozinha o tenant legítimo de dados antigos.

Documentos_obra possui uma prova local concreta separada. As restantes candidatas necessitam comparação por pacote e, futuramente, catálogo autorizado. Não aplicar um fecho global que remova permissões legítimas de Gestão/Gerência/Administrativo.

Recomendação: para cada candidata, identificar fonte factual do tenant e policy efetiva; separar dicionários globais; distinguir concessão funcional de âmbito; testar utilizador ativo, empresa própria/estrangeira e relação revogada; manter fail-closed para linhas ambíguas. Não fazer backfill pelo utilizador criador.

Os dados da captura são metadados do schema. Não foram lidas linhas reais nem criado novo teste de acesso em produção.
