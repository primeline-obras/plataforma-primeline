# Comparação do diretório — 23/09/2026

- Indicador: Total
- Cadastros na plataforma: 622
- Linhas de fornecedores no Excel: 776
- Designações normalizadas: 737
- Correspondências seguras: 36
- Cadastros com campos vazios a completar: 7
- Novos candidatos seguros: 272
- Nomes para revisão: 429
- Linhas sem nome excluídas: 103
- Fonte SHA256: bfef7e7a88189beeaed16d9d2a97e754464700b9616e90425b97d7f07075d897
- Estado: Preparado; não executado em produção
- Critérios: Só vazios; sem fusão, sem renomear, sem deduzir NIF, tipo, avaliação ou zona operacional.
- Notas: Contacto secundário/localidade/atividade/observações preservados nas notas dos novos registos. Notas existentes não são substituídas.
- Limite: O Excel não contém NIF; ausência de coincidência não prova identidade jurídica. Casos semelhantes ficam retidos.

Os nomes para revisão não constam do SQL de gravação. O relatório XLSX inclui os candidatos e a folha/linha de origem.

1. Executar primeiro o SQL terminado em _previsualizar.sql (não grava cadastros).
2. Conferir os totais e conflitos.
3. Executar _aplicar.sql para gravar o lote seguro numa transação única.
4. Repetir a pré-visualização: novos_previstos e cadastros_a_completar devem ficar a zero.

Alterações ficam em public.fornecedores_excel_historico (acesso administrativo SQL; sem leitura direta para utilizadores da app). Não altera faturas, subempreitadas, aliases ou ligações existentes. Novos parceiros sem tipo são apresentados como Tipo por classificar.
