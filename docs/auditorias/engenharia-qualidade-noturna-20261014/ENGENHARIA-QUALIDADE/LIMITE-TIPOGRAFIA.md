# Limite das capturas: tipografia local

Os ensaios completos interceptam pedidos externos para preservar o isolamento. O @import Google Fonts de styles.css não carrega Manrope/DM Sans nesse ambiente.

A consulta CDP dos nós visíveis confirmou Times New Roman para botões/rótulos/eyebrow e Arial Black no h1 inspecionado. Prova: full-navigation/FONTES-EFETIVAS-LOCAIS.json. Não houve download de fontes nem alteração CSS.

Consequências: screenshots são evidência da renderização local com fontes de substituição. Altura de20px do REGISTAR e recortes dependentes da largura do texto são observações locais, sem certificação de geometria idêntica em produção. Nomes acessíveis/foco, pedidos de rede, conteúdos/estados e cálculos de cor CSS continuam provas independentes da fonte. Contraste por fonte/tamanho real e fidelidade tipográfica completa ficam limitados até haver as fontes oficiais num ambiente isolado.

DEPENDÊNCIA TÉCNICA: disponibilizar os ficheiros oficiais das fontes ou permitir ambiente local já equipado; não recorrer a credenciais/dados de produção. Continuar restantes verificações independentes.
