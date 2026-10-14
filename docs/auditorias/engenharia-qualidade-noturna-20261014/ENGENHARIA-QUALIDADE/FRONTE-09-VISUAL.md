# Frente 9 — VISUAL

Estado: **PARCIAL**.

## Verificações

170 checks em 768×1024,1024×768,820×1180,375×812,1440×900; mais34 em1280×720. Screenshots inspecionadas explicitamente em tablet/mobile.

## Evidências

screenshots/resultado.json;compact-screenshots/METRICAS-VISUAIS.json

## Limites e próximo passo

Quadro/Financeiro/Documentos não têm nesta missão a mesma matriz visual completa. Browser sintético não é UAT autenticada em produção.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Teclado e nomes acessíveis

21 vistas ×3 larguras =63 inventários adicionais. Filtros excluem opacity/visibility e ancestrais inert/aria-hidden. Sem tabindex positivo;35 passos Tab sem foco invisível e sem erro JS. Menu móvel e seletor de obra não têm nome acessível programático (DEEP-OBS-04). A árvore ARIA confirma botão sem nome no topo. Isto não é certificação WCAG nem auditoria de contraste completa.

Inspeção visual planning-width-768.png revela cabeçalho/seletor parcialmente cortado no estado sem obras. scrollWidth global não acusou overflow: o recorte pode mascarar o problema. Classificação provisória de layout, por confirmar também com obra sintética preenchida; não é prova de indisponibilidade funcional em produção. Financeiro/Documentos tiveram45 capturas adicionais com CSS completo e sem overflow nessa bateria; não confundir com cobertura integral de formulários.

## Diálogo Obra

Quatro viewports (1440/768/1024/390): abrir/preencher/cancelar sem submit,0 pedidos de escrita de tabela e0 erros JS. O foco sai do diálogo ao percorrer Tab e Escape mantém-no aberto; cancelamento fecha. Registado em DEEP-OBS-04 como lacuna de acessibilidade, sem alterar o produto. Screenshots768/390 inspecionadas: formulário móvel usa scroll interno; cabeçalho pode ficar fora do recorte após foco. Prova: full-navigation/EVIDENCIAS-MODAL-OBRA.json.

## Contraste de texto

21 vistas em768px,376 amostras CSS. Textos secundários/eyebrows em fundos planos apresentam valores recorrentes3.47–3.62:1 para letra pequena; DEEP-OBS-05.81 amostras sinalizadas pelo limiar heurístico, não81 defeitos distintos. Gradientes/opacidade marcados incertos e não aprovados/reprovados automaticamente. Rótulos com descendentes de estilos distintos requerem medição por nó; não usar o agregado para declarar conformidade WCAG. Prova: full-navigation/EVIDENCIAS-CONTRASTE.json. Nenhuma cor alterada.

## Limitação de fidelidade

LIMITE-TIPOGRAFIA.md documenta fontes de substituição comprovadas por CDP. Medidas de geometria são locais, não certificação da tipografia de produção. Não usar as capturas para declarar UAT real aprovada.
