# Frente 3 — DOCUMENTOS

Estado: **PARCIAL**.

## Verificações

Upload/consulta com contexto trocado reproduzidos; extensão/tamanho recusados pelo cliente; bytes vazios e MIME divergente chegam ao transporte.

## Evidências

EVIDENCIAS-DOCUMENTOS-CONTEXTO.json

## Limites e próximo passo

Storage real local indisponível; ciclo integral de todas as entidades e revisão/remoção ainda não certificado.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Falhas por etapa

EVIDENCIAS-DOCUMENTOS-FALHAS-ETAPAS.json cobre6 assertions com código real do cliente/transporte sintético. Upload de bytes falhado não tenta metadados; cancelamento não chama RPC; recusa da RPC de apagamento não apaga bytes; download falhado liberta o botão e apresenta erro. Duas assertions são reproduções do limite N-DOC-01, sem PASS funcional: metadados falhados após upload sem compensação e bytes falhados após RPC sem reload/compensação. Nenhum Storage real ou apagamento persistente foi executado.
