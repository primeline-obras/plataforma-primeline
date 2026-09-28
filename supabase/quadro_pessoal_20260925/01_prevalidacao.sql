-- Quadro de Pessoal: apenas 28/09 a 02/10/2026, dia_inteiro; 95 posições.
-- Fonte: pré-visualização (18).csv, retiradas SOMENTE as 5 posições de Wanderson.
-- Manoel excluído. João Afonso -> Pedreiro. Nenhuma atualização de flags.
-- Não executar automaticamente. Sem semanas futuras; sem alterações de responsabilidades.
-- APENAS LEITURA. Executar após a migração 00 autorizada.
WITH manifesto AS (SELECT * FROM jsonb_to_recordset($manifesto$
[
  {
    "colaborador_id": "bef14c45-e884-4203-a3a4-a0db204a9c4f",
    "nome": "Alessandro Silva",
    "obra_id": "d22390df-25d7-444e-b281-eebbbee80c29",
    "obra": 32,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "bef14c45-e884-4203-a3a4-a0db204a9c4f",
    "nome": "Alessandro Silva",
    "obra_id": "d22390df-25d7-444e-b281-eebbbee80c29",
    "obra": 32,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "bef14c45-e884-4203-a3a4-a0db204a9c4f",
    "nome": "Alessandro Silva",
    "obra_id": "d22390df-25d7-444e-b281-eebbbee80c29",
    "obra": 32,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "bef14c45-e884-4203-a3a4-a0db204a9c4f",
    "nome": "Alessandro Silva",
    "obra_id": "d22390df-25d7-444e-b281-eebbbee80c29",
    "obra": 32,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "bef14c45-e884-4203-a3a4-a0db204a9c4f",
    "nome": "Alessandro Silva",
    "obra_id": "d22390df-25d7-444e-b281-eebbbee80c29",
    "obra": 32,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "e629a724-7dae-4807-a170-3378a59eb0fb",
    "nome": "Adilson Pires",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "e629a724-7dae-4807-a170-3378a59eb0fb",
    "nome": "Adilson Pires",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "e629a724-7dae-4807-a170-3378a59eb0fb",
    "nome": "Adilson Pires",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "e629a724-7dae-4807-a170-3378a59eb0fb",
    "nome": "Adilson Pires",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "e629a724-7dae-4807-a170-3378a59eb0fb",
    "nome": "Adilson Pires",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "743fed71-cd3b-447d-ad69-5f5010a2380f",
    "nome": "Bonifácio Té",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "743fed71-cd3b-447d-ad69-5f5010a2380f",
    "nome": "Bonifácio Té",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "743fed71-cd3b-447d-ad69-5f5010a2380f",
    "nome": "Bonifácio Té",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "743fed71-cd3b-447d-ad69-5f5010a2380f",
    "nome": "Bonifácio Té",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "743fed71-cd3b-447d-ad69-5f5010a2380f",
    "nome": "Bonifácio Té",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "4839f1e5-96d9-4706-8d7c-91c784963a77",
    "nome": "Fernando Silva",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "4839f1e5-96d9-4706-8d7c-91c784963a77",
    "nome": "Fernando Silva",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "4839f1e5-96d9-4706-8d7c-91c784963a77",
    "nome": "Fernando Silva",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "4839f1e5-96d9-4706-8d7c-91c784963a77",
    "nome": "Fernando Silva",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "4839f1e5-96d9-4706-8d7c-91c784963a77",
    "nome": "Fernando Silva",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "c6bd3641-367d-463c-a01a-ae60ed93c253",
    "nome": "Gilson Lima",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "c6bd3641-367d-463c-a01a-ae60ed93c253",
    "nome": "Gilson Lima",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "c6bd3641-367d-463c-a01a-ae60ed93c253",
    "nome": "Gilson Lima",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "c6bd3641-367d-463c-a01a-ae60ed93c253",
    "nome": "Gilson Lima",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "c6bd3641-367d-463c-a01a-ae60ed93c253",
    "nome": "Gilson Lima",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "0d6af694-8edb-41e0-b405-ad9f27feddc0",
    "nome": "João Borges",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "0d6af694-8edb-41e0-b405-ad9f27feddc0",
    "nome": "João Borges",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "0d6af694-8edb-41e0-b405-ad9f27feddc0",
    "nome": "João Borges",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "0d6af694-8edb-41e0-b405-ad9f27feddc0",
    "nome": "João Borges",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "0d6af694-8edb-41e0-b405-ad9f27feddc0",
    "nome": "João Borges",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "ed5674f3-b89f-4b86-b3c6-ff16f471b497",
    "nome": "Manuel Costa",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "ed5674f3-b89f-4b86-b3c6-ff16f471b497",
    "nome": "Manuel Costa",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "ed5674f3-b89f-4b86-b3c6-ff16f471b497",
    "nome": "Manuel Costa",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "ed5674f3-b89f-4b86-b3c6-ff16f471b497",
    "nome": "Manuel Costa",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "ed5674f3-b89f-4b86-b3c6-ff16f471b497",
    "nome": "Manuel Costa",
    "obra_id": "75579b62-44a6-41f4-95bd-f9968e39afc3",
    "obra": 79,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "11b8f830-35d6-48f3-b303-3684d55e652c",
    "obra": 85,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "11b8f830-35d6-48f3-b303-3684d55e652c",
    "obra": 85,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "11b8f830-35d6-48f3-b303-3684d55e652c",
    "obra": 85,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "11b8f830-35d6-48f3-b303-3684d55e652c",
    "obra": 85,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "11b8f830-35d6-48f3-b303-3684d55e652c",
    "obra": 85,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "0cb8eea5-c2ee-4784-9c2e-aa1622616543",
    "obra": 114,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "0cb8eea5-c2ee-4784-9c2e-aa1622616543",
    "obra": 114,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "0cb8eea5-c2ee-4784-9c2e-aa1622616543",
    "obra": 114,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "0cb8eea5-c2ee-4784-9c2e-aa1622616543",
    "obra": 114,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "0cb8eea5-c2ee-4784-9c2e-aa1622616543",
    "obra": 114,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "a441f83a-8de3-4618-94bf-6126326eacf6",
    "nome": "Mauro Dias",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "a441f83a-8de3-4618-94bf-6126326eacf6",
    "nome": "Mauro Dias",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "a441f83a-8de3-4618-94bf-6126326eacf6",
    "nome": "Mauro Dias",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "a441f83a-8de3-4618-94bf-6126326eacf6",
    "nome": "Mauro Dias",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "a441f83a-8de3-4618-94bf-6126326eacf6",
    "nome": "Mauro Dias",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "2654abc0-42f4-43f0-abcb-9d1e91d3709f",
    "nome": "Paulo Natividade",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "2654abc0-42f4-43f0-abcb-9d1e91d3709f",
    "nome": "Paulo Natividade",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "2654abc0-42f4-43f0-abcb-9d1e91d3709f",
    "nome": "Paulo Natividade",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "2654abc0-42f4-43f0-abcb-9d1e91d3709f",
    "nome": "Paulo Natividade",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "2654abc0-42f4-43f0-abcb-9d1e91d3709f",
    "nome": "Paulo Natividade",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "b147a0a5-d83d-4cf7-b868-a912a3227700",
    "nome": "William Coimbra",
    "obra_id": "5222b4c4-5255-4269-bd76-72b5227989c0",
    "obra": 118,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "cc5a58cc-d2ec-47bd-b64b-0952916b2526",
    "nome": "Clayton Oliveira",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "cc5a58cc-d2ec-47bd-b64b-0952916b2526",
    "nome": "Clayton Oliveira",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "cc5a58cc-d2ec-47bd-b64b-0952916b2526",
    "nome": "Clayton Oliveira",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "cc5a58cc-d2ec-47bd-b64b-0952916b2526",
    "nome": "Clayton Oliveira",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "cc5a58cc-d2ec-47bd-b64b-0952916b2526",
    "nome": "Clayton Oliveira",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "81a195a3-d75f-4504-87a7-4060078b9f9e",
    "nome": "João Afonso",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "81a195a3-d75f-4504-87a7-4060078b9f9e",
    "nome": "João Afonso",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "81a195a3-d75f-4504-87a7-4060078b9f9e",
    "nome": "João Afonso",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "81a195a3-d75f-4504-87a7-4060078b9f9e",
    "nome": "João Afonso",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "81a195a3-d75f-4504-87a7-4060078b9f9e",
    "nome": "João Afonso",
    "obra_id": "7c2a0c29-5eca-40d9-aff0-3e1b00d8e973",
    "obra": 120,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "0d271a1c-91f8-47ae-9566-84f1fbc213f3",
    "nome": "Regivaldo Rios",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Enc. Obra",
    "funcao_final": "Enc. Obra"
  },
  {
    "colaborador_id": "7bccd32c-26ca-4bd8-a009-150cb81ac6f7",
    "nome": "Wilson Monteiro",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "7bccd32c-26ca-4bd8-a009-150cb81ac6f7",
    "nome": "Wilson Monteiro",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "7bccd32c-26ca-4bd8-a009-150cb81ac6f7",
    "nome": "Wilson Monteiro",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "7bccd32c-26ca-4bd8-a009-150cb81ac6f7",
    "nome": "Wilson Monteiro",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "7bccd32c-26ca-4bd8-a009-150cb81ac6f7",
    "nome": "Wilson Monteiro",
    "obra_id": "127a4443-931b-49b8-a7eb-48e7099d452c",
    "obra": 121,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "2195300f-685e-4e60-97e7-a30631d63b71",
    "nome": "Genito Nanque",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "2195300f-685e-4e60-97e7-a30631d63b71",
    "nome": "Genito Nanque",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "2195300f-685e-4e60-97e7-a30631d63b71",
    "nome": "Genito Nanque",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "2195300f-685e-4e60-97e7-a30631d63b71",
    "nome": "Genito Nanque",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "2195300f-685e-4e60-97e7-a30631d63b71",
    "nome": "Genito Nanque",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Servente",
    "funcao_final": "Servente"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-09-28",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-09-29",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-09-30",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-10-01",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  },
  {
    "colaborador_id": "daed6a73-4566-4e16-8ee0-2e94cf36e2bf",
    "nome": "Helder Gonçalves",
    "obra_id": "d3f0e9bd-3fb4-4a10-9f23-253071516745",
    "obra": 128,
    "data": "2026-10-02",
    "periodo": "dia_inteiro",
    "funcao_atual": "Pedreiro",
    "funcao_final": "Pedreiro"
  }
]
$manifesto$::jsonb) AS m(colaborador_id uuid,nome text,obra_id uuid,obra integer,data date,periodo text,funcao_atual text,funcao_final text)),
avaliacao AS (
 SELECT m.*,(SELECT count(*) FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=m.colaborador_id AND q.obra_id=m.obra_id
 AND q.data=m.data AND q.periodo=m.periodo AND q.tipo_alocacao='obra' AND q.descricao_livre IS NULL) AS existentes,
 array_remove(ARRAY[
 CASE WHEN c.id IS NULL OR c.empresa_id IS DISTINCT FROM '73fb13c8-d29f-4192-a506-4ca243343add'::uuid OR c.nome IS DISTINCT FROM m.nome THEN 'IDENTIDADE_DIVERGENTE' END,
 CASE WHEN c.data_saida IS NOT NULL AND c.data_saida<=m.data OR c.data_admissao>m.data THEN 'COLABORADOR_INDISPONIVEL' END,
 CASE WHEN c.funcao IS DISTINCT FROM m.funcao_atual AND c.funcao IS DISTINCT FROM m.funcao_final THEN 'FUNCAO_DIVERGENTE' END,
 CASE WHEN o.id IS NULL OR o.empresa_id IS DISTINCT FROM '73fb13c8-d29f-4192-a506-4ca243343add'::uuid OR o.numero::integer IS DISTINCT FROM m.obra THEN 'OBRA_DIVERGENTE' END,
 CASE WHEN EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=m.colaborador_id AND a.data=m.data) THEN 'AUSENCIA_NESTA_DATA' END
 ],NULL::text) AS erros
 FROM manifesto m LEFT JOIN public.colaboradores c ON c.id=m.colaborador_id LEFT JOIN public.obras o ON o.id=m.obra_id
)
SELECT count(*) AS posicoes_previstas,
 count(*) FILTER(WHERE cardinality(erros)>0 OR existentes>1) AS bloqueios,
 count(*) FILTER(WHERE existentes=0 AND cardinality(erros)=0) AS a_inserir,
 count(*) FILTER(WHERE existentes=1 AND cardinality(erros)=0) AS preservar,
 coalesce(obj_description(to_regprocedure('public.fn_quadro_operar(text,jsonb,boolean,text)'),'pg_proc')='quadro_v3_20260925',false) AS regras_instaladas,
 CASE WHEN count(*)=95 AND count(*) FILTER(WHERE cardinality(erros)>0 OR existentes>1)=0 AND coalesce(obj_description(to_regprocedure('public.fn_quadro_operar(text,jsonb,boolean,text)'),'pg_proc')='quadro_v3_20260925',false) THEN 'PRONTO' ELSE 'BLOQUEADO' END AS estado,
 jsonb_agg(to_jsonb(avaliacao) ORDER BY obra,nome,data) AS previsualizacao
 FROM avaliacao;
