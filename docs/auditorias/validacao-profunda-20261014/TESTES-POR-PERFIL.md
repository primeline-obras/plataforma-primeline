# Testes por perfil

|Perfil|Backend executado|PASS|FAIL|Contrato pendente|Fluxo bloqueado|FAIL parcial de metadados|
|---|---:|---:|---:|---:|---:|---:|
|adjunto|22|22|0|0|3|0|
|administrativo|22|21|1|0|3|0|
|diretor_obra|22|22|0|0|3|0|
|encarregado|22|22|0|0|3|0|
|financeiro|23|22|1|0|3|0|
|gerencia|23|21|2|0|3|1|
|gestao_plataforma|23|20|2|1|3|1|
|preparador|22|22|0|0|3|0|

FAIL parcial permanece dentro de um fluxo bloqueado: não somar como mais um par nem certificar Auth/Storage. Baseline RLS local não é catálogo hospedado.
