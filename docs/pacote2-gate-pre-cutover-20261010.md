# Gate pré-cutover — 10/10/2026

Frontend publicado permanece em `11aac61a165369007d9d18276d8cab79329d4121`. Estes artefactos não alteram frontend, writers V2 ou os scripts de cutover existentes.

## Correção

A primeira composição inseria um SELECT sem parênteses na lista VALUES. O script dedicado calcula o catálogo numa variável com SELECT INTO antes do INSERT. A expressão é a mesma do precheck, sem aproximação.

O gerador temporário anterior falhou na linha 48 do stdin: `${id(...)}` do teste foi interpolado no escopo externo, onde `id` não existia. Nenhum gerador ficou no repositório. O teste é agora um módulo direto, com `id`, `read`, `run`, `q` e as restantes dependências definidos no respetivo escopo. O bootstrap reaproveita as fixtures sintéticas existentes.

## Fingerprint e reutilização

SHA-256 dos bytes UTF-8 da concatenação `path TAB sha256 LF`, com os 59 caminhos do manifesto ordenados ordinalmente:

`99f9904ded011f6aa0a2140a1e9b89490abf39407dc4fdd81fee473491ddc76b`

O gate existente só é reutilizado se a linha, fingerprint, catálogo live, instalação, validações, data, consumo, owner, ACL e RLS corresponderem. Não é atualizado para fazer coincidir. O precheck existente valida o formato do hash; o novo script do gate exige também este fingerprint exato.

## Verificação local

PostgreSQL efémero 17.6: 18 PASS / 0 FAIL / 0 SKIP. Cadeia exata gate → precheck → cutover → postcheck; quatro tipos de escrita recusados com 42501; SELECT preservado. Negativos: catálogo stale, instalação, flags, hash, consumo, data futura, grants/RLS, múltiplas linhas, colisão legado/V2, cutover existente, snapshot/helper/trigger alterados. Rollback recusa factos V2 e permite reversão vazia e replay sem consumir o gate.

Segunda verificação: executar o mesmo módulo com `GATE_SMOKE_ONLY=1` num worktree limpo do commit, usando os runtimes PostgreSQL/pg já instalados. Esse modo executa apenas criação/reutilização, precheck, cutover, postcheck, writer fechado e SELECT.

## Ordem real

1. Reconfirmar frontend publicado, 59 assets e estado pré-cutover.
2. `pacote2_gate_pre_cutover.sql` — transação atómica com postchecks Folha/documental antes do registo.
3. `folha_v2_legacy_cutover_precheck.sql` — leitura e rollback.
4. `folha_v2_legacy_cutover.sql` — sem edição.
5. `folha_v2_legacy_cutover_postcheck.sql` — leitura e rollback.
6. Prova técnica sem dados de trabalhadores; smoke V2 sem confirmação de escritas.

Não executar rollback real automaticamente. Não consumir o gate, executar Fase B, configurar calendário ou ativar HE monetária/exportadores.
