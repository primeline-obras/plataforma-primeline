export const demoWorks = [
  { id: "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973", numero: "120", nome: "Moradia Unifamiliar — Cascais", situacao: "em_curso", data_inicio: "2026-01-15", data_fim_prevista: "2026-12-18" },
  { id: "demo-118", numero: "118", nome: "Reabilitação — Lisboa", situacao: "em_curso", data_inicio: "2025-11-03", data_fim_prevista: "2026-09-30" },
  { id: "demo-117", numero: "117", nome: "Escritórios — Oeiras", situacao: "em_curso", data_inicio: "2026-03-02", data_fim_prevista: "2027-01-29" },
];
export const demoSuppliers = [
  { id: "fluxion", nome: "Fluxion" }, { id: "sergio", nome: "Sergio" },
  { id: "panorama", nome: "Panorama Delicado (Radu)" }, { id: "effusive", nome: "Effusive Spirit" },
  { id: "sanitop", nome: "Sanitop Portugal" },
];
export const demoSubcontracts = [
  { id: "sub-elec", obra_id: demoWorks[0].id, fornecedor_id: "fluxion", especialidade: "Eletricidade", valor_adjudicado: 17000, estado: "adjudicada", estado_aprovacao_gerencia: "aprovado" },
  { id: "sub-ac", obra_id: demoWorks[0].id, fornecedor_id: "fluxion", especialidade: "AC Pré-instalação", valor_adjudicado: 2700, estado: "adjudicada", estado_aprovacao_gerencia: "aprovado" },
  { id: "sub-hid", obra_id: demoWorks[0].id, fornecedor_id: "sergio", especialidade: "Hidráulica", valor_adjudicado: 7500, estado: "adjudicada", estado_aprovacao_gerencia: "pendente" },
  { id: "sub-vala", obra_id: demoWorks[0].id, fornecedor_id: "panorama", especialidade: "Vala", valor_adjudicado: 7280, estado: "adjudicada", estado_aprovacao_gerencia: "aprovado" },
];
export const demoInvoices = [
  { id: "demo-1", obra_id: demoWorks[0].id, tipo_origem: "subempreitada", fornecedor_id: "fluxion", subempreitada_id: "sub-elec", numero_doc: "FT 2026/041", data_fatura: "2026-07-18", valor: 4250, estado_aprovacao: "pendente" },
  { id: "demo-2", obra_id: demoWorks[0].id, tipo_origem: "estaleiro", fornecedor_id: "sanitop", numero_doc: "FT 003194", data_fatura: "2026-07-21", valor: 387.45, estado_aprovacao: "pendente" },
  { id: "demo-3", obra_id: "demo-118", tipo_origem: "material", fornecedor_id: "sanitop", numero_doc: "FT 003228", data_fatura: "2026-07-23", valor: 1864.9, estado_aprovacao: "pendente" },
  { id: "demo-4", obra_id: demoWorks[0].id, tipo_origem: "material", fornecedor_id: "sanitop", numero_doc: "FT 003105", data_fatura: "2026-07-16", valor: 928.2, estado_aprovacao: "aprovado", condicao_pagamento: "imediato", estado_pagamento: "por_pagar", data_aprovacao: "2026-07-22T10:30:00Z" },
  { id: "demo-5", obra_id: "demo-118", tipo_origem: "subempreitada", fornecedor_id: "panorama", numero_doc: "FT 2026/087", data_fatura: "2026-07-10", valor: 3640, estado_aprovacao: "aprovado", condicao_pagamento: "15_dias", estado_pagamento: "por_pagar", data_aprovacao: "2026-07-20T09:15:00Z" },
  { id: "demo-6", obra_id: "demo-117", tipo_origem: "estaleiro", fornecedor_id: "effusive", numero_doc: "FT 2026/012", data_fatura: "2026-06-28", valor: 512.75, estado_aprovacao: "aprovado", condicao_pagamento: "30_dias", estado_pagamento: "por_pagar", data_aprovacao: "2026-07-18T14:45:00Z" },
  { id: "demo-7", obra_id: demoWorks[0].id, tipo_origem: "subempreitada", fornecedor_id: "sergio", numero_doc: "FT 2026/033", data_fatura: "2026-06-20", valor: 2250, estado_aprovacao: "aprovado", condicao_pagamento: "15_dias", estado_pagamento: "pago", data_aprovacao: "2026-06-25T11:00:00Z", data_pagamento: "2026-07-09" },
];
