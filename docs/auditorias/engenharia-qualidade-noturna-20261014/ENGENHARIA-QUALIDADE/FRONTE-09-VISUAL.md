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
