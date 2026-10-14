# Cobertura por perfil

Oito papéis reais: gestao_plataforma,gerencia,administrativo,financeiro,diretor_obra,adjunto,preparador,encarregado. Cargo RH não deriva o papel. Gestão superutilizador funcional mantém tenant/revisão/auditoria; Gerência separada.

Frontend accessFor executado para oito perfis, com quatro booleans financeiros/obra por perfil. Ações de faturas de fornecedor seguem esse gate, mas grants/SQL reais não foram certificados por este teste.

Cadastro RH nativo: Gestão/Gerência/Admin leem; apenas Gestão importa Excel; os outros cinco perfis não leem cadastro completo. Usuário inativo recusado; outra empresa retorna0. Folha/tarefas: Admin confirma plano, Encarregado reporta, Diretor/Adjunto validam, Preparador não confirma tarefa. Demais contratos específicos têm provas no harness, não foi certificada toda matriz de operações.

Financeiro monetário usa stubs de autorização; isso não prova acesso econômico entre empresas. Médico/viaturas têm suites anteriores, não UAT nova. HR29 autorizado para técnicos segue intacto; HR38 permanece P1. Quadro do Encarregado não ganhou escrita.
