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

## Metadados SQL atuais

9 cenários/13 contagens Node PASS: obra própria registar/apagar; outra empresa recusa criação/remoção; caminho incoerente recusa; Encarregado sem escrita nesta RPC; documento inexistente recusa; entidade própria apaga, entidade estrangeira e referência órfã recusam. Prova EVIDENCIAS-DOCUMENTOS-METADADOS-SQL.json. Helper privado entidade/autorizar_alvo e RPCs copiados exatamente do SQL atual, sem stub permissivo. Controlo positivo precede a aceitação das recusas.

Limites: nenhum byte Storage; nem toda auditoria/trigger recomposta; não certifica o POST direto de documentos_obra do centro documental. fn_registar_documento_obra aceita contrato/orcamento/etc.; o centro usa outras categorias e outra rota. Os24 pares completos de Auth/Documento/Download continuam BLOQUEADO. O primeiro ensaio de entidade tinha helper ausente na fixture42883 e foi preservado em logs/DOCUMENTOS-FIRST-MISSING-HELPER.txt; não é falha do produto.

## Proposta PDF: sucesso ambíguo

DEEP-DOC-03 é P2 condicional, variante N-DOC-01: o callback deleteProposalPdf está ligado a deleteWorkDocument (app.js:6233). A resposta2xx com corpo perdido entra no catch de comparative-map.js:280 e pede eliminação do objeto. Três controlos positivos/de erro e uma assertion diagnóstica preservados em EVIDENCIAS-PDF-COMPENSACAO-AMBIGUA.json. Os4 NodePASS significam que o ensaio correu conforme previsto; o último tem functional_result=FAIL_CONDITIONAL.

Não se provou perda real: o commit e os objetos foram simulados, e Storage pode recusar apagar uma referência ativa. Recomendação futura: conservar bytes até reconciliar estado da operação; usar identificação/idempotência para distinguir recusa de resultado desconhecido. Não foi implementada alteração.

## Rota direta e RLS

RLS-DOCUMENTAL-BASELINE.md documenta2 SELECT estrangeiros indevidos na montagem local para Gestão/Gerência; role authenticated e RLS ativo confirmados. DEEP-SEC-03 relaciona-se com N-SEC-02. Não afirmar ocorrência em produção nem fechar Documento/Download completos; apenas a baseline e a rota específica foram verificadas. As9 provas de RPC segura não contradizem a falha da rota DML.
