export const demoWorks = [
  { id: "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973", numero: "120", nome: "Moradia Unifamiliar — Cascais" },
  { id: "demo-118", numero: "118", nome: "Reabilitação — Lisboa" },
  { id: "demo-117", numero: "117", nome: "Escritórios — Oeiras" },
];
export const demoSuppliers = [
  { id: "fluxion", nome: "Fluxion" }, { id: "sergio", nome: "Sergio" },
  { id: "panorama", nome: "Panorama Delicado (Radu)" }, { id: "effusive", nome: "Effusive Spirit" },
  { id: "sanitop", nome: "Sanitop Portugal" },
];
export const demoSubcontracts = [
  { id: "sub-elec", obra_id: demoWorks[0].id, fornecedor_id: "fluxion", especialidade: "Eletricidade" },
  { id: "sub-ac", obra_id: demoWorks[0].id, fornecedor_id: "fluxion", especialidade: "AC Pré-instalação" },
  { id: "sub-hid", obra_id: demoWorks[0].id, fornecedor_id: "sergio", especialidade: "Hidráulica" },
  { id: "sub-vala", obra_id: demoWorks[0].id, fornecedor_id: "panorama", especialidade: "Vala" },
];
export const demoInvoices = [
  { id: "demo-1", obra_id: demoWorks[0].id, tipo_origem: "subempreitada", fornecedor_id: "fluxion", subempreitada_id: "sub-elec", numero_doc: "FT 2026/041", data_fatura: "2026-07-18", valor: 4250, estado_aprovacao: "pendente" },
  { id: "demo-2", obra_id: demoWorks[0].id, tipo_origem: "estaleiro", fornecedor_id: "sanitop", numero_doc: "FT 003194", data_fatura: "2026-07-21", valor: 387.45, estado_aprovacao: "pendente" },
  { id: "demo-3", obra_id: "demo-118", tipo_origem: "material", fornecedor_id: "sanitop", numero_doc: "FT 003228", data_fatura: "2026-07-23", valor: 1864.9, estado_aprovacao: "pendente" },
];
