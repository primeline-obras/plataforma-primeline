# Cobertura backend observada

```json
{
  "original": 203,
  "reconciliados": 203,
  "chaves_unicas": 203,
  "aplicaveis": 203,
  "nao_aplicaveis": 0,
  "cobertos_prova_anterior": 0,
  "cobertura": {
    "BLOQUEADO": 24,
    "EXECUTADO": 179
  },
  "resultados_backend": {
    "NÃO EXECUTADO no backend; sem substituição por mock": 24,
    "PASS": 174,
    "PENDENTE CONTRATO": 1,
    "FAIL": 4
  },
  "provas_suplementares": 5,
  "limitacao": "Execução de variantes backend especificadas; não todos os fluxos frontend nem catálogo de produção atual"
}
```

As chaves são exatamente as 203 originais. Zero exclusões por ausência de menu. As cinco provas adicionais fora desse conjunto ficam separadas. Não somar contagens Node de grupos/reexecuções como cenários únicos.

A fixture económica reconstrói catálogo público/RLS/ACL e funções reais capturadas, mas não todos os defaults, constraints e triggers operacionais. Asserções financeiras verificam efeito intratransação antes da reversão. A fixture RH instala os scripts cumulativos e confirma preview, commit, consumidores e replay. As decisões de papel foram confrontadas com o código, sem mudar permissões.
