# Frente 5 — FINANCEIRO

Estado: **PARCIAL**.

## Verificações

Recebimento real via REST: parcelas100+400 =500, saldo43, replay sem terceiro movimento; importação repetida mantém um ajuste.

## Evidências

../../validacao-profunda-20261014/EVIDENCIAS-REST-SEGUNDA-PASSAGEM.json;EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json

## Limites e próximo passo

Casos de adiantamento/retenção/crédito/anulação/investimento e distribuições contratuais devem ser ampliados; P1 anteriores preservados.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Orçamento, TEE e distribuição mensal — nova prova sintética

EVIDENCIAS-MAPA-CONTRATOS-DISTRIBUICAO.json e logs/MAPA-CONTRATOS-DISTRIBUICAO.txt exercitam o consumidor real src/financial-map.js. Uma cópia em memória expõe buildRows; nenhum ficheiro de produto foi alterado.

Cinco controlos PASS:
- PV1200, PC600, margem600 em12meses:50/mês.
- Prorrogação para24meses:25/mês;300 no primeiro ano e300 no segundo.
- Mês fechado sem movimento: zero REAL, não50 estimado.
- Ajuste explícito zero: final0, referência calculada50 preservada.
- TEE aprovado+100 e-20: líquido80; pendentes/recusados não entram no filtro real. Composição preserva sinal.

Diagnóstico adicional ligado ao achado ANTERIOR N-FIN-07: com duas linhas contratuais válidas como entrada do consumidor, ordenadas atual→antiga, o Mapa escolhe PV900 da antiga; o seletor do dashboard escolhe PV1200 da atual. A assertion de reprodução passou, mas o resultado funcional é FAIL_EXISTING. Não é um sexto controlo funcional aprovado, nem novo achado independente. Não certifica que o writer aceita duplicar contratos ou que estes dados existem em produção.

Adiantamento, retenção, medição, crédito e anulação ainda requerem os respetivos estados/writers; esta prova não os substitui.

## Autos — retenção, adiantamento e parcial

EVIDENCIAS-AUTOS-DEDUCOES-CLIENTE.json:5 controlos cliente PASS. Auto contratual1000-50-100=850; adicional recusa dedução antes do transporte; adicional com retenção sem dedução=950; fluxo configurado envia componentes e usa representação devolvida. Indicador totalClientBilling soma adiantamento100 e dois autos300+550=950. Não confundir faturação acumulada com recebimento.

A fixture usa o handler real submitMeasurement extraído em memória, sem carregar app.js inteiro nem ficheiros reais. API preparada não demonstra RLS, transação ou coluna gerada do PostgreSQL.

## Estados de falha e recuperação

Browser com aplicação real e transporte sintético:3larguras1440/768/390 × carregamento/503/recuperação=9capturas. Aviso DADOS INDISPONÍVEIS preserva mensagem, nova tentativa bem sucedida remove o aviso. Sem console/pageerror. Inspecionadas capturas tablet de erro e mobile de recuperação.

Durante o erro inicial a tabela/estrutura continua visível com valores por omissão, incluindo0. O PASS refere-se à transição e ao aviso; não certifica que esses zeros sejam factos financeiros conhecidos. Sem alterar o contrato de custo desconhecido. Tipografia de substituição e clique de navegação via DOM limitam a prova visual/tátil.

Atualização do teste de autos:6 contagens Node, das quais5 controlos PASS e1 reprodução FAIL_EXISTING ligada a N-FIN-02. Rascunho850 + adiantamento100 já produz indicador950 sem emissão de fatura. Nenhum novo ID contado; a regra/fonte de faturação continua pendente.
