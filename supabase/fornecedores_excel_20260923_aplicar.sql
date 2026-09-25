-- APLICAR — Base de Dados de Subempreiteiros e Fornecedores.xlsx
-- Fonte SHA256: bfef7e7a88189beeaed16d9d2a97e754464700b9616e90425b97d7f07075d897
-- Só campos vazios; não renomeia, não funde, não altera NIF, avaliações, tipos ou zonas.
-- Novos: tipo por classificar (NULL), estado nao_avaliado. Não cria faturas/contratos.
begin;
do $permissao$
begin
  if current_user not in ('postgres','supabase_admin') or auth.uid() is not null then
    if not exists(select 1 from public.utilizadores u where u.id=public.fn_utilizador_atual_id()
      and coalesce(u.ativo,false) and u.funcao in ('gestao_plataforma','administrativo','gerencia')
      and u.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'::uuid) then
      raise exception 'Sem permissão para completar este diretório.';
    end if;
  end if;
end $permissao$;

create temp table _forn_opcao(aplicar boolean,fonte_hash text,empresa_id uuid) on commit drop;
insert into _forn_opcao values(true,'bfef7e7a88189beeaed16d9d2a97e754464700b9616e90425b97d7f07075d897','73fb13c8-d29f-4192-a506-4ca243343add');
create temp table _forn_fonte on commit drop as
select * from jsonb_to_recordset($fornecedores_fonte$
[
  {
    "key": "valarme",
    "nome": "Valarme",
    "acao": "existente",
    "alvo": "ca83a1e3-3165-4920-a758-850da10a4b8f",
    "alvo_nome": "Valarme",
    "email": "geral@valarme.pt",
    "telefone": "211518626 / 213936000",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALARMES; linha: 5; nome na fonte: Valarme\nAtividade: Alarme, vigilância, detecção de incendios, extintores, etc\nLocalidade/morada: Rua Padre Gregório Verdonk, Nº 4 -D/E 1900-362 Lisboa-PT\nContactos na fonte: 211 518 626 213 936 000\nEmails na fonte: geral@valarme.pt\nObservações da fonte: www.valarme.pt",
    "emails": [
      "geral@valarme.pt"
    ],
    "phones": [
      "211518626",
      "213936000"
    ]
  },
  {
    "key": "almasindustrieslda",
    "nome": "Almas Industries, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "mail@appasset.pt",
    "telefone": "223774280",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALARMES; linha: 8; nome na fonte: Almas Industries, Lda\nAtividade: Soluções de segurança, controlo de acessos biométricos e vídeovigilância\nLocalidade/morada: Rot. Eng.º Edgar Cardoso, 23, 4.º Andar, salas G, H e I 4400-676 Vila Nova de Gaia, Portugal\nContactos na fonte: 223774280\nEmails na fonte: mail@appasset.pt",
    "emails": [
      "mail@appasset.pt"
    ],
    "phones": [
      "223774280"
    ]
  },
  {
    "key": "cnpvedacao",
    "nome": "CNP Vedação",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial@cnpvedacao.com",
    "telefone": "261423421",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 6; nome na fonte: CNP Vedação\nAtividade: Aluguer de vedações\nLocalidade/morada: Lourinhã\nContactos na fonte: 261423421\nEmails na fonte: comercial@cnpvedacao.com",
    "emails": [
      "comercial@cnpvedacao.com"
    ],
    "phones": [
      "261423421"
    ]
  },
  {
    "key": "amarnaveservicosmaritimoslda",
    "nome": "AMARNAVE - Serviços Marítimos, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@amarnave.com",
    "telefone": "210177548 / 916673836",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 10; nome na fonte: AMARNAVE - Serviços Marítimos, Lda\nAtividade: Aluguer de equipamentos (gruas, equip. de mov. de terras, vedações, etc.)\nLocalidade/morada: Sacavém\nContactos na fonte: 210 177 548 916 673 836\nEmails na fonte: geral@amarnave.com",
    "emails": [
      "geral@amarnave.com"
    ],
    "phones": [
      "210177548",
      "916673836"
    ]
  },
  {
    "key": "inovsan",
    "nome": "Inovsan",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "212452751 / 918746690",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 13; nome na fonte: Inovsan\nAtividade: Aluguer de equipamentos (sanitários, produtos de higiene e manutenção, etc.)\nLocalidade/morada: Charneca Caparica\nContactos na fonte: 212 452 751 918 746 690\nEmails na fonte: comercial@inovsan.pt geral@inovsan.pt",
    "emails": [
      "comercial@inovsan.pt",
      "geral@inovsan.pt"
    ],
    "phones": [
      "212452751",
      "918746690"
    ]
  },
  {
    "key": "alugalgrupoeleva",
    "nome": "ALUGAL - GRUPO ELEVA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@alugal.pt",
    "telefone": "229995530 / 962149700",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 14; nome na fonte: ALUGAL - GRUPO ELEVA\nAtividade: Aluguer de equipamentos\nContactos na fonte: 229 995 530 962 149 700\nEmails na fonte: geral@alugal.pt",
    "emails": [
      "geral@alugal.pt"
    ],
    "phones": [
      "229995530",
      "962149700"
    ]
  },
  {
    "key": "andalugaaluguerdeandaimesemaquinasparaaconstrucaolda",
    "nome": "ANDALUGA - Aluguer de Andaimes e Máquinas Para A Construção, Lda",
    "acao": "existente",
    "alvo": "cd8c97e9-7779-4f1a-956f-3fc28c452951",
    "alvo_nome": "Andaluga - Aluguer De Andaimes E Máquinas Para A Construção, Lda",
    "email": "andaluga@andaluga.pt",
    "telefone": "212260830 / 918350899",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 18; nome na fonte: ANDALUGA - Aluguer de Andaimes e Máquinas Para A Construção, Lda\nAtividade: Aluguer de andaimes, gruas e equipamentos\nLocalidade/morada: Seixal\nContactos na fonte: 212 260 830 918 350 899\nEmails na fonte: andaluga@andaluga.pt",
    "emails": [
      "andaluga@andaluga.pt"
    ],
    "phones": [
      "212260830",
      "918350899"
    ]
  },
  {
    "key": "remsa",
    "nome": "REMSA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial@remsa.pt",
    "telefone": "263650080",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 21; nome na fonte: REMSA\nAtividade: Aluguer e venda de contentores e módulos pré-fabricados\nLocalidade/morada: Lisboa\nContactos na fonte: 263650080\nEmails na fonte: comercial@remsa.pt",
    "emails": [
      "comercial@remsa.pt"
    ],
    "phones": [
      "263650080"
    ]
  },
  {
    "key": "mundigruasportugal",
    "nome": "Mundigruas Portugal",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial.pt@mundigruas.com",
    "telefone": "253671768",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 24; nome na fonte: Mundigruas Portugal\nAtividade: Gruas\nLocalidade/morada: Braga\nContactos na fonte: 253671768\nEmails na fonte: comercial.pt@mundigruas.com",
    "emails": [
      "comercial.pt@mundigruas.com"
    ],
    "phones": [
      "253671768"
    ]
  },
  {
    "key": "servirentlda",
    "nome": "Servirent, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@servirent.pt",
    "telefone": "263652867",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 26; nome na fonte: Servirent, Lda\nAtividade: Aluguer de outras máquinas e equipamentos\nLocalidade/morada: Samora Correia\nContactos na fonte: 263652867\nEmails na fonte: geral@servirent.pt",
    "emails": [
      "geral@servirent.pt"
    ],
    "phones": [
      "263652867"
    ]
  },
  {
    "key": "machrent",
    "nome": "MACHRENT",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@machrent.pt",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 29; nome na fonte: MACHRENT\nAtividade: Aluguer de Equipamentos\nLocalidade/morada: Quinta da Marquesa IV, Lote B, 2950-677 Quinta do Anjo\nContactos na fonte: 808215115\nEmails na fonte: geral@machrent.pt",
    "emails": [
      "geral@machrent.pt"
    ],
    "phones": []
  },
  {
    "key": "vmflex",
    "nome": "VM Flex",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@vmflex.pt",
    "telefone": "215817952",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 33; nome na fonte: VM Flex\nAtividade: Comércio e manutenção de equipamentos indrustriais\nLocalidade/morada: Lisboa\nContactos na fonte: 215817952\nEmails na fonte: geral@vmflex.pt",
    "emails": [
      "geral@vmflex.pt"
    ],
    "phones": [
      "215817952"
    ]
  },
  {
    "key": "hymedi",
    "nome": "Hymedi",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "export@machinerymachinery.com",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 34; nome na fonte: Hymedi\nAtividade: Máquinas de construção e outros tipos de máquinas\nLocalidade/morada: China\nContactos na fonte: 8618661819186\nEmails na fonte: export@machinerymachinery.com",
    "emails": [
      "export@machinerymachinery.com"
    ],
    "phones": []
  },
  {
    "key": "euroelevacao",
    "nome": "Euro Elevação",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "212131100",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 36; nome na fonte: Euro Elevação\nAtividade: Aluguer de aindaimes de alumínio\nLocalidade/morada: Rua do Alumínio 310, 2950-805 Quinta do Anjo\nContactos na fonte: 212131100\nEmails na fonte: a.alves@euroelevacao\nObservações da fonte: www.euroelevacao.pt",
    "emails": [],
    "phones": [
      "212131100"
    ]
  },
  {
    "key": "tractolena",
    "nome": "Tracto-Lena",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "rui.oliveira@tracto-lena.com",
    "telefone": "917298308",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ALUGUER DE EQUIPAMENTO DE E ; linha: 37; nome na fonte: Tracto-Lena\nAtividade: Aluguer de máquinas\nLocalidade/morada: Leiria\nContactos na fonte: 917298308\nEmails na fonte: rui.oliveira@tracto-lena.com",
    "emails": [
      "rui.oliveira@tracto-lena.com"
    ],
    "phones": [
      "917298308"
    ]
  },
  {
    "key": "combituboslda",
    "nome": "Combitubos, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "combitubos@gmail.com",
    "telefone": "219337471 / 919640229",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ANDAIMES,ESCADAS,ESCADOTES, PE; linha: 7; nome na fonte: Combitubos, Lda\nAtividade: Montagem e aluguer de andaimes\nLocalidade/morada: Odivelas\nContactos na fonte: 219 337 471 919 640 229\nEmails na fonte: combitubos@gmail.com",
    "emails": [
      "combitubos@gmail.com"
    ],
    "phones": [
      "219337471",
      "919640229"
    ]
  },
  {
    "key": "andaimetal",
    "nome": "ANDAIMETAL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@andaimetal.com",
    "telefone": "914933707 / 911162935",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ANDAIMES,ESCADAS,ESCADOTES, PE; linha: 8; nome na fonte: ANDAIMETAL\nAtividade: Montagem de andaimes\nLocalidade/morada: Queluz e Belas\nContactos na fonte: 914 933 707 911 162 935\nEmails na fonte: geral@andaimetal.com",
    "emails": [
      "geral@andaimetal.com"
    ],
    "phones": [
      "914933707",
      "911162935"
    ]
  },
  {
    "key": "sesociedadedeescoramentoslda",
    "nome": "SE -Sociedade de Escoramentos, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "214795037 / 917324159",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ANDAIMES,ESCADAS,ESCADOTES, PE; linha: 9; nome na fonte: SE -Sociedade de Escoramentos, Lda\nAtividade: Andaimes metálicos e tubulares\nLocalidade/morada: Pontinha\nContactos na fonte: 214 795 037 917 324 159\nEmails na fonte: geral@seandaimes.pt seandaimes@iol.pt",
    "emails": [
      "geral@seandaimes.pt",
      "seandaimes@iol.pt"
    ],
    "phones": [
      "214795037",
      "917324159"
    ]
  },
  {
    "key": "turmadoandaimeunipessoallda",
    "nome": "Turma do Andaime Unipessoal, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "turmadoandaime@hotmail.com",
    "telefone": "963494061",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ANDAIMES,ESCADAS,ESCADOTES, PE; linha: 10; nome na fonte: Turma do Andaime Unipessoal, Lda\nAtividade: Montagem e aluguer de andaimes\nLocalidade/morada: Via Longa\nContactos na fonte: 963 494 061\nEmails na fonte: turmadoandaime@hotmail.com",
    "emails": [
      "turmadoandaime@hotmail.com"
    ],
    "phones": [
      "963494061"
    ]
  },
  {
    "key": "fordemandlda",
    "nome": "FOR DEMAND, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@fordemand.pt",
    "telefone": "223744090",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ANDAIMES,ESCADAS,ESCADOTES, PE; linha: 13; nome na fonte: FOR DEMAND, Lda\nAtividade: Equipamentos e materiais para armazéns, segurança e proteção\nLocalidade/morada: Vila Nova de Gaia\nContactos na fonte: 223744090\nEmails na fonte: info@fordemand.pt",
    "emails": [
      "info@fordemand.pt"
    ],
    "phones": [
      "223744090"
    ]
  },
  {
    "key": "speedrent",
    "nome": "SPEEDRENT",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "214459600",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ANDAIMES,ESCADAS,ESCADOTES, PE; linha: 15; nome na fonte: SPEEDRENT\nAtividade: Máquinas de movimentação, cargas, remoção de terras e elevação\nLocalidade/morada: Stº Tirso\nContactos na fonte: 707 200 270 214 459 600\nObservações da fonte: https://www.speedrent.pt/portfolio/plataforma-tesoura-eletricas-12m/",
    "emails": [],
    "phones": [
      "214459600"
    ]
  },
  {
    "key": "flafagamentos",
    "nome": "FL AFAGAMENTOS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@flafagamentos.com",
    "telefone": "210167324 / 936162366",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ASSENTAMENTO E AFAGAMENTO DE PA; linha: 5; nome na fonte: FL AFAGAMENTOS\nAtividade: Afagamento, assentamento e envernizamento de pavimentos\nLocalidade/morada: Pontinha\nContactos na fonte: 210 167 324 936 162 366\nEmails na fonte: geral@flafagamentos.com",
    "emails": [
      "geral@flafagamentos.com"
    ],
    "phones": [
      "210167324",
      "936162366"
    ]
  },
  {
    "key": "hugorego",
    "nome": "Hugo Rêgo",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "968140139",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ASSENTAMENTO E AFAGAMENTO DE PA; linha: 7; nome na fonte: Hugo Rêgo\nAtividade: Afagador\nContactos na fonte: 968140139",
    "emails": [],
    "phones": [
      "968140139"
    ]
  },
  {
    "key": "pavipnaislda",
    "nome": "Pavipnais, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "pavipnais@sapo.pt",
    "telefone": "967045489 / 219333510",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ASSENTAMENTO E AFAGAMENTO DE PA; linha: 9; nome na fonte: Pavipnais, Lda\nAtividade: Assentamento pavimentos de madeira\nLocalidade/morada: Ramada\nContactos na fonte: 967 045 489 219 333 510\nEmails na fonte: pavipnais@sapo.pt\nObservações da fonte: Marco Ferreira",
    "emails": [
      "pavipnais@sapo.pt"
    ],
    "phones": [
      "967045489",
      "219333510"
    ]
  },
  {
    "key": "matersuperficieldamasterbetonilhas",
    "nome": "MATERSUPERFÍCIE, LDA (Masterbetonilhas)",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "masterbetonilhas@gmail.com",
    "telefone": "966709328 / 925496301",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BETONILHAS E ENCHIMENTO; linha: 6; nome na fonte: MATERSUPERFÍCIE, LDA (Masterbetonilhas)\nAtividade: Enchimentos e betonilhas\nLocalidade/morada: Odivelas\nContactos na fonte: 966 709 328 925 496 301\nEmails na fonte: masterbetonilhas@gmail.com",
    "emails": [
      "masterbetonilhas@gmail.com"
    ],
    "phones": [
      "966709328",
      "925496301"
    ]
  },
  {
    "key": "eurobetonilhasbetonilhaseparquetslda",
    "nome": "EUROBETONILHAS - Betonilhas e Parquets, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "236211766 / 925965165",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BETONILHAS E ENCHIMENTO; linha: 8; nome na fonte: EUROBETONILHAS - Betonilhas e Parquets, Lda\nAtividade: Betonilhas e parquets\nLocalidade/morada: Pombal\nContactos na fonte: 236 211 766 925 965 165\nEmails na fonte: info@eurobetonilhas.com orcamentos@eurobetonilhaas.com",
    "emails": [
      "info@eurobetonilhas.com",
      "orcamentos@eurobetonilhaas.com"
    ],
    "phones": [
      "236211766",
      "925965165"
    ]
  },
  {
    "key": "brifatbritas",
    "nome": "BRIFAT BRITAS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "brifat@brifat.pt",
    "telefone": "249521611 / 911801419",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BETONILHAS E ENCHIMENTO; linha: 10; nome na fonte: BRIFAT BRITAS\nAtividade: Britas e Transporte\nLocalidade/morada: Fátima\nContactos na fonte: 249 521 611 911 801 419\nEmails na fonte: brifat@brifat.pt",
    "emails": [
      "brifat@brifat.pt"
    ],
    "phones": [
      "249521611",
      "911801419"
    ]
  },
  {
    "key": "buildibet",
    "nome": "BUILDIBET",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@buildibet.pt",
    "telefone": "913638362",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BETONILHAS E ENCHIMENTO; linha: 11; nome na fonte: BUILDIBET\nAtividade: Betonilhas e betão leve / betão celular\nLocalidade/morada: Rua da Horta, Nº 3 3105-170 Louriçal\nContactos na fonte: 913638362\nEmails na fonte: geral@buildibet.pt",
    "emails": [
      "geral@buildibet.pt"
    ],
    "phones": [
      "913638362"
    ]
  },
  {
    "key": "futurluz",
    "nome": "FUTURLUZ",
    "acao": "existente",
    "alvo": "2349257d-732e-42b7-8146-678c6199a1a6",
    "alvo_nome": "FUTURLUZ",
    "email": null,
    "telefone": "214318070",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BOMBAS DE ÁGUA; linha: 5; nome na fonte: FUTURLUZ\nAtividade: Bombagem e circulação de água\nLocalidade/morada: Cacém\nContactos na fonte: 214318070\nEmails na fonte: marketing@futurluz.pt\n\nFolha: ELETRICIDADE E GÁS; linha: 24; nome na fonte: FUTURLUZ\nAtividade: Material Elétricos\nLocalidade/morada: CACÉM - Rua Agualva dos Açores N15 - 214 318 070\nContactos na fonte: 214318070\nEmails na fonte: futurluz@futurluz.pt\nObservações da fonte: marketing@futurluz.pt",
    "emails": [
      "marketing@futurluz.pt",
      "futurluz@futurluz.pt"
    ],
    "phones": [
      "214318070"
    ]
  },
  {
    "key": "lisbombas",
    "nome": "Lisbombas",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@lisbombas.pt",
    "telefone": "217222290",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BOMBAS DE ÁGUA; linha: 6; nome na fonte: Lisbombas\nAtividade: Acessórios e bombas de água\nLocalidade/morada: Lisboa\nContactos na fonte: 217222290\nEmails na fonte: info@lisbombas.pt",
    "emails": [
      "info@lisbombas.pt"
    ],
    "phones": [
      "217222290"
    ]
  },
  {
    "key": "improvecompany",
    "nome": "Improve Company",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "improvecompanynow@gmail.com",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BRINDES PERSONALIZÁVEIS; linha: 5; nome na fonte: Improve Company\nAtividade: Brindes Personalizáveis\nEmails na fonte: improvecompanynow@gmail.com\nObservações da fonte: https://www.facebook.com/profile.php?id=100074304512674",
    "emails": [
      "improvecompanynow@gmail.com"
    ],
    "phones": []
  },
  {
    "key": "estudioplast",
    "nome": "EstudioPlast",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "paula.teixeira@estudioplast.com",
    "telefone": "221450354",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BRINDES PERSONALIZÁVEIS; linha: 8; nome na fonte: EstudioPlast\nAtividade: Dinamizadores de venda e suportes de comunicação ,sinais de pavimento, sinalética.\nLocalidade/morada: Vila Nova de Gaia - Portugal\nContactos na fonte: 221450354\nEmails na fonte: paula.teixeira@estudioplast.com\nObservações da fonte: www.estudioplast.com",
    "emails": [
      "paula.teixeira@estudioplast.com"
    ],
    "phones": [
      "221450354"
    ]
  },
  {
    "key": "inovartt",
    "nome": "Inovartt",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "contato@inovartt.com",
    "telefone": "935667148",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: BRINDES PERSONALIZÁVEIS; linha: 10; nome na fonte: Inovartt\nAtividade: Brindes personalizados com arte exclusiva\nLocalidade/morada: Lisboa\nContactos na fonte: 935667148\nEmails na fonte: contato@inovartt.com",
    "emails": [
      "contato@inovartt.com"
    ],
    "phones": [
      "935667148"
    ]
  },
  {
    "key": "blif",
    "nome": "Blif",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "sergio.a@blif.pt",
    "telefone": "927315079",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARREGADORES ELÉTRICOS; linha: 6; nome na fonte: Blif\nAtividade: Carregadores para veículos elétricos\nContactos na fonte: 927315079\nEmails na fonte: sergio.a@blif.pt\nObservações da fonte: https://www.blif.pt/index.html",
    "emails": [
      "sergio.a@blif.pt"
    ],
    "phones": [
      "927315079"
    ]
  },
  {
    "key": "jalusteelsa",
    "nome": "JaluSteel, SA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@jalusteel.pt",
    "telefone": "252218900",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 15; nome na fonte: JaluSteel, SA\nAtividade: Estruturas metálicas e caixilharias de alumínio\nLocalidade/morada: V.N. Famalicão\nContactos na fonte: 252218900\nEmails na fonte: geral@jalusteel.pt",
    "emails": [
      "geral@jalusteel.pt"
    ],
    "phones": [
      "252218900"
    ]
  },
  {
    "key": "caixiduartelda",
    "nome": "CaixiDuarte, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "caixiduarte@sapo.pt",
    "telefone": "214453340 / 968116050",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 16; nome na fonte: CaixiDuarte, Lda\nAtividade: Caixilharias, estores e grades\nLocalidade/morada: S. Domingos de Rana\nContactos na fonte: 214 453 340 968 116 050\nEmails na fonte: caixiduarte@sapo.pt",
    "emails": [
      "caixiduarte@sapo.pt"
    ],
    "phones": [
      "214453340",
      "968116050"
    ]
  },
  {
    "key": "drogariarodrigues",
    "nome": "Drogaria Rodrigues",
    "acao": "existente",
    "alvo": "1c7016e9-cff8-455d-ac7a-9b360552bf86",
    "alvo_nome": "Drogaria Rodrigues",
    "email": "drogariarodrigues1910@gmail.com",
    "telefone": "214680196",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 18; nome na fonte: Drogaria Rodrigues\nAtividade: Caixilharias\nLocalidade/morada: S. João do Estoril\nContactos na fonte: 214680196\nEmails na fonte: drogariarodrigues1910@gmail.com",
    "emails": [
      "drogariarodrigues1910@gmail.com"
    ],
    "phones": [
      "214680196"
    ]
  },
  {
    "key": "wiknaplast",
    "nome": "WIKNAPLAST",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "wiknaplast@wiknaplast.com",
    "telefone": "219259013 / 914568080",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 25; nome na fonte: WIKNAPLAST\nAtividade: Fabrico e montagem de caixilharia, portas e janelas PVC\nLocalidade/morada: Rua Gil Vicente, 2 Manique de Cima- Sintra\nContactos na fonte: 219 259 013 914 568 080\nEmails na fonte: wiknaplast@wiknaplast.com",
    "emails": [
      "wiknaplast@wiknaplast.com"
    ],
    "phones": [
      "219259013",
      "914568080"
    ]
  },
  {
    "key": "multiwindows",
    "nome": "MULTI-WINDOWS",
    "acao": "existente",
    "alvo": "cc244bff-3c0d-4ee8-942f-adf2383cd76d",
    "alvo_nome": "Multiwindows",
    "email": "bruno.g@multi-windows.com",
    "telefone": "210995036",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 29; nome na fonte: MULTI-WINDOWS\nAtividade: Fabrico e comercialização de janelas perfil PVC\nLocalidade/morada: Mem Martins\nContactos na fonte: 210995036\nEmails na fonte: bruno.g@multi-windows.com\nObservações da fonte: Bruno Gonçalves",
    "emails": [
      "bruno.g@multi-windows.com"
    ],
    "phones": [
      "210995036"
    ]
  },
  {
    "key": "caixilhopvc",
    "nome": "Caixilho PVC",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@caixilhopvc.pt",
    "telefone": "927648979",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 30; nome na fonte: Caixilho PVC\nAtividade: Janelas e Portas em PVC\nLocalidade/morada: ET Consiglieri Pedroso 71B, ED B F2 - Barcarena\nContactos na fonte: 927648979\nEmails na fonte: info@caixilhopvc.pt\nObservações da fonte: https://caixilhopvc.pt/#",
    "emails": [
      "info@caixilhopvc.pt"
    ],
    "phones": [
      "927648979"
    ]
  },
  {
    "key": "bancadasuperior",
    "nome": "Bancada Superior",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial2_bancadasuperior@hotmail.com",
    "telefone": "933683866",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 32; nome na fonte: Bancada Superior\nAtividade: Caixilharia de alumínio e PVC\nLocalidade/morada: Zona Industrial da Feiteirinha em Aljesur\nContactos na fonte: 933683866\nEmails na fonte: comercial2_bancadasuperior@hotmail.com",
    "emails": [
      "comercial2_bancadasuperior@hotmail.com"
    ],
    "phones": [
      "933683866"
    ]
  },
  {
    "key": "sernox",
    "nome": "Sernox",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@sernox.pt",
    "telefone": "227836041",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 33; nome na fonte: Sernox\nAtividade: Serralharia e Caixilharia\nLocalidade/morada: Vila Nova de Gaia, Portugal\nContactos na fonte: 227836041\nEmails na fonte: geral@sernox.pt\n\nFolha: SERRALHARIAS; linha: 34; nome na fonte: Sernox\nAtividade: Serralharia e Caixilharia\nLocalidade/morada: Vila Nova de Gaia, Portugal\nContactos na fonte: 227836041\nEmails na fonte: geral@sernox.pt",
    "emails": [
      "geral@sernox.pt"
    ],
    "phones": [
      "227836041"
    ]
  },
  {
    "key": "winlux",
    "nome": "Winlux",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial@winlux.pt",
    "telefone": "933545529",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 34; nome na fonte: Winlux\nAtividade: Janelas em PVC e Alumínio\nContactos na fonte: Yehor Ivanov - 933545529\nEmails na fonte: comercial@winlux.pt\nObservações da fonte: https://www.winlux.pt",
    "emails": [
      "comercial@winlux.pt"
    ],
    "phones": [
      "933545529"
    ]
  },
  {
    "key": "navarra",
    "nome": "Navarra",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "218965032",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 35; nome na fonte: Navarra\nAtividade: Sistema de alumínio para construção\nLocalidade/morada: Alameda dos Oceanos, Lisboa\nContactos na fonte: 218 965 032\nEmails na fonte: www.navarraaluminio.pt",
    "emails": [],
    "phones": [
      "218965032"
    ]
  },
  {
    "key": "caixilharia560",
    "nome": "Caixilharia560",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "caixilharia560@gmail.com",
    "telefone": "211563615",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAIXILHARIAS; linha: 37; nome na fonte: Caixilharia560\nAtividade: Especializada no fabrico e montagem de caixilharias em PVC\nLocalidade/morada: Estrada de São Marcos – Armazém nº 1 2735-521 São Marcos – Cacém\nContactos na fonte: 211563615\nEmails na fonte: caixilharia560@gmail.com",
    "emails": [
      "caixilharia560@gmail.com"
    ],
    "phones": [
      "211563615"
    ]
  },
  {
    "key": "rscconstrucaolda",
    "nome": "RSC - Construção, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "resolveparalelo.producao@gmail.com",
    "telefone": "962878197",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CALÇADAS; linha: 6; nome na fonte: RSC - Construção, Lda\nAtividade: Calçadas\nLocalidade/morada: Amadora\nContactos na fonte: 962 878 197\nEmails na fonte: resolveparalelo.producao@gmail.com",
    "emails": [
      "resolveparalelo.producao@gmail.com"
    ],
    "phones": [
      "962878197"
    ]
  },
  {
    "key": "ruidoal",
    "nome": "Rui Doal",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "934690040",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CALÇADAS; linha: 12; nome na fonte: Rui Doal\nAtividade: Calceteiro\nContactos na fonte: 934690040",
    "emails": [],
    "phones": [
      "934690040"
    ]
  },
  {
    "key": "acrimarii",
    "nome": "AcriMarII",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "acrimar.afagamentos@gmail.com",
    "telefone": "244745291 / 969061179",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CALÇADAS; linha: 14; nome na fonte: AcriMarII\nAtividade: Calceteiro\nLocalidade/morada: Fátima\nContactos na fonte: 244745291 969061179\nEmails na fonte: acrimar.afagamentos@gmail.com\nObservações da fonte: (preço de afagamento 55€m2, 26/06/2023)",
    "emails": [
      "acrimar.afagamentos@gmail.com"
    ],
    "phones": [
      "244745291",
      "969061179"
    ]
  },
  {
    "key": "lancilstreetlda",
    "nome": "LancilStreet, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "967763305",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CALÇADAS; linha: 16; nome na fonte: LancilStreet, Lda\nAtividade: Calçada, lancil, pavimento\nContactos na fonte: 967763305\nObservações da fonte: Nuno Lázaro",
    "emails": [],
    "phones": [
      "967763305"
    ]
  },
  {
    "key": "caleiratorres",
    "nome": "Caleira Torres",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@caldeiratorres.pt",
    "telefone": "910362601 / 919553205 / 261331644",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CALEIRAS; linha: 6; nome na fonte: Caleira Torres\nAtividade: Fabrico e montagem de Caleiras, Algerozes e Remate em alumínio\nLocalidade/morada: Rua frei Paulo de Sta Tereza - Torres Vedras\nContactos na fonte: 910 362 601 919 553 205 261 331 644\nEmails na fonte: geral@caldeiratorres.pt",
    "emails": [
      "geral@caldeiratorres.pt"
    ],
    "phones": [
      "910362601",
      "919553205",
      "261331644"
    ]
  },
  {
    "key": "jmdr",
    "nome": "JMDR",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "969063015",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CANALIZADOR; linha: 11; nome na fonte: JMDR\nAtividade: Roturas, Desentupimentos, Infiltrações, Peritagens\nContactos na fonte: 969063015",
    "emails": [],
    "phones": [
      "969063015"
    ]
  },
  {
    "key": "plastimorgado",
    "nome": "PlastiMorgado",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral.plastimorgado@gmail.com",
    "telefone": "919909582",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CANALIZADOR; linha: 13; nome na fonte: PlastiMorgado\nAtividade: Acessórios de Canalização\nLocalidade/morada: Pombal\nContactos na fonte: 919909582\nEmails na fonte: geral.plastimorgado@gmail.com\n\nFolha: CLIMATIZAÇÃO; linha: 14; nome na fonte: PlastiMorgado\nAtividade: Aquecimento, Ventilação, Ar Condicionado\nLocalidade/morada: Pombal\nContactos na fonte: 919909582\nEmails na fonte: geral.plastimorgado@gmail.com\nObservações da fonte: mais sistema de regas de jardim, produtos elétricos, tubagem, aspiração central, acessórios de canalização, saneamento, gás,…",
    "emails": [
      "geral.plastimorgado@gmail.com"
    ],
    "phones": [
      "919909582"
    ]
  },
  {
    "key": "faustaguas",
    "nome": "FAUSTÁGUAS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "faustaguas@hotmail.com",
    "telefone": "263978495",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CANALIZADOR; linha: 16; nome na fonte: FAUSTÁGUAS\nAtividade: Instalações de Canalizações\nLocalidade/morada: Arruda dos Vinhos\nContactos na fonte: 263978495\nEmails na fonte: faustaguas@hotmail.com",
    "emails": [
      "faustaguas@hotmail.com"
    ],
    "phones": [
      "263978495"
    ]
  },
  {
    "key": "marmorexiiinternacionallda",
    "nome": "MARMOREX II INTERNACIONAL, LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@marmorex.pt",
    "telefone": "219672567",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CANTARIAS E BANCADAS DE COZINHA; linha: 5; nome na fonte: MARMOREX II INTERNACIONAL, LDA\nAtividade: Mármores, Calcários, Granitos, Quartz Compac, Corian e Silestone\nLocalidade/morada: Quinta das Bicas Mafra\nContactos na fonte: 219672567\nEmails na fonte: geral@marmorex.pt",
    "emails": [
      "geral@marmorex.pt"
    ],
    "phones": [
      "219672567"
    ]
  },
  {
    "key": "isol2006",
    "nome": "ISOL 2006",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@isol.pt",
    "telefone": "214781271",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAPOTO; linha: 5; nome na fonte: ISOL 2006\nAtividade: Serviços de Impermeabilizações, Pinturas e Reabilitação e Isolamento Térmico pelo exterior (Capoto).\nLocalidade/morada: Odivelas\nContactos na fonte: 214 781 271\nEmails na fonte: geral@isol.pt",
    "emails": [
      "geral@isol.pt"
    ],
    "phones": [
      "214781271"
    ]
  },
  {
    "key": "horacioboaventuraunipessoallda",
    "nome": "HORÁCIO BOAVENTURA, UNIPESSOAL, LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@horaciosolucoes.pt",
    "telefone": "214081580 / 969633399",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAPOTO; linha: 7; nome na fonte: HORÁCIO BOAVENTURA, UNIPESSOAL, LDA\nAtividade: Isolamento térmico, capoto, impermeabilizações, pinturas, assentamento do ladrilhos\nLocalidade/morada: Rua Francisco Lucas Pires, 24, GR, 2735-088 Agualva Cacém\nContactos na fonte: 214 081 580 969 633 399\nEmails na fonte: geral@horaciosolucoes.pt",
    "emails": [
      "geral@horaciosolucoes.pt"
    ],
    "phones": [
      "214081580",
      "969633399"
    ]
  },
  {
    "key": "renovaz",
    "nome": "RENOVAZ",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "joaopcvaz@hotmail.com",
    "telefone": "910856329",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAPOTO; linha: 10; nome na fonte: RENOVAZ\nAtividade: Revestimento térmico ETIC'S (capoto)\nLocalidade/morada: Gândaras Lousã\nContactos na fonte: 910856329\nEmails na fonte: joaopcvaz@hotmail.com",
    "emails": [
      "joaopcvaz@hotmail.com"
    ],
    "phones": [
      "910856329"
    ]
  },
  {
    "key": "isohome",
    "nome": "ISOHOME",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@isohome.pt",
    "telefone": "928158099",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAPOTO; linha: 11; nome na fonte: ISOHOME\nAtividade: Fornecimento e aplicação do sistema de isolamento térmico etics/ cappoto\nLocalidade/morada: Rua Capitão Salgueiro Maia, Loja 1, Lote 124\nContactos na fonte: 928 158 099\nEmails na fonte: geral@isohome.Pt",
    "emails": [
      "geral@isohome.pt"
    ],
    "phones": [
      "928158099"
    ]
  },
  {
    "key": "bauterportugal",
    "nome": "Bauter Portugal",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "926181497",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAPOTO; linha: 12; nome na fonte: Bauter Portugal\nAtividade: Isolamento térmico de base nanotecnológica\nLocalidade/morada: Alameda da Beloura Edfifício 6 , Loja 4\nContactos na fonte: 351926181497\nEmails na fonte: www.bauter.pt",
    "emails": [],
    "phones": [
      "926181497"
    ]
  },
  {
    "key": "esferacristalizada",
    "nome": "Esfera Cristalizada",
    "acao": "existente",
    "alvo": "1ef39495-20a4-44dc-b0ca-dc9589e03cf7",
    "alvo_nome": "Esfera Cristalizada, Lda",
    "email": "esferacristalizada@gmail.com",
    "telefone": "967402564",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CAROTES; linha: 6; nome na fonte: Esfera Cristalizada\nAtividade: Abertura de carotes\nContactos na fonte: 967 402 564\nEmails na fonte: esferacristalizada@gmail.com\nObservações da fonte: Sr. Alexandre",
    "emails": [
      "esferacristalizada@gmail.com"
    ],
    "phones": [
      "967402564"
    ]
  },
  {
    "key": "globaldissadistribuidorexclusivovicaima",
    "nome": "Globaldis S.A. Distribuidor exclusivo Vicaima",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@globaldis.pt",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 9; nome na fonte: Globaldis S.A. Distribuidor exclusivo Vicaima\nAtividade: Porta, pavimentos, painéis em madeira\nLocalidade/morada: Lisboa\nContactos na fonte: 808 50 50 30\nEmails na fonte: geral@globaldis.pt",
    "emails": [
      "geral@globaldis.pt"
    ],
    "phones": []
  },
  {
    "key": "artesimetrica",
    "nome": "Arte Simétrica",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@artesimetrica.com",
    "telefone": "914863822",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 10; nome na fonte: Arte Simétrica\nAtividade: Carpintarias\nLocalidade/morada: Ourém\nContactos na fonte: 914 863 822\nEmails na fonte: geral@artesimetrica.com",
    "emails": [
      "geral@artesimetrica.com"
    ],
    "phones": [
      "914863822"
    ]
  },
  {
    "key": "jjteixeirasa",
    "nome": "J&J TEIXEIRA, S.A.",
    "acao": "existente",
    "alvo": "0809937e-79e5-47f1-877a-9adbd4037c09",
    "alvo_nome": "J.& J.teixeira S.A",
    "email": "geral@jjteixeira.pt",
    "telefone": "227878400",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 12; nome na fonte: J&J TEIXEIRA, S.A.\nAtividade: Carpintarias\nLocalidade/morada: Vila Nova de Gaia\nContactos na fonte: 227 878 400\nEmails na fonte: geral@jjteixeira.pt",
    "emails": [
      "geral@jjteixeira.pt"
    ],
    "phones": [
      "227878400"
    ]
  },
  {
    "key": "movwood",
    "nome": "Movwood",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@movwood.pt",
    "telefone": "261249852",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 13; nome na fonte: Movwood\nAtividade: Carpintarias\nLocalidade/morada: Mafra\nContactos na fonte: 261 249 852\nEmails na fonte: geral@movwood.pt",
    "emails": [
      "geral@movwood.pt"
    ],
    "phones": [
      "261249852"
    ]
  },
  {
    "key": "bamersa",
    "nome": "BAMER, SA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "214919105",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 15; nome na fonte: BAMER, SA\nAtividade: Divisórias, Carpintarias\nLocalidade/morada: Oeiras\nContactos na fonte: 214 919 105",
    "emails": [],
    "phones": [
      "214919105"
    ]
  },
  {
    "key": "ergowoodconstrucaocivilunipessoallda",
    "nome": "Ergowood - Construção Civil Unipessoal, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@ergowwod.pt",
    "telefone": "967023270",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 16; nome na fonte: Ergowood - Construção Civil Unipessoal, Lda\nAtividade: Carpintarias, isolamentos, fachadas\nLocalidade/morada: Pombal\nContactos na fonte: 967 023 270\nEmails na fonte: geral@ergowwod.pt\nObservações da fonte: Vitor Rodrigues",
    "emails": [
      "geral@ergowwod.pt"
    ],
    "phones": [
      "967023270"
    ]
  },
  {
    "key": "powercode",
    "nome": "Powercode",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "powercode@powercode.pt",
    "telefone": "253590260",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 23; nome na fonte: Powercode\nAtividade: Carpintarias\nLocalidade/morada: Fafe\nContactos na fonte: 253 590 260\nEmails na fonte: powercode@powercode.pt",
    "emails": [
      "powercode@powercode.pt"
    ],
    "phones": [
      "253590260"
    ]
  },
  {
    "key": "carpigoncalveslda",
    "nome": "Carpigonçalves, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "912326667",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 27; nome na fonte: Carpigonçalves, Lda\nAtividade: Carpintarias\nLocalidade/morada: Braga\nContactos na fonte: 912326667",
    "emails": [],
    "phones": [
      "912326667"
    ]
  },
  {
    "key": "cimacamateriaisdeconstrucaosa",
    "nome": "Cimaca - Materiais de Construção, SA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "cimaca@cimaca.pt",
    "telefone": "227877330",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 31; nome na fonte: Cimaca - Materiais de Construção, SA\nAtividade: Carpintaria, materiais de construção\nLocalidade/morada: V.N. Gaia\nContactos na fonte: 227877330\nEmails na fonte: cimaca@cimaca.pt",
    "emails": [
      "cimaca@cimaca.pt"
    ],
    "phones": [
      "227877330"
    ]
  },
  {
    "key": "lockdoor",
    "nome": "Lockdoor",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "967469317",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 33; nome na fonte: Lockdoor\nAtividade: Carpintarias\nLocalidade/morada: Leiria\nContactos na fonte: 967469317\nObservações da fonte: Antonio Vilar",
    "emails": [],
    "phones": [
      "967469317"
    ]
  },
  {
    "key": "movilima",
    "nome": "MOVILIMA",
    "acao": "existente",
    "alvo": "eb30a1b7-6d6c-4b8d-99cd-7e45874edbb5",
    "alvo_nome": "Movilima, Lda",
    "email": null,
    "telefone": "214320832 / 934023035",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 41; nome na fonte: MOVILIMA\nAtividade: Comércio de Mobiliário, Importação, Exportação, Lda\nLocalidade/morada: Bairro Serrado Nv, Lote 46 A/B Idanha 2605-114 Belas\nContactos na fonte: 214 320 832 934 023 035\nEmails na fonte: movilima@sapo.pt geral@movilima.pt\nObservações da fonte: Sr. Saúl Lima",
    "emails": [
      "movilima@sapo.pt",
      "geral@movilima.pt"
    ],
    "phones": [
      "214320832",
      "934023035"
    ]
  },
  {
    "key": "rswoodmontagemcarpintaria",
    "nome": "RS WOOD - Montagem Carpintaria",
    "acao": "existente",
    "alvo": "dfc64000-e26f-4883-8813-aa4eea51e9c9",
    "alvo_nome": "RS Wood - Montagem Carpintaria",
    "email": "rodolfosilvawood@gmail.com",
    "telefone": "917872467",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CARPINTARIAS; linha: 42; nome na fonte: RS WOOD - Montagem Carpintaria\nAtividade: Soalhos, Decks, Portas, Pavimentos Flutuantes\nContactos na fonte: 917872467\nEmails na fonte: rodolfosilvawood@gmail.com\nObservações da fonte: Obra António Loma em Cascais",
    "emails": [
      "rodolfosilvawood@gmail.com"
    ],
    "phones": [
      "917872467"
    ]
  },
  {
    "key": "quintafachada",
    "nome": "Quinta Fachada",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@quintafachada.pt",
    "telefone": "914400158 / 211370492",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CHAMINÉS E LAREIRAS; linha: 5; nome na fonte: Quinta Fachada\nAtividade: Chaminés, telhados, algerozes\nLocalidade/morada: S. Domingos de Rana\nContactos na fonte: 914 400 158 211 370 492\nEmails na fonte: geral@quintafachada.pt\nObservações da fonte: Limpeza e manutenção",
    "emails": [
      "geral@quintafachada.pt"
    ],
    "phones": [
      "914400158",
      "211370492"
    ]
  },
  {
    "key": "lusostonelda",
    "nome": "Lusostone, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "962783722 / 232560060",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CHAMINÉS E LAREIRAS; linha: 7; nome na fonte: Lusostone, Lda\nAtividade: Lareiras neoclássicas em pedra\nLocalidade/morada: Mafra\nContactos na fonte: 962 783 722\nEmails na fonte: info@lusostone.com\n\nFolha: CHAMINÉS E LAREIRAS; linha: 8; nome na fonte: Lusostone, Lda\nAtividade: Lareiras neoclássicas em pedra\nLocalidade/morada: Sátão\nContactos na fonte: 232 560 060\nEmails na fonte: geral@lusostone.pt",
    "emails": [
      "info@lusostone.com",
      "geral@lusostone.pt"
    ],
    "phones": [
      "962783722",
      "232560060"
    ]
  },
  {
    "key": "gargulagotica",
    "nome": "Gárgula Gótica",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "913725108 / 244767122",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CHAMINÉS E LAREIRAS; linha: 9; nome na fonte: Gárgula Gótica\nAtividade: Lareiras e esculturas em pedra natural\nLocalidade/morada: Batalha\nContactos na fonte: 913 725 108 244 767 122\nObservações da fonte: Ana Sebastião",
    "emails": [],
    "phones": [
      "913725108",
      "244767122"
    ]
  },
  {
    "key": "clearfire",
    "nome": "ClearFire",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "cascais@clearfire.pt",
    "telefone": "314211344",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CHAMINÉS E LAREIRAS; linha: 11; nome na fonte: ClearFire\nAtividade: Lareiras Elétricas\nLocalidade/morada: Av. Infante Dom Henrique\nContactos na fonte: 314211344\nEmails na fonte: cascais@clearfire.pt\nObservações da fonte: www.clearfire.pt",
    "emails": [
      "cascais@clearfire.pt"
    ],
    "phones": [
      "314211344"
    ]
  },
  {
    "key": "shelterder",
    "nome": "Shelterder",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "220503460",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CHAMINÉS E LAREIRAS; linha: 13; nome na fonte: Shelterder\nAtividade: Desenvolvimento e produção de lareiras de design exclusivo, de combustão a lenha, gás, BEV bioetanol e vapor de água.\nLocalidade/morada: Lisboa e Algarve\nContactos na fonte: (+351) 220 503 460\nEmails na fonte: www.shelter.com",
    "emails": [],
    "phones": [
      "220503460"
    ]
  },
  {
    "key": "imaginaryclima",
    "nome": "Imaginaryclima",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "imaginaryclima@gmail.com",
    "telefone": "968493606",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 5; nome na fonte: Imaginaryclima\nAtividade: Ar Condicionado\nLocalidade/morada: Arruda dos Vinhos\nContactos na fonte: 968 493 606\nEmails na fonte: imaginaryclima@gmail.com",
    "emails": [
      "imaginaryclima@gmail.com"
    ],
    "phones": [
      "968493606"
    ]
  },
  {
    "key": "daikinairconditioningportugal",
    "nome": "Daikin Airconditioning Portugal",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "214268700 / 963076828",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 6; nome na fonte: Daikin Airconditioning Portugal\nAtividade: Ar condicionado, aquecimento e bombas solares, sistemas agua quente\nLocalidade/morada: Paço d'Arcos\nContactos na fonte: 21 426 8700 963 076 828",
    "emails": [],
    "phones": [
      "214268700",
      "963076828"
    ]
  },
  {
    "key": "easyheat",
    "nome": "EasyHeat",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@easyheat.pt",
    "telefone": "961671755",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 9; nome na fonte: EasyHeat\nAtividade: Aquecimento infravermelho\nLocalidade/morada: Queluz\nContactos na fonte: 961671755\nEmails na fonte: geral@easyheat.pt",
    "emails": [
      "geral@easyheat.pt"
    ],
    "phones": [
      "961671755"
    ]
  },
  {
    "key": "frigoair",
    "nome": "Frigoair",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "939262771",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 10; nome na fonte: Frigoair\nAtividade: AVAC\nLocalidade/morada: (margem Sul)\nContactos na fonte: 939262771\nObservações da fonte: Sr. Agostinho",
    "emails": [],
    "phones": [
      "939262771"
    ]
  },
  {
    "key": "windline",
    "nome": "Windline",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@windline.pt",
    "telefone": "935363219",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 11; nome na fonte: Windline\nAtividade: Ar condicionado, exaustão de gases, desenfumagem, ventilação, painéis solares, frigoríficos industriais\nLocalidade/morada: Alverca do Ribatejo\nContactos na fonte: 935363219\nEmails na fonte: geral@windline.pt",
    "emails": [
      "geral@windline.pt"
    ],
    "phones": [
      "935363219"
    ]
  },
  {
    "key": "erfolconter",
    "nome": "ERFOLCONTER",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geralmontijo@erfolconter.pt",
    "telefone": "210927680",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 12; nome na fonte: ERFOLCONTER\nAtividade: Comercialização, instalação de equipamentos de climatização e energias renováveis\nLocalidade/morada: Armazém 21 – Estrada Nacional 5, Afonsoeiro, 2870-500 Montijo\nContactos na fonte: 210927680\nEmails na fonte: geralmontijo@erfolconter.pt\nObservações da fonte: Dora Silva | Filial Montijo\n\nFolha: SUBEMPREITEIRO GERAL; linha: 29; nome na fonte: ERFOLCONTER\nAtividade: Comercialização, instalação de equipamentos de climatização e energias renováveis\nLocalidade/morada: Montijo\nContactos na fonte: 210927680\nEmails na fonte: geralmontijo@erfolconter.pt",
    "emails": [
      "geralmontijo@erfolconter.pt"
    ],
    "phones": [
      "210927680"
    ]
  },
  {
    "key": "krarcondicionadoeenergiasrenovaveis",
    "nome": "KR - AR CONDICIONADO E ENERGIAS RENOVÁVEIS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "gestao.kr@gmail.com",
    "telefone": "216027376 / 934694490",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 15; nome na fonte: KR - AR CONDICIONADO E ENERGIAS RENOVÁVEIS\nAtividade: Ar Condicionado, Bombas de Calor, Energias Renováveis, Ventilação\nLocalidade/morada: Rua Emídio da Conceição Fernandes, 6B 2700-803 Amadora\nContactos na fonte: 216 027 376 934 694 490\nEmails na fonte: gestao.kr@gmail.com",
    "emails": [
      "gestao.kr@gmail.com"
    ],
    "phones": [
      "216027376",
      "934694490"
    ]
  },
  {
    "key": "copraxsa",
    "nome": "COPRAX S.A",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "ulisses.carvalho@coprax.com",
    "telefone": "256579480",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CLIMATIZAÇÃO; linha: 20; nome na fonte: COPRAX S.A\nAtividade: Desenvolvimento e fornecimento de sistemas de tubos e acessórios para redes hidráulicas e AVAC.\nLocalidade/morada: Av. 16 de Maio | Zona Ind. Ovar | 3880 - 102 Ovar - Portugal\nContactos na fonte: 256 579 480\nEmails na fonte: ulisses.carvalho@coprax.com",
    "emails": [
      "ulisses.carvalho@coprax.com"
    ],
    "phones": [
      "256579480"
    ]
  },
  {
    "key": "asousaalvesrevestimentosdezincoecobrelda",
    "nome": "A. Sousa Alves - Revestimentos de Zinco e cobre, Lda",
    "acao": "existente",
    "alvo": "de7da5f7-f62e-484a-ba54-0c9a8a564646",
    "alvo_nome": "A. Sousa Alves - Revestimentos de Zinco e Cobre Lda",
    "email": "orcamentos@asa.com.pt",
    "telefone": "224337330",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COBERTURAS E RUFOS EM ZINCO; linha: 9; nome na fonte: A. Sousa Alves - Revestimentos de Zinco e cobre, Lda\nAtividade: Coberturas e rufos em zinco\nLocalidade/morada: Paredes\nContactos na fonte: 224337330\nEmails na fonte: orcamentos@asa.com.pt",
    "emails": [
      "orcamentos@asa.com.pt"
    ],
    "phones": [
      "224337330"
    ]
  },
  {
    "key": "style4bungalows",
    "nome": "Style4bungalows",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@style4bungalows.com",
    "telefone": "239850000",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CONST.BUNGALLOWS E PRÉ-FABRICAD; linha: 5; nome na fonte: Style4bungalows\nAtividade: Bungalows contemporâneos\nContactos na fonte: 239 850 000\nEmails na fonte: info@style4bungalows.com",
    "emails": [
      "info@style4bungalows.com"
    ],
    "phones": [
      "239850000"
    ]
  },
  {
    "key": "prninformatica",
    "nome": "PRN - Informática",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial@prn.pt",
    "telefone": "224157620",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CONSUMÍVEIS ; linha: 6; nome na fonte: PRN - Informática\nAtividade: Informática / Consumíveis\nLocalidade/morada: Rebordosa\nContactos na fonte: 224157620\nEmails na fonte: comercial@prn.pt\nObservações da fonte: Sr. Rui Neves",
    "emails": [
      "comercial@prn.pt"
    ],
    "phones": [
      "224157620"
    ]
  },
  {
    "key": "inforsilva",
    "nome": "Inforsilva",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial@inforsilva.pt",
    "telefone": "255341132",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: CONSUMÍVEIS ; linha: 7; nome na fonte: Inforsilva\nAtividade: Software online de gestão de obras\nLocalidade/morada: Rua Tenente Coronel António Emídio Moreira Peixoto\nContactos na fonte: 255341132\nEmails na fonte: comercial@inforsilva.pt\nObservações da fonte: inforsilva.pt",
    "emails": [
      "comercial@inforsilva.pt"
    ],
    "phones": [
      "255341132"
    ]
  },
  {
    "key": "cozidias",
    "nome": "Cozidias",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@cozidias.pt",
    "telefone": "224150442 / 910108498",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 5; nome na fonte: Cozidias\nAtividade: Cozinhas, Roupeiros, móveis banho\nLocalidade/morada: Cascais\nContactos na fonte: 224 150 442 910 108 498\nEmails na fonte: geral@cozidias.pt",
    "emails": [
      "geral@cozidias.pt"
    ],
    "phones": [
      "224150442",
      "910108498"
    ]
  },
  {
    "key": "masterkitchen",
    "nome": "MasterKitchen",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@masterkitchen.pt",
    "telefone": "236948053",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 7; nome na fonte: MasterKitchen\nAtividade: Cozinhas\nLocalidade/morada: Pombal\nContactos na fonte: 236 948 053\nEmails na fonte: geral@masterkitchen.pt",
    "emails": [
      "geral@masterkitchen.pt"
    ],
    "phones": [
      "236948053"
    ]
  },
  {
    "key": "cenariwood",
    "nome": "CENARIWOOD",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@cenariwood.pt",
    "telefone": "212250634",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 8; nome na fonte: CENARIWOOD\nAtividade: Roupeiros e Cozinhas\nLocalidade/morada: Quinta do Anjo\nContactos na fonte: 212250634\nEmails na fonte: info@cenariwood.pt",
    "emails": [
      "info@cenariwood.pt"
    ],
    "phones": [
      "212250634"
    ]
  },
  {
    "key": "belchans",
    "nome": "Belchans",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "belchans@sapo.pt",
    "telefone": "219889390",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 9; nome na fonte: Belchans\nAtividade: Cozinhas\nLocalidade/morada: Loures\nContactos na fonte: 219889390\nEmails na fonte: belchans@sapo.pt",
    "emails": [
      "belchans@sapo.pt"
    ],
    "phones": [
      "219889390"
    ]
  },
  {
    "key": "arktiles",
    "nome": "ARKTILES",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "ketan.arktiles@gmail.com",
    "telefone": "912103280",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 11; nome na fonte: ARKTILES\nAtividade: bancadas cozinhas contemporâneos de espessura fina\nLocalidade/morada: Alcabideche\nContactos na fonte: 912103280\nEmails na fonte: ketan.arktiles@gmail.com\nObservações da fonte: Ketan Dhokia\n\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 22; nome na fonte: ARKTILES\nAtividade: Torneiras, sistemas de duche e wellness\nLocalidade/morada: Alcabideche\nContactos na fonte: 912103280\nEmails na fonte: ketan.arktiles@gmail.com\nObservações da fonte: Ketan Dhokia\n\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 12; nome na fonte: ARKTILES\nAtividade: Revestimentos cerâmicos e pedra\nLocalidade/morada: Alcabideche\nContactos na fonte: 912103280\nEmails na fonte: ketan.arktiles@gmail.com\nObservações da fonte: Ketan Dhokia",
    "emails": [
      "ketan.arktiles@gmail.com"
    ],
    "phones": [
      "912103280"
    ]
  },
  {
    "key": "lusokit",
    "nome": "LUSOKIT",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@lusokit.com",
    "telefone": "289704758",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 12; nome na fonte: LUSOKIT\nAtividade: Fabrico de cozinhas\nLocalidade/morada: Zona industrial de Olhão, Rua 14 lote 239 8700-281 Olhão\nContactos na fonte: 289704758\nEmails na fonte: geral@lusokit.com\nObservações da fonte: Departamento Comercial Jessica Melo Contacto : 913285151 (custo chamada rede móvel)",
    "emails": [
      "geral@lusokit.com"
    ],
    "phones": [
      "289704758"
    ]
  },
  {
    "key": "pedrosafilhos",
    "nome": "Pedrosa & Filhos",
    "acao": "existente",
    "alvo": "9ca62a23-d498-42fc-b6b0-b3c868ec0f30",
    "alvo_nome": "Pedrosa & Filhos",
    "email": "ruicarvalho@pedrosaefilhos.com",
    "telefone": "910534300",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 13; nome na fonte: Pedrosa & Filhos\nAtividade: Fabricação, acabamentos e montagem de cozinhas, roupeiros e bancadas.\nLocalidade/morada: Rua das Cavadas nº44 Cavadas da Bouça, 2425-184 Bajouca\nContactos na fonte: 910534300\nEmails na fonte: ruicarvalho@pedrosaefilhos.com\nObservações da fonte: www.pedrosaefilhos.com\n\nFolha: FORNECEDORES; linha: 8; nome na fonte: Pedrosa & Filhos\nAtividade: Fornecem fabrico de mobiliário de cozinhas salas de banho, roupeiros, escadas e móveis por medida.\nLocalidade/morada: Rua das Cavadas Nº 44 - Bajouca Leiria 2425-184\nContactos na fonte: 910534300\nEmails na fonte: ruicarvalho@pedrosaefilhos.com\nObservações da fonte: www.pedrosaefilhos.com",
    "emails": [
      "ruicarvalho@pedrosaefilhos.com"
    ],
    "phones": [
      "910534300"
    ]
  },
  {
    "key": "cozitracos",
    "nome": "Cozitraços",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "ruifiuza.cozitracos@gmail.com",
    "telefone": "933654044",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: COZINHAS, MÓVEIS E ROUPEIROS; linha: 14; nome na fonte: Cozitraços\nAtividade: Cozinhas, roupeiros, portas, pavimentos ETC\nContactos na fonte: 933 654 044\nEmails na fonte: ruifiuza.cozitracos@gmail.com",
    "emails": [
      "ruifiuza.cozitracos@gmail.com"
    ],
    "phones": [
      "933654044"
    ]
  },
  {
    "key": "demobetao",
    "nome": "Demobetão",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@demobetao.pt",
    "telefone": "249381975",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DEMOLIÇÕES E CORTE DE BETÃO; linha: 8; nome na fonte: Demobetão\nAtividade: Demolição de Betão\nLocalidade/morada: Tomar\nContactos na fonte: 249381975\nEmails na fonte: geral@demobetao.pt",
    "emails": [
      "geral@demobetao.pt"
    ],
    "phones": [
      "249381975"
    ]
  },
  {
    "key": "democorte",
    "nome": "Democorte",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@democorte.pt",
    "telefone": "212102316",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DEMOLIÇÕES E CORTE DE BETÃO; linha: 9; nome na fonte: Democorte\nAtividade: Acabamentos na área da construção\nContactos na fonte: 212102316\nEmails na fonte: geral@democorte.pt",
    "emails": [
      "geral@democorte.pt"
    ],
    "phones": [
      "212102316"
    ]
  },
  {
    "key": "plenodinamismo",
    "nome": "Pleno Dinamismo",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "927584616",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DEMOLIÇÕES E CORTE DE BETÃO; linha: 15; nome na fonte: Pleno Dinamismo\nAtividade: Demolições\nLocalidade/morada: R. Francisco Costa 15, 2635-277 Rinchoa\nContactos na fonte: 927584616",
    "emails": [],
    "phones": [
      "927584616"
    ]
  },
  {
    "key": "ecopraga",
    "nome": "Ecopraga",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@ecopraga.pt",
    "telefone": "243556184",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DESINFESTAÇÕES; linha: 5; nome na fonte: Ecopraga\nAtividade: Desinfestaçoes\nLocalidade/morada: Alpiarça\nContactos na fonte: 243556184\nEmails na fonte: geral@ecopraga.pt",
    "emails": [
      "geral@ecopraga.pt"
    ],
    "phones": [
      "243556184"
    ]
  },
  {
    "key": "tecnoescava",
    "nome": "Tecnoescava",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "tecnoescava@hotmail.com",
    "telefone": "962525100",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DESMATAÇÃO E MOVIMENTO DE T ; linha: 8; nome na fonte: Tecnoescava\nAtividade: Transporte e terraplanagens\nLocalidade/morada: São Domingos de Rana\nContactos na fonte: 962525100\nEmails na fonte: tecnoescava@hotmail.com",
    "emails": [
      "tecnoescava@hotmail.com"
    ],
    "phones": [
      "962525100"
    ]
  },
  {
    "key": "fadasapressadasunipessoallda",
    "nome": "FADAS APRESSADAS UNIPESSOAL LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "fadasapressadas@gmail.com",
    "telefone": "962318901",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DESMATAÇÃO E MOVIMENTO DE T ; linha: 11; nome na fonte: FADAS APRESSADAS UNIPESSOAL LDA\nAtividade: Ferro e cofragem\nLocalidade/morada: Cacém\nContactos na fonte: 962 318 901\nEmails na fonte: fadasapressadas@gmail.com\nObservações da fonte: Gil Vaz",
    "emails": [
      "fadasapressadas@gmail.com"
    ],
    "phones": [
      "962318901"
    ]
  },
  {
    "key": "ideiasarejadasconstrucoeslda",
    "nome": "Ideias Arejadas - Construções, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "ideiasarejadas@sapo.pt",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DESMATAÇÃO E MOVIMENTO DE T ; linha: 12; nome na fonte: Ideias Arejadas - Construções, Lda\nAtividade: Escavações e Terraplanagens\nLocalidade/morada: Sobral de Monte Agraço\nEmails na fonte: ideiasarejadas@sapo.pt\nObservações da fonte: Pedro Bizarro",
    "emails": [
      "ideiasarejadas@sapo.pt"
    ],
    "phones": []
  },
  {
    "key": "mafrimaquinas",
    "nome": "Mafrimáquinas",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "mafrimaquinas@mail.telepac.pt",
    "telefone": "210451554",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DESMATAÇÃO E MOVIMENTO DE T ; linha: 16; nome na fonte: Mafrimáquinas\nAtividade: TERRAPLANAGENS E CONSTRUÇÃO CIVIL\nLocalidade/morada: Mafra\nContactos na fonte: 210451554\nEmails na fonte: mafrimaquinas@mail.telepac.pt",
    "emails": [
      "mafrimaquinas@mail.telepac.pt"
    ],
    "phones": [
      "210451554"
    ]
  },
  {
    "key": "arvorespessoaslda",
    "nome": "Árvores & Pessoas LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@arvores-e-pessoas.pt",
    "telefone": "231205243",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DESMATAÇÃO E MOVIMENTO DE T ; linha: 18; nome na fonte: Árvores & Pessoas LDA\nAtividade: Poda seletiva, Desmontagem de Árvores, Limpeza de palmeiras\nLocalidade/morada: Mealhada\nContactos na fonte: 231205243\nEmails na fonte: geral@arvores-e-pessoas.pt",
    "emails": [
      "geral@arvores-e-pessoas.pt"
    ],
    "phones": [
      "231205243"
    ]
  },
  {
    "key": "smartav",
    "nome": "SMARTAV",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "md@smartav.pt",
    "telefone": "939063861",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DOMÓTICA, HOME CINEMA; linha: 5; nome na fonte: SMARTAV\nAtividade: Domótica e home cinema\nLocalidade/morada: Lisboa\nContactos na fonte: 939063861\nEmails na fonte: md@smartav.pt\nObservações da fonte: Marco Dias",
    "emails": [
      "md@smartav.pt"
    ],
    "phones": [
      "939063861"
    ]
  },
  {
    "key": "doeasy",
    "nome": "DOEASY",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "tiago.afonso@doeasy.pt",
    "telefone": "911194153",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: DOMÓTICA, HOME CINEMA; linha: 6; nome na fonte: DOEASY\nAtividade: Domótica (automação residencial)\nContactos na fonte: 911194153\nEmails na fonte: tiago.afonso@doeasy.pt",
    "emails": [
      "tiago.afonso@doeasy.pt"
    ],
    "phones": [
      "911194153"
    ]
  },
  {
    "key": "luzimeca",
    "nome": "Luzimeca",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "luzimeca@luzimeca.pt",
    "telefone": "219106710",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 5; nome na fonte: Luzimeca\nAtividade: REDES HIDRÁULICAS, ELÉTRICAS, SOLAR TÉRMICO, GÁS\nLocalidade/morada: Sintra\nContactos na fonte: 219 106 710\nEmails na fonte: luzimeca@luzimeca.pt",
    "emails": [
      "luzimeca@luzimeca.pt"
    ],
    "phones": [
      "219106710"
    ]
  },
  {
    "key": "instalcentro",
    "nome": "Instalcentro",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "administrativo@instalcentro.pt",
    "telefone": "244612236",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 8; nome na fonte: Instalcentro\nAtividade: Eletricidade e canalização\nLocalidade/morada: Carvide\nContactos na fonte: 244 612 236\nEmails na fonte: administrativo@instalcentro.pt",
    "emails": [
      "administrativo@instalcentro.pt"
    ],
    "phones": [
      "244612236"
    ]
  },
  {
    "key": "gasquatro",
    "nome": "Gasquatro",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@gasquatro.com",
    "telefone": "263470280",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 9; nome na fonte: Gasquatro\nAtividade: Instalação E Manutenção De Redes De Gás\nLocalidade/morada: Lisboa\nContactos na fonte: 263 470 280\nEmails na fonte: geral@gasquatro.com",
    "emails": [
      "geral@gasquatro.com"
    ],
    "phones": [
      "263470280"
    ]
  },
  {
    "key": "microamper",
    "nome": "MICROAMPER",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral.microamper@gmail.com",
    "telefone": "223249747",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 11; nome na fonte: MICROAMPER\nAtividade: Eletricidade e telecomunicações\nLocalidade/morada: Lamelas\nContactos na fonte: 223249747\nEmails na fonte: geral.microamper@gmail.com",
    "emails": [
      "geral.microamper@gmail.com"
    ],
    "phones": [
      "223249747"
    ]
  },
  {
    "key": "eresolux",
    "nome": "eResolux",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "eresolux@gmail.com",
    "telefone": "210127595",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 13; nome na fonte: eResolux\nAtividade: Instalações Elétricas\nLocalidade/morada: Alcabideche\nContactos na fonte: 210127595\nEmails na fonte: eresolux@gmail.com",
    "emails": [
      "eresolux@gmail.com"
    ],
    "phones": [
      "210127595"
    ]
  },
  {
    "key": "instaltejo",
    "nome": "INSTALTEJO",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@instaltejo.pt",
    "telefone": "212684533",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 14; nome na fonte: INSTALTEJO\nAtividade: Instalaçoes elétricas, ITED e segurança\nLocalidade/morada: Sesimbra\nContactos na fonte: 212684533\nEmails na fonte: geral@instaltejo.pt",
    "emails": [
      "geral@instaltejo.pt"
    ],
    "phones": [
      "212684533"
    ]
  },
  {
    "key": "expoentebrilhante",
    "nome": "Expoente Brilhante",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "expoentebrilhante@sapo.pt",
    "telefone": "919602157",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 16; nome na fonte: Expoente Brilhante\nAtividade: Instalações elétricas\nContactos na fonte: 919602157\nEmails na fonte: expoentebrilhante@sapo.pt",
    "emails": [
      "expoentebrilhante@sapo.pt"
    ],
    "phones": [
      "919602157"
    ]
  },
  {
    "key": "keepon",
    "nome": "KeepOn",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@keepon.pt",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 18; nome na fonte: KeepOn\nAtividade: Especialista em Instalação e Manutenção de Instalações Elétricas\nLocalidade/morada: Camarate\nContactos na fonte: 800918080\nEmails na fonte: info@keepon.pt",
    "emails": [
      "info@keepon.pt"
    ],
    "phones": []
  },
  {
    "key": "attackgaslda",
    "nome": "Attackgás, Lda",
    "acao": "existente",
    "alvo": "b9dc82b3-93d1-491a-a09e-615fe1d4fd4d",
    "alvo_nome": "Attackgás, Lda",
    "email": "attackgas@gmail.com",
    "telefone": "214910054 / 932351577 / 937756370",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 21; nome na fonte: Attackgás, Lda\nAtividade: Trabalhos de gás\nLocalidade/morada: Amadora\nContactos na fonte: 214 910 054 932351577 937756370\nEmails na fonte: attackgas@gmail.com\nObservações da fonte: Sr. Nuno Maria",
    "emails": [
      "attackgas@gmail.com"
    ],
    "phones": [
      "214910054",
      "932351577",
      "937756370"
    ]
  },
  {
    "key": "mourelec",
    "nome": "Mourelec",
    "acao": "existente",
    "alvo": "a78677d8-8b29-4f61-b7bf-07857e28e337",
    "alvo_nome": "Mourelec, Unipessoal Lda",
    "email": "mourelec@gmail.com",
    "telefone": "912378726",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 22; nome na fonte: Mourelec\nAtividade: Electricidade e ITED\nContactos na fonte: 912378726\nEmails na fonte: mourelec@gmail.com\nObservações da fonte: Sr. António Magalhães",
    "emails": [
      "mourelec@gmail.com"
    ],
    "phones": [
      "912378726"
    ]
  },
  {
    "key": "injectgas",
    "nome": "Injectgás",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@injectgas.pt",
    "telefone": "217783570",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 25; nome na fonte: Injectgás\nAtividade: Instalação, montagem e assistência técnica a instalações e equipamentos a gás\nLocalidade/morada: Rua José Galhardo, 5 – Sub/cave, Loja A 1750-131 Lisboa\nContactos na fonte: 21 778 35 70\nEmails na fonte: geral@injectgas.pt\nObservações da fonte: 93 945 34 46 , assistenciatecnica@injectgas.pt",
    "emails": [
      "geral@injectgas.pt"
    ],
    "phones": [
      "217783570"
    ]
  },
  {
    "key": "francofasica",
    "nome": "Francofásica",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "francofasica@gmail.com",
    "telefone": "261937359",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 31; nome na fonte: Francofásica\nAtividade: Eletricista\nLocalidade/morada: R. Pereira Paulo 8, 2560-425 Silveira\nContactos na fonte: 261937359\nEmails na fonte: francofasica@gmail.com",
    "emails": [
      "francofasica@gmail.com"
    ],
    "phones": [
      "261937359"
    ]
  },
  {
    "key": "legrand",
    "nome": "Legrand",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "alexandre.cibrao@legrand.pt",
    "telefone": "935548842",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 32; nome na fonte: Legrand\nAtividade: Produtos e sistemas para infraestruturas elétricas e digitais dos edifícios\nLocalidade/morada: São Domingos de Rana - Estrada nacional 249-4\nContactos na fonte: 935548842\nEmails na fonte: alexandre.cibrao@legrand.pt\nObservações da fonte: www.legrand.pt",
    "emails": [
      "alexandre.cibrao@legrand.pt"
    ],
    "phones": [
      "935548842"
    ]
  },
  {
    "key": "efectoled",
    "nome": "EfectoLED",
    "acao": "existente",
    "alvo": "bbea8078-722f-413a-ba0c-c47c55ae2a8b",
    "alvo_nome": "EfectoLed",
    "email": "profissional@efectoled.com",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 33; nome na fonte: EfectoLED\nAtividade: Iluminação LED\nLocalidade/morada: Online\nEmails na fonte: profissional@efectoled.com\nObservações da fonte: www.efectoled.com",
    "emails": [
      "profissional@efectoled.com"
    ],
    "phones": []
  },
  {
    "key": "cypelux",
    "nome": "CYPELUX",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "cype@cype.com",
    "telefone": "965922550",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 35; nome na fonte: CYPELUX\nAtividade: Cálculo luminotécnico de instalações de iluminação\nContactos na fonte: 965922550\nEmails na fonte: cype@cype.com",
    "emails": [
      "cype@cype.com"
    ],
    "phones": [
      "965922550"
    ]
  },
  {
    "key": "voltagemcerta",
    "nome": "Voltagem Certa",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "voltagem.certa2023@gmail.com",
    "telefone": "931221074 / 931965183",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 36; nome na fonte: Voltagem Certa\nAtividade: Serviços de Instalações Elétricas e Telecomunicações – Parceria com Construdata21\nContactos na fonte: Rubem Gomes – 931221074 Campêlo – 931965183\nEmails na fonte: voltagem.certa2023@gmail.com\n\nFolha: INSTALAÇÕES ELÉTRICAS; linha: 8; nome na fonte: Voltagem Certa\nAtividade: Especializada em instalações elétricas e sistemas de telecomunicações\nContactos na fonte: 931221074\nEmails na fonte: voltagem.certa2023@gmail.com",
    "emails": [
      "voltagem.certa2023@gmail.com"
    ],
    "phones": [
      "931221074",
      "931965183"
    ]
  },
  {
    "key": "litigoncalveslda",
    "nome": "LitiGonçalves, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "919048378",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELETRICIDADE E GÁS; linha: 37; nome na fonte: LitiGonçalves, Lda\nAtividade: Fornecimento e montagem de caixilharia\nLocalidade/morada: Av. dos Lusíadas Ed. Fabrimar Arm. 284-A/B Matos Cheirinhos 2785-320 S. Domingos de Rana\nContactos na fonte: 919048378\nEmails na fonte: www.LITIGONCALVES.com",
    "emails": [],
    "phones": [
      "919048378"
    ]
  },
  {
    "key": "vitalsupplier",
    "nome": "VitalSupplier",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "miguel.martins@vitalsupplier.pt",
    "telefone": "929384320",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: EPI´S; linha: 6; nome na fonte: VitalSupplier\nAtividade: Fardamento personalizado, EPIs e consumíveis de higiene e segurança.\nLocalidade/morada: Tv. Monte da Barca 81, 4795-144 Vila das Aves\nContactos na fonte: 929384320\nEmails na fonte: miguel.martins@vitalsupplier.pt",
    "emails": [
      "miguel.martins@vitalsupplier.pt"
    ],
    "phones": [
      "929384320"
    ]
  },
  {
    "key": "eleve",
    "nome": "Eleve",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@eleve.pt",
    "telefone": "219342021",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELEVADORES; linha: 6; nome na fonte: Eleve\nAtividade: Elevadores a vácuo\nLocalidade/morada: Odivelas\nContactos na fonte: 21 934 2021\nEmails na fonte: geral@eleve.pt",
    "emails": [
      "geral@eleve.pt"
    ],
    "phones": [
      "219342021"
    ]
  },
  {
    "key": "schmittelevadoreslda",
    "nome": "Schmitt-Elevadores, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "289813156",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ELEVADORES; linha: 7; nome na fonte: Schmitt-Elevadores, Lda\nAtividade: Elevadores\nLocalidade/morada: Cave direito, 8000-183 Faro\nContactos na fonte: 289813156\nEmails na fonte: www.schmitt-elevadores.com",
    "emails": [],
    "phones": [
      "289813156"
    ]
  },
  {
    "key": "combisistemas",
    "nome": "COMBISISTEMAS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@combisistemas.pt",
    "telefone": "919796344 / 218216291",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTORES; linha: 6; nome na fonte: COMBISISTEMAS\nAtividade: Estores, pérgolas, toldos\nLocalidade/morada: Rua Monte Leite, 468 A 2765-496 Estoril\nContactos na fonte: 919 796 344 218 216 291\nEmails na fonte: geral@combisistemas.pt\nObservações da fonte: Trabalham para clientes na Quinta Patino e por isso contactaram-nos.",
    "emails": [
      "geral@combisistemas.pt"
    ],
    "phones": [
      "919796344",
      "218216291"
    ]
  },
  {
    "key": "sunblocktech",
    "nome": "SUNBLOCK TECH",
    "acao": "existente",
    "alvo": "dc2fec58-ff3b-40d3-94c3-9f59e5bf605e",
    "alvo_nome": "Sunblock Tech, Lda",
    "email": "comercial@sunblock.pt",
    "telefone": "915008530 / 915008533",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTORES; linha: 7; nome na fonte: SUNBLOCK TECH\nAtividade: Estores exteriores, interiores, pérgolas, toldos e soluções domóticas integradas\nLocalidade/morada: Rua do Centro Empresarial, Edf. 7, Quinta da Beloura\nContactos na fonte: 915 008 530 915 008 533\nEmails na fonte: comercial@sunblock.pt\nObservações da fonte: Nancy Luis (910607990) Empresa vizinha do nosso escritório",
    "emails": [
      "comercial@sunblock.pt"
    ],
    "phones": [
      "915008530",
      "915008533"
    ]
  },
  {
    "key": "ninoxinova",
    "nome": "NI NOXINOVA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@noxinova.com",
    "telefone": "255814271",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURAS-SOLUÇÕES METÁLICAS; linha: 7; nome na fonte: NI NOXINOVA\nAtividade: realização de trabalhos em metal: soluções em alumínio, soluções em inox, soluções em ferro\nLocalidade/morada: Centro Empresarial do Rio, Rua Verdial Horácio de Moura, n.º 170, fr. B e E 4650-331 Rande, Felgueiras (Portugal)\nContactos na fonte: 255814271\nEmails na fonte: geral@noxinova.com",
    "emails": [
      "geral@noxinova.com"
    ],
    "phones": [
      "255814271"
    ]
  },
  {
    "key": "acero",
    "nome": "Acero",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "jane.machado@acero.ae",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURAS-SOLUÇÕES METÁLICAS; linha: 9; nome na fonte: Acero\nAtividade: Edifícios modulares pré fabricados (módulos metálicos industrializados)\nLocalidade/morada: Dubai, Emirates\nContactos na fonte: 97148931000\nEmails na fonte: jane.machado@acero.ae",
    "emails": [
      "jane.machado@acero.ae"
    ],
    "phones": []
  },
  {
    "key": "curtymania",
    "nome": "CURTYMANIA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "bruno.curtymania@gmail.com",
    "telefone": "920352121",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ENTULHO; linha: 5; nome na fonte: CURTYMANIA\nAtividade: Contentores de entulho, demolição, terraplanagem e construção\nLocalidade/morada: Linda-a-Velha\nContactos na fonte: 920352121\nEmails na fonte: bruno.curtymania@gmail.com",
    "emails": [
      "bruno.curtymania@gmail.com"
    ],
    "phones": [
      "920352121"
    ]
  },
  {
    "key": "resetdemolitionsexperts",
    "nome": "RESET - Demolitions Experts",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@reset-demolicoes.pt",
    "telefone": "219372009",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESCAVAÇÕES; linha: 6; nome na fonte: RESET - Demolitions Experts\nAtividade: Demolições, demolições c/ robot, remoção amianto, desmantelamentos remoção estuturas, escavações\nLocalidade/morada: Póvoa de Stº Adrião\nContactos na fonte: 219372009\nEmails na fonte: geral@reset-demolicoes.pt\n\nFolha: REMOÇÃO AMIANTO, ESTRUTURAS; linha: 6; nome na fonte: RESET - Demolitions Experts\nAtividade: Demolições, demolições c/ robot, remoção amianto, desmantelamentos remoção estuturas, escavações\nLocalidade/morada: Póvoa de Stº Adrião\nContactos na fonte: 219372009\nEmails na fonte: geral@reset-demolicoes.pt",
    "emails": [
      "geral@reset-demolicoes.pt"
    ],
    "phones": [
      "219372009"
    ]
  },
  {
    "key": "ccasa",
    "nome": "CCA.S.A.",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "924441805",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 12; nome na fonte: CCA.S.A.\nAtividade: Movimento de terras, Cofragem e Armação de Ferro, Estrutura Metálica\nLocalidade/morada: Loures\nContactos na fonte: 924441805\nEmails na fonte: geral@jcs.com.pt; construcoesca.sa@gmail.com\nObservações da fonte: Resp. Sr.º Joaquim Castanheira Silva; Adm. Srª Dª Nazaré",
    "emails": [
      "geral@jcs.com.pt",
      "construcoesca.sa@gmail.com"
    ],
    "phones": [
      "924441805"
    ]
  },
  {
    "key": "lusomelt",
    "nome": "Lusomelt",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "lusomelt@lusomelt.pt",
    "telefone": "213616210",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 17; nome na fonte: Lusomelt\nAtividade: Fornecimento de ferro, aços e metais\nLocalidade/morada: Lisboa\nContactos na fonte: 213616210\nEmails na fonte: lusomelt@lusomelt.pt\nObservações da fonte: Não é armazenista, importação directa!",
    "emails": [
      "lusomelt@lusomelt.pt"
    ],
    "phones": [
      "213616210"
    ]
  },
  {
    "key": "chagas",
    "nome": "Chagas",
    "acao": "existente",
    "alvo": "d4e1669c-c1a3-494e-bfa7-59cd701f48fe",
    "alvo_nome": "Chagas, SA",
    "email": "massama@chagas.pt",
    "telefone": "214370998",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 18; nome na fonte: Chagas\nAtividade: Armazém de ferro\nLocalidade/morada: Massamá\nContactos na fonte: 214370998\nEmails na fonte: massama@chagas.pt",
    "emails": [
      "massama@chagas.pt"
    ],
    "phones": [
      "214370998"
    ]
  },
  {
    "key": "cimpaurblda",
    "nome": "Cimpaurb, Lda.",
    "acao": "existente",
    "alvo": "8108df80-31d8-424e-92f9-a2f4d3aa4b8b",
    "alvo_nome": "Cimpaurb. Lda",
    "email": "ascimpaurb@gmail.com",
    "telefone": "219618486 / 935041394",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 19; nome na fonte: Cimpaurb, Lda.\nAtividade: Fabrico e comercialização de betão pronto\nLocalidade/morada: Terrugem - Sintra\nContactos na fonte: 219 618 486 935 041 394\nEmails na fonte: ascimpaurb@gmail.com\nObservações da fonte: António Sá trabalha com a cimpaurb ou com a BETOPAR",
    "emails": [
      "ascimpaurb@gmail.com"
    ],
    "phones": [
      "219618486",
      "935041394"
    ]
  },
  {
    "key": "lenobetaosa",
    "nome": "LenoBetão, S.A.",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@lenobetao.pt",
    "telefone": "244749100",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 25; nome na fonte: LenoBetão, S.A.\nAtividade: Fornecimento de betão pronto\nLocalidade/morada: Montijo\nContactos na fonte: 244749100\nEmails na fonte: geral@lenobetao.pt\nObservações da fonte: Não apresenta propostas devido á distância!",
    "emails": [
      "geral@lenobetao.pt"
    ],
    "phones": [
      "244749100"
    ]
  },
  {
    "key": "betopalbetoespreparadossa",
    "nome": "Betopal-Betões Preparados, SA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "219240457",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 27; nome na fonte: Betopal-Betões Preparados, SA\nAtividade: Fornecimento de betão pronto\nLocalidade/morada: Sintra\nContactos na fonte: 219240457",
    "emails": [],
    "phones": [
      "219240457"
    ]
  },
  {
    "key": "betoparsa",
    "nome": "Betopar, S.A.",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@betopar.pt",
    "telefone": "926326038",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 28; nome na fonte: Betopar, S.A.\nAtividade: Fornecimento de betão pronto\nLocalidade/morada: Sintra\nContactos na fonte: 926326038\nEmails na fonte: geral@betopar.pt",
    "emails": [
      "geral@betopar.pt"
    ],
    "phones": [
      "926326038"
    ]
  },
  {
    "key": "antobetao",
    "nome": "Antobetão",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "luismiguel@grupoverdasca.com",
    "telefone": "969455235 / 917264364",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 30; nome na fonte: Antobetão\nAtividade: Betão Pronto\nContactos na fonte: 969455235, 917264364\nEmails na fonte: luismiguel@grupoverdasca.com\nObservações da fonte: Contacto do Eng.º Luis Guerreiro, solicitar proposta da parfe da Inacio Bento construções. Responsavel - Luís Miguel Responsavel de sintra - Nelson Vilela 917 264 364",
    "emails": [
      "luismiguel@grupoverdasca.com"
    ],
    "phones": [
      "969455235",
      "917264364"
    ]
  },
  {
    "key": "souticonfra",
    "nome": "Souticonfra",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "souticonfra@hotmail.com",
    "telefone": "962314303 / 968053005",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 31; nome na fonte: Souticonfra\nAtividade: Cofragem, armação de ferro\nLocalidade/morada: Sintra\nContactos na fonte: 962 314 303 968 053 005\nEmails na fonte: souticonfra@hotmail.com",
    "emails": [
      "souticonfra@hotmail.com"
    ],
    "phones": [
      "962314303",
      "968053005"
    ]
  },
  {
    "key": "afcc",
    "nome": "AFCC",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@afcc.pt",
    "telefone": "219340670",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 32; nome na fonte: AFCC\nAtividade: Armação de ferro\nLocalidade/morada: Ramada\nContactos na fonte: 21 934 06 70/71\nEmails na fonte: geral@afcc.pt",
    "emails": [
      "geral@afcc.pt"
    ],
    "phones": [
      "219340670"
    ]
  },
  {
    "key": "jmcofra",
    "nome": "JMCOFRA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "jmcofra.lda@gmail.com",
    "telefone": "969477789 / 934273671",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 33; nome na fonte: JMCOFRA\nAtividade: Construção civil, cofragens, aluguer de equipamentos\nLocalidade/morada: Setúbal\nContactos na fonte: 969 477 789 934 273 671\nEmails na fonte: jmcofra.lda@gmail.com",
    "emails": [
      "jmcofra.lda@gmail.com"
    ],
    "phones": [
      "969477789",
      "934273671"
    ]
  },
  {
    "key": "merconstrucoes",
    "nome": "MER Construções",
    "acao": "existente",
    "alvo": "862a9971-8855-4ae9-9aef-a34dff09fb6f",
    "alvo_nome": "M.E.R. Construções, Unipessoal Lda",
    "email": "mer.construcoes@gmail.com",
    "telefone": "219279213 / 934205685",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 35; nome na fonte: MER Construções\nLocalidade/morada: Sintra\nContactos na fonte: 21 927 92 13 934 205 685\nEmails na fonte: mer.construcoes@gmail.com",
    "emails": [
      "mer.construcoes@gmail.com"
    ],
    "phones": [
      "219279213",
      "934205685"
    ]
  },
  {
    "key": "cibloco",
    "nome": "Cibloco",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "262609150",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 36; nome na fonte: Cibloco\nAtividade: Pré-fabricados de betão\nLocalidade/morada: Bombarral\nContactos na fonte: 262609150",
    "emails": [],
    "phones": [
      "262609150"
    ]
  },
  {
    "key": "ferrosil",
    "nome": "Ferrosil",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "960323512",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 37; nome na fonte: Ferrosil\nAtividade: Cofragem e Ferro\nLocalidade/morada: Lisboa\nContactos na fonte: 960323512",
    "emails": [],
    "phones": [
      "960323512"
    ]
  },
  {
    "key": "probetao",
    "nome": "Probetão",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "probetao.pt@gmail.com",
    "telefone": "913835640",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 40; nome na fonte: Probetão\nAtividade: Pré-fabricados de Betão\nLocalidade/morada: Quinta do Conde\nContactos na fonte: 913835640\nEmails na fonte: probetao.pt@gmail.com",
    "emails": [
      "probetao.pt@gmail.com"
    ],
    "phones": [
      "913835640"
    ]
  },
  {
    "key": "stap",
    "nome": "Stap",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@stap.pt",
    "telefone": "213712580",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 41; nome na fonte: Stap\nAtividade: Reparação, Consolidação e Modificação de Estruturas\nLocalidade/morada: Algés\nContactos na fonte: 213712580\nEmails na fonte: info@stap.pt",
    "emails": [
      "info@stap.pt"
    ],
    "phones": [
      "213712580"
    ]
  },
  {
    "key": "frasesepaginas",
    "nome": "Frases e Páginas",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "930429069",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 45; nome na fonte: Frases e Páginas\nAtividade: Ferro e Cofragem\nLocalidade/morada: Almargem do Bispo\nContactos na fonte: 930429069 - Arquiteto Filipe Portugal\nObservações da fonte: Armindo Sabino - 926384689 Escritório - 969083460",
    "emails": [],
    "phones": [
      "930429069"
    ]
  },
  {
    "key": "conversajuizadalda",
    "nome": "Conversajuizada, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "965798921",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 47; nome na fonte: Conversajuizada, Lda\nAtividade: Cofragens e Armação de Ferro\nLocalidade/morada: Pero Pinheiro\nContactos na fonte: 965798921\nObservações da fonte: Alvará 92304 - PAR",
    "emails": [],
    "phones": [
      "965798921"
    ]
  },
  {
    "key": "airesfernandesdealmeida",
    "nome": "Aires Fernandes de Almeida",
    "acao": "existente",
    "alvo": "cd4feb24-9af6-4b41-9403-104ab5335d13",
    "alvo_nome": "Aires Fernandes de Almeida, Lda",
    "email": null,
    "telefone": "214263729 / 967383655",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 48; nome na fonte: Aires Fernandes de Almeida\nAtividade: Armazéns de ferro, inox, coberturas, vedações\nLocalidade/morada: Cacém\nContactos na fonte: 214263729\nEmails na fonte: geral@airesalmeida.com\nObservações da fonte: Filipe Rebelo\n\nFolha: SERRALHARIAS; linha: 15; nome na fonte: Aires Fernandes de Almeida\nAtividade: Armezéns de ferro, inox, coberturas, vedações, corte e quinagem\nLocalidade/morada: Cacém\nContactos na fonte: 967 383 655\nEmails na fonte: corte.quinagem@airesalmeida.com\nObservações da fonte: Sr. Silva",
    "emails": [
      "geral@airesalmeida.com",
      "corte.quinagem@airesalmeida.com"
    ],
    "phones": [
      "214263729",
      "967383655"
    ]
  },
  {
    "key": "doka",
    "nome": "DOKA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "portugal@doka.com",
    "telefone": "219112660",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 52; nome na fonte: DOKA\nAtividade: Cofragem\nContactos na fonte: 219112660\nEmails na fonte: portugal@doka.com",
    "emails": [
      "portugal@doka.com"
    ],
    "phones": [
      "219112660"
    ]
  },
  {
    "key": "vcln",
    "nome": "VCLN",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@grupovcln.com",
    "telefone": "211302610",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 53; nome na fonte: VCLN\nAtividade: Serviços em estruturas de betão armado (cofragem e ferro)\nLocalidade/morada: Rua Fernanda Seno nº 6, 7005-485 Évora\nContactos na fonte: 211302610\nEmails na fonte: geral@grupovcln.com",
    "emails": [
      "geral@grupovcln.com"
    ],
    "phones": [
      "211302610"
    ]
  },
  {
    "key": "dallesteel",
    "nome": "Dalle Steel",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@dallesteel.com",
    "telefone": "965693390",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 55; nome na fonte: Dalle Steel\nAtividade: Coletores em aço inoxidável\nLocalidade/morada: Vagos, Portugal\nContactos na fonte: 965693390\nEmails na fonte: geral@dallesteel.com",
    "emails": [
      "geral@dallesteel.com"
    ],
    "phones": [
      "965693390"
    ]
  },
  {
    "key": "fastwise",
    "nome": "Fast wise",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "fastwiselda@gmail.com",
    "telefone": "962093832",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURA - COFRAGEM, ARMADURAS; linha: 56; nome na fonte: Fast wise\nAtividade: Trabalhos diversos e betão modular\nLocalidade/morada: Sintra\nContactos na fonte: 962093832\nEmails na fonte: fastwiselda@gmail.com",
    "emails": [
      "fastwiselda@gmail.com"
    ],
    "phones": [
      "962093832"
    ]
  },
  {
    "key": "habioliveira",
    "nome": "Habioliveira",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@habioliveira.com",
    "telefone": "238692265",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURAS DE AÇO LEVE; linha: 5; nome na fonte: Habioliveira\nAtividade: Estruturas de aço leve\nLocalidade/morada: Oliveira do Hospital\nContactos na fonte: 238 692 265\nEmails na fonte: geral@habioliveira.com",
    "emails": [
      "geral@habioliveira.com"
    ],
    "phones": [
      "238692265"
    ]
  },
  {
    "key": "construseco",
    "nome": "Construseco",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@construseco.pt",
    "telefone": "926703031",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTRUTURAS DE AÇO LEVE; linha: 6; nome na fonte: Construseco\nAtividade: Construção em aço leve (LSF)\nLocalidade/morada: Agualva-Cacém\nContactos na fonte: 926703031\nEmails na fonte: geral@construseco.pt",
    "emails": [
      "geral@construseco.pt"
    ],
    "phones": [
      "926703031"
    ]
  },
  {
    "key": "vicentectolda",
    "nome": "Vicentecto, Lda.",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "vicentecto@hotmail.com",
    "telefone": "919796582",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 7; nome na fonte: Vicentecto, Lda.\nAtividade: Tetos Falsos\nLocalidade/morada: Lourinhã\nContactos na fonte: 919 796 582\nEmails na fonte: vicentecto@hotmail.com",
    "emails": [
      "vicentecto@hotmail.com"
    ],
    "phones": [
      "919796582"
    ]
  },
  {
    "key": "divimoderna",
    "nome": "DIVIMODERNA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "engenharia.divimoderna@gmail.com",
    "telefone": "938830910 / 214038947",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 8; nome na fonte: DIVIMODERNA\nAtividade: Tetos Falsos, divisórias, pinturas\nLocalidade/morada: Corroios\nContactos na fonte: 938 830 910 214038947\nEmails na fonte: engenharia.divimoderna@gmail.com",
    "emails": [
      "engenharia.divimoderna@gmail.com"
    ],
    "phones": [
      "938830910",
      "214038947"
    ]
  },
  {
    "key": "multitectos",
    "nome": "Multitectos",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "214312829",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 10; nome na fonte: Multitectos\nAtividade: Tetos Falsos\nLocalidade/morada: Lisboa\nContactos na fonte: 214312829",
    "emails": [],
    "phones": [
      "214312829"
    ]
  },
  {
    "key": "munditamanho",
    "nome": "Munditamanho",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@munditamanho.pt",
    "telefone": "962212161 / 912660433",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 12; nome na fonte: Munditamanho\nAtividade: Tetos Falsos, isolamentos acústicos\nLocalidade/morada: Corroios\nContactos na fonte: 962212161\nEmails na fonte: geral@munditamanho.pt\n\nFolha: TETOS FALSOS E DIVISÓRIAS; linha: 6; nome na fonte: Munditamanho\nAtividade: Tetos falsos e divisórias\nLocalidade/morada: Aroeira\nContactos na fonte: 962 212 161 912 660 433\nEmails na fonte: geral@munditamanho.pt www.munditamanho.pt",
    "emails": [
      "geral@munditamanho.pt"
    ],
    "phones": [
      "962212161",
      "912660433"
    ]
  },
  {
    "key": "improvisobra",
    "nome": "Improvisobra",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "improvisobrarevestimentos@hotmail.com",
    "telefone": "937869497",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 14; nome na fonte: Improvisobra\nAtividade: Tetos Falsos, Divisórias, Revestimentos Decorativos\nLocalidade/morada: Torres Vedras\nContactos na fonte: 937869497\nEmails na fonte: IMPROVISOBRAREVESTIMENTOS@HOTMAIL.COM",
    "emails": [
      "improvisobrarevestimentos@hotmail.com"
    ],
    "phones": [
      "937869497"
    ]
  },
  {
    "key": "menoitectos",
    "nome": "Menoitectos",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "menoitectos@sapo.pt",
    "telefone": "210827928",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 16; nome na fonte: Menoitectos\nAtividade: Tectos Falsos e divisórias\nLocalidade/morada: Moita\nContactos na fonte: 210827928\nEmails na fonte: menoitectos@sapo.pt",
    "emails": [
      "menoitectos@sapo.pt"
    ],
    "phones": [
      "210827928"
    ]
  },
  {
    "key": "lxpro",
    "nome": "LxPro",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "lxprosprl@gmail.com",
    "telefone": "912188890 / 939836980",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 17; nome na fonte: LxPro\nAtividade: Pladur\nLocalidade/morada: Lisboa\nContactos na fonte: 912 188 890 939 836 980\nEmails na fonte: lxprosprl@gmail.com\nObservações da fonte: Sr. Miguel Ramos e D. Caroline Stabile",
    "emails": [
      "lxprosprl@gmail.com"
    ],
    "phones": [
      "912188890",
      "939836980"
    ]
  },
  {
    "key": "placoperfil",
    "nome": "Placoperfil",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@placoperfil.pt",
    "telefone": "211974699",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 19; nome na fonte: Placoperfil\nAtividade: Estuques, tetos falsos, divisórias\nLocalidade/morada: Camarate\nContactos na fonte: 211974699\nEmails na fonte: geral@placoperfil.pt\nObservações da fonte: www.placoperfil.pt",
    "emails": [
      "geral@placoperfil.pt"
    ],
    "phones": [
      "211974699"
    ]
  },
  {
    "key": "cenarioesmeradolda",
    "nome": "Cenário Esmerado, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "cenarioesmeradoltd@gmail.com",
    "telefone": "915170423 / 963289943",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 20; nome na fonte: Cenário Esmerado, Lda\nAtividade: Estuque e Reboco Projetado (construção civil e remodelações)\nLocalidade/morada: Rio de Mouro\nContactos na fonte: 915 170 423 963 289 943\nEmails na fonte: cenarioesmeradoltd@gmail.com",
    "emails": [
      "cenarioesmeradoltd@gmail.com"
    ],
    "phones": [
      "915170423",
      "963289943"
    ]
  },
  {
    "key": "destaquelisonjeirounipessoallda",
    "nome": "Destaque Lisonjeiro Unipessoal Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "destaquelinsonjeiro@gmail.com",
    "telefone": "919991169",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ESTUQUE E PLADUR; linha: 21; nome na fonte: Destaque Lisonjeiro Unipessoal Lda\nAtividade: Estuque, Reboco projectado, gesso cartonado e acabamentos interiores.\nLocalidade/morada: Lisboa\nContactos na fonte: 919991169\nEmails na fonte: destaquelinsonjeiro@gmail.com",
    "emails": [
      "destaquelinsonjeiro@gmail.com"
    ],
    "phones": [
      "919991169"
    ]
  },
  {
    "key": "earthform",
    "nome": "Earth Form",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "rhumanos@earthform.pt",
    "telefone": "917702807",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FORMAÇÕES; linha: 6; nome na fonte: Earth Form\nAtividade: Formação profissonal\nLocalidade/morada: Avenida Mário Mendes Delgado, nº 50 Porto Alto - Samora Correia\nContactos na fonte: 917702807\nEmails na fonte: rhumanos@earthform.pt",
    "emails": [
      "rhumanos@earthform.pt"
    ],
    "phones": [
      "917702807"
    ]
  },
  {
    "key": "formaschool",
    "nome": "Formaschool",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "912804444",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FORMAÇÕES; linha: 7; nome na fonte: Formaschool\nAtividade: Academia de formação especializada\nLocalidade/morada: Rua dos bombeiros 27A 4740-291 Esposende\nContactos na fonte: 912804444\nEmails na fonte: www.formaschool.pt",
    "emails": [],
    "phones": [
      "912804444"
    ]
  },
  {
    "key": "mediatica",
    "nome": "Mediática",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "224910947",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FORMAÇÕES; linha: 8; nome na fonte: Mediática\nAtividade: Formações Diversas\nLocalidade/morada: Rua 14 de Outubro, nº502/506 4430-047 Vila Nova de Gaia\nContactos na fonte: 224910947\nEmails na fonte: www.mediatica.pt",
    "emails": [],
    "phones": [
      "224910947"
    ]
  },
  {
    "key": "tevel",
    "nome": "TEVEL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "217810300",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FERRAGENS ; linha: 6; nome na fonte: TEVEL\nAtividade: Ferragens decorativas para todos os fins\nLocalidade/morada: Lisboa\nContactos na fonte: 21 781 0300",
    "emails": [],
    "phones": [
      "217810300"
    ]
  },
  {
    "key": "bernardinoferragem",
    "nome": "BERNARDINO Ferragem",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "bernardinoferragem@gmail.com",
    "telefone": "967676715",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FERRAGENS ; linha: 7; nome na fonte: BERNARDINO Ferragem\nAtividade: Armador de ferro para construção\nContactos na fonte: 967676715\nEmails na fonte: bernardinoferragem@gmail.com",
    "emails": [
      "bernardinoferragem@gmail.com"
    ],
    "phones": [
      "967676715"
    ]
  },
  {
    "key": "construferro",
    "nome": "CONSTRUFERRO",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "construferroericeira2019@outlook.com",
    "telefone": "920070594 / 920070185",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FERRAGENS ; linha: 8; nome na fonte: CONSTRUFERRO\nAtividade: Armador de ferro\nContactos na fonte: 920070594 920070185\nEmails na fonte: construferroericeira2019@outlook.com",
    "emails": [
      "construferroericeira2019@outlook.com"
    ],
    "phones": [
      "920070594",
      "920070185"
    ]
  },
  {
    "key": "ferlito",
    "nome": "Ferlito",
    "acao": "existente",
    "alvo": "982ee2a0-ad5b-463f-8c0f-1b28dff4107a",
    "alvo_nome": "Ferlito, SA",
    "email": "ferlito@oscacer.pt",
    "telefone": "256570900",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FERRAGENS ; linha: 9; nome na fonte: Ferlito\nAtividade: Tubos, Trefilaria, Varão nervurado, entre outros\nLocalidade/morada: Ovar\nContactos na fonte: 256570900\nEmails na fonte: ferlito@oscacer.pt",
    "emails": [
      "ferlito@oscacer.pt"
    ],
    "phones": [
      "256570900"
    ]
  },
  {
    "key": "thomazdossantos",
    "nome": "Thomaz dos Santos",
    "acao": "existente",
    "alvo": "473fb894-e55c-42fc-87d6-ce5709958e36",
    "alvo_nome": "Thomaz Dos Santos",
    "email": null,
    "telefone": "219535290 / 969025615",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FERRAGENS ; linha: 10; nome na fonte: Thomaz dos Santos\nAtividade: Produtos Siderúrgicos\nLocalidade/morada: Caldas da Rainha e Santa Iria de Azóia\nContactos na fonte: 219535290\nEmails na fonte: geral@thomazsantos.pt\n\nFolha: PRODUTOS SIDERÚRGICOS; linha: 6; nome na fonte: Thomaz dos Santos\nAtividade: Produtos siderúrgicos\nLocalidade/morada: Caldas da Rainha e Santa Iria de Azóia\nContactos na fonte: 969025615\nEmails na fonte: miguel.gomes@thomazdossantos.pt",
    "emails": [
      "geral@thomazsantos.pt",
      "miguel.gomes@thomazdossantos.pt"
    ],
    "phones": [
      "219535290",
      "969025615"
    ]
  },
  {
    "key": "brisintemporal",
    "nome": "BRISINTEMPORAL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "secretaria@brisintemporal.com",
    "telefone": "930671264",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FORNECEDORES; linha: 6; nome na fonte: BRISINTEMPORAL\nAtividade: fornecimento de trabalhadores\nLocalidade/morada: Avenida Elias Garcia Nº 93 1050-097 Lisboa\nContactos na fonte: 930671264\nEmails na fonte: secretaria@brisintemporal.com\nObservações da fonte: TERESA BONNET SECRETÁRIA ADMINISTRATIVA",
    "emails": [
      "secretaria@brisintemporal.com"
    ],
    "phones": [
      "930671264"
    ]
  },
  {
    "key": "gamavancada",
    "nome": "GamAvançada",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "gamavancada@gamavancada.pt",
    "telefone": "961022668",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: FORNECEDORES; linha: 7; nome na fonte: GamAvançada\nAtividade: Fornecedores de Materiais (área da Hidráulica,(Tubos, acessórios e componentes), componentes em inox, tubos de travão, direção e ar condicionado auto, também comercializamos óleos hidráulicos, térmicos e de motor, sprays, adblue, massas e ferramentas, absorventes, tubos de lavagem alta pressão, pistolas de lavagem, luvas entre outros)\nLocalidade/morada: Av. Pedro Álvares Cabral, Armazém E2 Centro Empresarial Sintra Estoril V 2710-144 Linhó\nContactos na fonte: 961022668\nEmails na fonte: gamavancada@gamavancada.pt\nObservações da fonte: 212841682/3 ; pcardoso@gamavancada.pt; Helena Valentim - hvalentim@gamavancada.pt; 936209030\n\nFolha: REPARAÇÕES; linha: 6; nome na fonte: GamAvançada\nAtividade: Reparações (cilindros, distribuidores, bombas hidráulicas, válvulas hidráulicas)\nLocalidade/morada: Av. Pedro Álvares Cabral, Armazém E2 Centro Empresarial Sintra Estoril V 2710-144 Linhó\nContactos na fonte: 961022668\nEmails na fonte: gamavancada@gamavancada.pt\nObservações da fonte: 212841682/3 ; pcardoso@gamavancada.pt; Helena Valentim - hvalentim@gamavancada.pt; 936209030",
    "emails": [
      "gamavancada@gamavancada.pt"
    ],
    "phones": [
      "961022668"
    ]
  },
  {
    "key": "entulhosnahoraunipessoallda",
    "nome": "Entulhos na hora,unipessoal,LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "964244767",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: GESTÃO DE RESÍDUOS; linha: 5; nome na fonte: Entulhos na hora,unipessoal,LDA\nAtividade: Recolha de Entulhos\nLocalidade/morada: Costa da Caparica\nContactos na fonte: 964244767",
    "emails": [],
    "phones": [
      "964244767"
    ]
  },
  {
    "key": "perdidosnocaos",
    "nome": "Perdidos no Caos",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "perdidosnocaos@hotmail.com",
    "telefone": "965360506 / 918853757",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: GESTÃO DE RESÍDUOS; linha: 6; nome na fonte: Perdidos no Caos\nAtividade: Contentores de entulhos\nLocalidade/morada: Odivelas\nContactos na fonte: 965 360 506 918 853 757\nEmails na fonte: perdidosnocaos@hotmail.com",
    "emails": [
      "perdidosnocaos@hotmail.com"
    ],
    "phones": [
      "965360506",
      "918853757"
    ]
  },
  {
    "key": "renasxer",
    "nome": "Renasxer",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@renasxer.pt",
    "telefone": "964299105 / 969028743",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: GESTÃO DE RESÍDUOS; linha: 7; nome na fonte: Renasxer\nAtividade: Gestao de residuos\nLocalidade/morada: Loures\nContactos na fonte: 964299105 | 969028743\nEmails na fonte: geral@renasxer.pt",
    "emails": [
      "geral@renasxer.pt"
    ],
    "phones": [
      "964299105",
      "969028743"
    ]
  },
  {
    "key": "grumontelda",
    "nome": "Grumonte, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@grumonte.pt",
    "telefone": "255891721",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: GRUAS; linha: 7; nome na fonte: Grumonte, Lda\nAtividade: Serviços especializados...montagens, demontagens e assistências a todo o tipo de gruas\nLocalidade/morada: Rua de S. Pedro da Lomba n.º 234, Amarante, Portugal\nContactos na fonte: 255891721\nEmails na fonte: geral@grumonte.pt",
    "emails": [
      "geral@grumonte.pt"
    ],
    "phones": [
      "255891721"
    ]
  },
  {
    "key": "vanquish",
    "nome": "VANQUISH",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "afonso.perdigao@vanquishproperties.co",
    "telefone": "931901693",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INVESTIMENTOS; linha: 6; nome na fonte: VANQUISH\nAtividade: Consultora na assessoria e estruturação de investimentos imobiliários prime\nLocalidade/morada: Cascais, Portugal\nContactos na fonte: 931901693\nEmails na fonte: afonso.perdigao@vanquishproperties.co",
    "emails": [
      "afonso.perdigao@vanquishproperties.co"
    ],
    "phones": [
      "931901693"
    ]
  },
  {
    "key": "editela",
    "nome": "Editela",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "editela@live.com",
    "telefone": "210888253",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 6; nome na fonte: Editela\nAtividade: Isolamentos\nLocalidade/morada: Loures\nContactos na fonte: 210888253\nEmails na fonte: editela@live.com\n\nFolha: SUBEMPREITEIRO GERAL; linha: 17; nome na fonte: Editela\nAtividade: C.Civil, Isolamentos, Pedreiro, Ladrilhador\nLocalidade/morada: Lisboa\nContactos na fonte: 912 870 5036 210 888 253\nEmails na fonte: editela@live.com",
    "emails": [
      "editela@live.com"
    ],
    "phones": [
      "210888253"
    ]
  },
  {
    "key": "globalpur",
    "nome": "Globalpur",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@globalpur.pt",
    "telefone": "211379921 / 910197545",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 9; nome na fonte: Globalpur\nAtividade: Impermeabilizações\nLocalidade/morada: Sintra\nContactos na fonte: 211 379 921 910197545\nEmails na fonte: geral@globalpur.pt",
    "emails": [
      "geral@globalpur.pt"
    ],
    "phones": [
      "211379921",
      "910197545"
    ]
  },
  {
    "key": "lusomembranalda",
    "nome": "Lusomembrana, Lda",
    "acao": "existente",
    "alvo": "adfcba2a-85dd-49e3-89b2-28cc7a9b8c05",
    "alvo_nome": "Lusomembrana, Unipessoal, Lda",
    "email": "geral@lusomembrana.pt",
    "telefone": "218531468",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 10; nome na fonte: Lusomembrana, Lda\nAtividade: Impermeabilizações\nLocalidade/morada: Lisboa\nContactos na fonte: 218 531 468\nEmails na fonte: geral@lusomembrana.pt",
    "emails": [
      "geral@lusomembrana.pt"
    ],
    "phones": [
      "218531468"
    ]
  },
  {
    "key": "mundisol",
    "nome": "Mundisol",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "965218302",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 11; nome na fonte: Mundisol\nAtividade: Coberturas e Impermeabilizações\nContactos na fonte: 965218302\nObservações da fonte: Carlos Cerejo",
    "emails": [],
    "phones": [
      "965218302"
    ]
  },
  {
    "key": "isologlobal",
    "nome": "ISOLOGLOBAL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@isologlobal.pt",
    "telefone": "967221954",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 12; nome na fonte: ISOLOGLOBAL\nAtividade: Isolamentos\nLocalidade/morada: Lisboa\nContactos na fonte: 967221954\nEmails na fonte: geral@isologlobal.pt\nObservações da fonte: VM contactou no dia 12/09/2023, não trabalham para empresas de construção. Fazem manitenção de condominios",
    "emails": [
      "geral@isologlobal.pt"
    ],
    "phones": [
      "967221954"
    ]
  },
  {
    "key": "tiib",
    "nome": "Tiib",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@tiib.pt",
    "telefone": "253114810",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 13; nome na fonte: Tiib\nAtividade: Impermeabilizações, Coberturas, Fachadas\nLocalidade/morada: Braga\nContactos na fonte: 253114810\nEmails na fonte: geral@tiib.pt",
    "emails": [
      "geral@tiib.pt"
    ],
    "phones": [
      "253114810"
    ]
  },
  {
    "key": "isolpedro",
    "nome": "Isolpedro",
    "acao": "existente",
    "alvo": "4fe5b6b0-d837-4857-8115-443e1cb3d55b",
    "alvo_nome": "Isolpedro Unipessoal, Lda",
    "email": null,
    "telefone": "914652784",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 14; nome na fonte: Isolpedro\nAtividade: Impermeabilizações\nContactos na fonte: 914652784",
    "emails": [],
    "phones": [
      "914652784"
    ]
  },
  {
    "key": "waterproof",
    "nome": "WaterProof",
    "acao": "existente",
    "alvo": "f5eb3656-2c27-4e7b-9f81-e79665cfbdc4",
    "alvo_nome": "Waterproof, Lda",
    "email": "geral@waterproof.pt",
    "telefone": "215866344",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 16; nome na fonte: WaterProof\nAtividade: Impermeabilizações\nContactos na fonte: 215866344\nEmails na fonte: geral@waterproof.pt",
    "emails": [
      "geral@waterproof.pt"
    ],
    "phones": [
      "215866344"
    ]
  },
  {
    "key": "krystaline",
    "nome": "Krystaline",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "luis@krystaline.pt",
    "telefone": "911805231",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 17; nome na fonte: Krystaline\nAtividade: Impermeabilizações\nLocalidade/morada: Alcabideche\nContactos na fonte: 911805231\nEmails na fonte: luis@krystaline.pt",
    "emails": [
      "luis@krystaline.pt"
    ],
    "phones": [
      "911805231"
    ]
  },
  {
    "key": "nacionalrev",
    "nome": "Nacionalrev",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "tiago.cruz@nacionalrev.pt",
    "telefone": "249728448",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: IMPERMEABILIZAÇÕES; linha: 18; nome na fonte: Nacionalrev\nAtividade: Impermeabilização\nLocalidade/morada: Zona Industrial do Entroncamento, E.N. 3 - Lote 20, 2330-210 Entroncamento\nContactos na fonte: 249 728 448\nEmails na fonte: tiago.cruz@nacionalrev.pt",
    "emails": [
      "tiago.cruz@nacionalrev.pt"
    ],
    "phones": [
      "249728448"
    ]
  },
  {
    "key": "spybuilding",
    "nome": "SPYBUILDING",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@spybuilding.com",
    "telefone": "213241560",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INSPEÇÕES; linha: 6; nome na fonte: SPYBUILDING\nAtividade: Inspeção de edifícios\nContactos na fonte: 213241560\nEmails na fonte: geral@spybuilding.com",
    "emails": [
      "geral@spybuilding.com"
    ],
    "phones": [
      "213241560"
    ]
  },
  {
    "key": "ecorbis",
    "nome": "ECORBIS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "antoniopena@ecorbis.pt",
    "telefone": "934515361",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INSPEÇÕES; linha: 7; nome na fonte: ECORBIS\nAtividade: Inspeção de edifícios\nContactos na fonte: 934515361\nEmails na fonte: antoniopena@ecorbis.pt",
    "emails": [
      "antoniopena@ecorbis.pt"
    ],
    "phones": [
      "934515361"
    ]
  },
  {
    "key": "i9ar",
    "nome": "I9ar",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "i9ar.geral@gmail.com",
    "telefone": "968693402",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INSPEÇÕES; linha: 9; nome na fonte: I9ar\nAtividade: Inspeção de edifícios\nContactos na fonte: 968693402\nEmails na fonte: i9ar.geral@gmail.com",
    "emails": [
      "i9ar.geral@gmail.com"
    ],
    "phones": [
      "968693402"
    ]
  },
  {
    "key": "dfgest",
    "nome": "DFGest",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@dfgest.com",
    "telefone": "211934140",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INSPEÇÕES; linha: 10; nome na fonte: DFGest\nAtividade: Inspeção de edifícios\nContactos na fonte: 211934140\nEmails na fonte: geral@dfgest.com",
    "emails": [
      "geral@dfgest.com"
    ],
    "phones": [
      "211934140"
    ]
  },
  {
    "key": "grupojota",
    "nome": "Grupojota",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "lisboa@grupojota.com",
    "telefone": "219241425",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INSTALAÇÕES ELÉTRICAS; linha: 6; nome na fonte: Grupojota\nAtividade: Instalações eléctricas, domotica, som, imagem, home cinema, redes de wi fi, foto voltaicos, segurança e vigilância incluindo o light design\nLocalidade/morada: SHOWROOM CASCAIS Av. Eng. Adelino Amaro da Costa n.º 1586 2750 343 Cascais\nContactos na fonte: 219241425\nEmails na fonte: lisboa@grupojota.com\nObservações da fonte: Jorge Teixeira CEO - 963 005 166 - jorge@grupojota.com",
    "emails": [
      "lisboa@grupojota.com"
    ],
    "phones": [
      "219241425"
    ]
  },
  {
    "key": "enginstalunipessoallda",
    "nome": "ENGINSTAL - Unipessoal, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@enginstal.pt",
    "telefone": "214926339",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: INSTALAÇÕES ELÉTRICAS; linha: 7; nome na fonte: ENGINSTAL - Unipessoal, Lda\nAtividade: Instalação e manutenção de instalações elétricas e mecânicas, sistemas de gestão, automatismo e instrumentação\nLocalidade/morada: Rua Branquinho da Fonseca, 2 Amadora\nContactos na fonte: 214926339\nEmails na fonte: geral@enginstal.pt\nObservações da fonte: www.enginstal.pt",
    "emails": [
      "geral@enginstal.pt"
    ],
    "phones": [
      "214926339"
    ]
  },
  {
    "key": "isolar",
    "nome": "Isolar",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "263518090",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: ISOLAMENTOS; linha: 6; nome na fonte: Isolar\nAtividade: Isolamentos\nLocalidade/morada: Benavente\nContactos na fonte: 263518090",
    "emails": [],
    "phones": [
      "263518090"
    ]
  },
  {
    "key": "gardenprops",
    "nome": "Garden Props",
    "acao": "existente",
    "alvo": "7315052f-f573-4956-8672-641ef747a962",
    "alvo_nome": "Garden Props, Lda",
    "email": "geral@garden-props.pt",
    "telefone": "963259574",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: JARDINAGEM; linha: 8; nome na fonte: Garden Props\nAtividade: Madeiras para jardim\nLocalidade/morada: Mem Martins\nContactos na fonte: 963259574\nEmails na fonte: geral@garden-props.pt\nObservações da fonte: Rodrigo Martins",
    "emails": [
      "geral@garden-props.pt"
    ],
    "phones": [
      "963259574"
    ]
  },
  {
    "key": "maneis",
    "nome": "Manei's",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "maneis.viveiros@sapo.pt",
    "telefone": "963308781",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: JARDINAGEM; linha: 9; nome na fonte: Manei's\nAtividade: Construção de Jardins\nLocalidade/morada: Ferreira do Zézere\nContactos na fonte: 963308781\nEmails na fonte: maneis.viveiros@sapo.pt",
    "emails": [
      "maneis.viveiros@sapo.pt"
    ],
    "phones": [
      "963308781"
    ]
  },
  {
    "key": "diaplant",
    "nome": "DIAPLANT",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "912234087 / 255449356",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: JARDINAGEM; linha: 13; nome na fonte: DIAPLANT\nAtividade: Viveiro de plantas, arquitetura paisagistica, espaços verdes\nLocalidade/morada: Rua de Mem Gundar, 550 4600-648 Gondar, Amarante\nContactos na fonte: 912 234 087 255 449 356\nEmails na fonte: geral@diaplant.pt claudioazevedo@diaplant.pt\nObservações da fonte: Cláudio Azevedo",
    "emails": [
      "geral@diaplant.pt",
      "claudioazevedo@diaplant.pt"
    ],
    "phones": [
      "912234087",
      "255449356"
    ]
  },
  {
    "key": "ecojardins",
    "nome": "ECOJARDINS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "969079385 / 965008659 / 968094402",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: JARDINAGEM; linha: 14; nome na fonte: ECOJARDINS\nAtividade: Construção e Manutenção de Jardins\nLocalidade/morada: Cascais\nContactos na fonte: 969 079 385 965 008 659 968 094 402\nEmails na fonte: ecojardins_3hotmail.com\nObservações da fonte: João Duarte, Luís Duarte, José Duarte",
    "emails": [],
    "phones": [
      "969079385",
      "965008659",
      "968094402"
    ]
  },
  {
    "key": "liderglorioso",
    "nome": "LIDERGLORIOSO",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "liderglorioso2019@gmail.com",
    "telefone": "968469195",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: LADRILHADOR; linha: 6; nome na fonte: LIDERGLORIOSO\nAtividade: Ladrilhos\nContactos na fonte: 968469195\nEmails na fonte: liderglorioso2019@gmail.com",
    "emails": [
      "liderglorioso2019@gmail.com"
    ],
    "phones": [
      "968469195"
    ]
  },
  {
    "key": "fariaesumbi",
    "nome": "Faria ESumbi",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "fariaesumbi@gmail.com",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: LIMPEZAS; linha: 9; nome na fonte: Faria ESumbi\nAtividade: Empresa de limpezas comerciais e industriais\nEmails na fonte: fariaesumbi@gmail.com",
    "emails": [
      "fariaesumbi@gmail.com"
    ],
    "phones": []
  },
  {
    "key": "giganticjumpunipessoallda",
    "nome": "GIGANTIC JUMP UNIPESSOAL LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "920610957",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: LIMPEZAS; linha: 11; nome na fonte: GIGANTIC JUMP UNIPESSOAL LDA\nAtividade: Suporte profissional de limpeza e manutenção\nLocalidade/morada: Centro Comercial Mouraria, 427, Lift 1nd Floor, Praça Martim Moniz, Lisbon, Portugal\nContactos na fonte: 920610957\nEmails na fonte: www.giganticjulda.com",
    "emails": [],
    "phones": [
      "920610957"
    ]
  },
  {
    "key": "tecknodeck",
    "nome": "Tecknodeck",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "ricardoalmeida@tecnodeck.pt",
    "telefone": "910230958",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MADEIRAS E DERIVADOS; linha: 8; nome na fonte: Tecknodeck\nAtividade: Madeira e resina termoplástica (HDPE) oferece a estética da madeira sem a necessidade de tratamentos convencionais\nLocalidade/morada: Alto da Bela Vista, Sulimpark Armazém 86 A/B 2735-521 Cacém - Portugal\nContactos na fonte: +351 910 230 958\nEmails na fonte: Ricardoalmeida@tecnodeck.pt",
    "emails": [
      "ricardoalmeida@tecnodeck.pt"
    ],
    "phones": [
      "910230958"
    ]
  },
  {
    "key": "rivaofficesshowroom",
    "nome": "Riva - Offices Showroom",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "mkt@ricardoevaz.com",
    "telefone": "253276132",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE PAPELARIA, AUDIOVI; linha: 6; nome na fonte: Riva - Offices Showroom\nAtividade: Empresa dedicada a material de papelaria, audiovisuais, mobiliário escritório e consumíveis informática.\nLocalidade/morada: Rua Pomar de Marvila Lote 13 Parque industrial Sequeira, 4705-629 Braga\nContactos na fonte: 253276132\nEmails na fonte: mkt@ricardoevaz.com\nObservações da fonte: info@riva-office.pt (orçamentos) orcamentos@riva-office.pt",
    "emails": [
      "mkt@ricardoevaz.com"
    ],
    "phones": [
      "253276132"
    ]
  },
  {
    "key": "sociodata",
    "nome": "Sociodata",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "214957313",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE PAPELARIA, AUDIOVI; linha: 7; nome na fonte: Sociodata\nAtividade: Material de escritório e artigos de papelaria.\nLocalidade/morada: Av. 25 de Abril 105 Pavilhão 10, 2705-902 Terrugem\nContactos na fonte: 214957313\nEmails na fonte: www.sociodata.com\nObservações da fonte: Rafael Firmino - Sócio Gerente Tlm: 919 410 878",
    "emails": [],
    "phones": [
      "214957313"
    ]
  },
  {
    "key": "papelarte",
    "nome": "Papelarte",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "932838510",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE PAPELARIA, AUDIOVI; linha: 8; nome na fonte: Papelarte\nAtividade: Material de escritório e consumíveis informáticos\nContactos na fonte: 932838510\nObservações da fonte: Antonio Moreira",
    "emails": [],
    "phones": [
      "932838510"
    ]
  },
  {
    "key": "maammaterialsatmitera",
    "nome": "MA`AM - Materials at Mitera",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@maam-materials.com",
    "telefone": "213600000",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE REVESTIMENTO; linha: 6; nome na fonte: MA`AM - Materials at Mitera\nAtividade: Materiais de resvestimento (materiais para diversas aplicações)\nLocalidade/morada: Largo Marquês da Angeja 11/12 1300 - 389 Lisboa\nContactos na fonte: 213600000\nEmails na fonte: info@maam-materials.com\nObservações da fonte: 213600009 https://www.maamaterials.com/pt/home/ https://verti-maam.com/pt/maam",
    "emails": [
      "info@maam-materials.com"
    ],
    "phones": [
      "213600000"
    ]
  },
  {
    "key": "alvarofigueiredofilhoslda",
    "nome": "Álvaro Figueiredo & Filhos, Lda.",
    "acao": "existente",
    "alvo": "1e3c15f8-94a3-4a50-899e-0327440ca82c",
    "alvo_nome": "Álvaro Figueiredo & Filhos, Lda",
    "email": "alvaro.filhos@sapo.pt",
    "telefone": "219151328",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 6; nome na fonte: Álvaro Figueiredo & Filhos, Lda.\nAtividade: Materiais de construção\nLocalidade/morada: Rio de Mouro\nContactos na fonte: 219151328\nEmails na fonte: alvaro.filhos@sapo.pt",
    "emails": [
      "alvaro.filhos@sapo.pt"
    ],
    "phones": [
      "219151328"
    ]
  },
  {
    "key": "macolide",
    "nome": "Macolide",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@macolide.pt",
    "telefone": "211633633",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 7; nome na fonte: Macolide\nAtividade: Área da Cozinha, Revestimentos Interiores/Exteriores, Salas de Banho\nLocalidade/morada: Lisboa/Cascais\nContactos na fonte: 211 633 633\nEmails na fonte: info@macolide.pt",
    "emails": [
      "info@macolide.pt"
    ],
    "phones": [
      "211633633"
    ]
  },
  {
    "key": "prink",
    "nome": "Prink",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "trajouce@prink.pt",
    "telefone": "218035016",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 8; nome na fonte: Prink\nAtividade: Rolos de papel e tinteiros\nLocalidade/morada: Trajouce\nContactos na fonte: 218035016\nEmails na fonte: trajouce@prink.pt",
    "emails": [
      "trajouce@prink.pt"
    ],
    "phones": [
      "218035016"
    ]
  },
  {
    "key": "bact3riacom",
    "nome": "Bact3ria.com",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "lab@bact3ria.com",
    "telefone": "214602910",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 9; nome na fonte: Bact3ria.com\nAtividade: Empresa de publicidade\nLocalidade/morada: Alcabideche\nContactos na fonte: 214602910\nEmails na fonte: lab@bact3ria.com",
    "emails": [
      "lab@bact3ria.com"
    ],
    "phones": [
      "214602910"
    ]
  },
  {
    "key": "securitycenter",
    "nome": "Security Center",
    "acao": "existente",
    "alvo": "254d4a5b-d614-4742-b5d0-a211b1e2136b",
    "alvo_nome": "Security Center",
    "email": "info@securitycenter.pt",
    "telefone": "214589000",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 10; nome na fonte: Security Center\nContactos na fonte: 214589000\nEmails na fonte: info@securitycenter.pt",
    "emails": [
      "info@securitycenter.pt"
    ],
    "phones": [
      "214589000"
    ]
  },
  {
    "key": "impersol",
    "nome": "Impersol",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@impersol.pt",
    "telefone": "218496329",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 11; nome na fonte: Impersol\nAtividade: Películas\nLocalidade/morada: Lisboa\nContactos na fonte: 218496329\nEmails na fonte: geral@impersol.pt",
    "emails": [
      "geral@impersol.pt"
    ],
    "phones": [
      "218496329"
    ]
  },
  {
    "key": "ajnavalho",
    "nome": "AJ Navalho",
    "acao": "existente",
    "alvo": "5ccdea1a-cecc-4098-a5ba-0bddbc4057fc",
    "alvo_nome": "A.J. Navalho, Lda",
    "email": "compras@ajnavalho.pt",
    "telefone": "214353867",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 13; nome na fonte: AJ Navalho\nAtividade: Materiais de construção\nLocalidade/morada: Queluz\nContactos na fonte: 214 353 867\nEmails na fonte: compras@ajnavalho.pt",
    "emails": [
      "compras@ajnavalho.pt"
    ],
    "phones": [
      "214353867"
    ]
  },
  {
    "key": "inkgo",
    "nome": "Ink&Go",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "lojaoeirasparque@inkandgo.pt",
    "telefone": "211629350",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 16; nome na fonte: Ink&Go\nAtividade: Enchimento tinteiros impressoras\nLocalidade/morada: Oeiras\nContactos na fonte: 211629350\nEmails na fonte: lojaoeirasparque@inkandgo.pt",
    "emails": [
      "lojaoeirasparque@inkandgo.pt"
    ],
    "phones": [
      "211629350"
    ]
  },
  {
    "key": "clarimat",
    "nome": "Clarimat",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@clarimat.pt",
    "telefone": "249145371",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 21; nome na fonte: Clarimat\nAtividade: Materiais de Construção\nLocalidade/morada: Fátima\nContactos na fonte: 249145371\nEmails na fonte: geral@clarimat.pt",
    "emails": [
      "geral@clarimat.pt"
    ],
    "phones": [
      "249145371"
    ]
  },
  {
    "key": "italbox",
    "nome": "ITALBOX",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "pedro.silva@italbox.pt",
    "telefone": "912305716",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 23; nome na fonte: ITALBOX\nAtividade: Resguardos/ cabines de casa de banho, mobiliário wc\nContactos na fonte: 912 305 716\nEmails na fonte: pedro.silva@italbox.pt\nObservações da fonte: Pedro Silva",
    "emails": [
      "pedro.silva@italbox.pt"
    ],
    "phones": [
      "912305716"
    ]
  },
  {
    "key": "alcatifex",
    "nome": "ALCATIFEX",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "212747061",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 28; nome na fonte: ALCATIFEX\nAtividade: Alcatifas\nLocalidade/morada: Almada\nContactos na fonte: 212747061",
    "emails": [],
    "phones": [
      "212747061"
    ]
  },
  {
    "key": "hatelier19",
    "nome": "HÁTELIER 19",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "sales.sofiarocha@gmail.com",
    "telefone": "937377301",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 33; nome na fonte: HÁTELIER 19\nAtividade: Comércio de materiais para a construção, remodelação e decoração de interiores\nLocalidade/morada: S. Domingos de Rana\nContactos na fonte: 937377301\nEmails na fonte: sales.sofiarocha@gmail.com\nObservações da fonte: Sofia Rocha",
    "emails": [
      "sales.sofiarocha@gmail.com"
    ],
    "phones": [
      "937377301"
    ]
  },
  {
    "key": "azulaico",
    "nome": "Azulaico",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comunicacao@azulaico.com",
    "telefone": "255490130",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 38; nome na fonte: Azulaico\nAtividade: Comércio de materiais de construção para a casa: casas de banho, cozinhas, pavimentos e revestimentos, sistemas de climatização e soluções de construção.\nLocalidade/morada: Avenida da República Nº635 4615-676 - Lixa\nContactos na fonte: 255490130\nEmails na fonte: comunicacao@azulaico.com",
    "emails": [
      "comunicacao@azulaico.com"
    ],
    "phones": [
      "255490130"
    ]
  },
  {
    "key": "extracabos",
    "nome": "ExtraCabos",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial@extra-cabos.pt",
    "telefone": "212256818",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MATERIAIS DE CONSTRUÇÃO E DIVER; linha: 40; nome na fonte: ExtraCabos\nAtividade: Cabos de aço, correntes, acessórios e equipamentos de elevação\nLocalidade/morada: Praceta Emílio Santana, nº2B Casal do Marco 2840-588 Aldeia de Paio Pires - Seixal Portugal\nContactos na fonte: 212256818\nEmails na fonte: comercial@extra-cabos.pt\nObservações da fonte: www.extracabos.pt",
    "emails": [
      "comercial@extra-cabos.pt"
    ],
    "phones": [
      "212256818"
    ]
  },
  {
    "key": "previmed",
    "nome": "Previmed",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@previmed.pt",
    "telefone": "213161899",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MEDICINA NO TRABALHO; linha: 5; nome na fonte: Previmed\nAtividade: Medicina no trabalho\nLocalidade/morada: Lisboa\nContactos na fonte: 213161899\nEmails na fonte: geral@previmed.pt\nObservações da fonte: 10 de Outubro 2025 as 16:26",
    "emails": [
      "geral@previmed.pt"
    ],
    "phones": [
      "213161899"
    ]
  },
  {
    "key": "rendl",
    "nome": "Rendl",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@rendl.pt",
    "telefone": "253930231",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MOBILIÁRIO DE INTERIORES; linha: 7; nome na fonte: Rendl\nAtividade: Luzes e candeeiros\nContactos na fonte: 253930231\nEmails na fonte: info@rendl.pt\nObservações da fonte: system4@rendl.com",
    "emails": [
      "info@rendl.pt"
    ],
    "phones": [
      "253930231"
    ]
  },
  {
    "key": "rubato",
    "nome": "RUBATO",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "contact@rubato.studio",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MODELAÇÃO E RENDERIZAÇÃO; linha: 5; nome na fonte: RUBATO\nAtividade: Modelação tridimensional e renderização de projetos de arquitetura e imobiliário\nEmails na fonte: contact@rubato.studio\nObservações da fonte: Leonardo Barros",
    "emails": [
      "contact@rubato.studio"
    ],
    "phones": []
  },
  {
    "key": "israelfilho",
    "nome": "Israel Filho",
    "acao": "existente",
    "alvo": "7e5bb956-4d59-41b4-92c9-25c2338fe3c5",
    "alvo_nome": "Israel & Filho, Lda",
    "email": "israelefilho@gmail.com",
    "telefone": "939605157",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: MOVIMENTO DE TERRAS; linha: 7; nome na fonte: Israel Filho\nAtividade: Aterros, desaterros e terraplanagens\nLocalidade/morada: Terrugem\nContactos na fonte: 939605157\nEmails na fonte: israelefilho@gmail.com\nObservações da fonte: Paulo Esteves",
    "emails": [
      "israelefilho@gmail.com"
    ],
    "phones": [
      "939605157"
    ]
  },
  {
    "key": "gasovalaconstrucoesunipessoallda",
    "nome": "Gasovala Construções Unipessoal Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "919651898 / 913355785",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS BETUMINOSOS; linha: 6; nome na fonte: Gasovala Construções Unipessoal Lda\nAtividade: Pavimentos betuminosos e trabalhos de obras públicas\nLocalidade/morada: Torres Vedras\nContactos na fonte: 919651898 913355785\nObservações da fonte: mail recebido a 10/01/2023 (geral@primeline.pt)",
    "emails": [],
    "phones": [
      "919651898",
      "913355785"
    ]
  },
  {
    "key": "udeck",
    "nome": "U-DECK",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "u.deckrg@gmail.com",
    "telefone": "262841026 / 964097821",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 5; nome na fonte: U-DECK\nAtividade: PAVIMENTOS E REVESTIMENTOS\nLocalidade/morada: Caldas da Rainha\nContactos na fonte: 262 841 026 964 097 821\nEmails na fonte: u.deckrg@gmail.com",
    "emails": [
      "u.deckrg@gmail.com"
    ],
    "phones": [
      "262841026",
      "964097821"
    ]
  },
  {
    "key": "pavieste",
    "nome": "Pavieste",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@pavieste.pt",
    "telefone": "227410115",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 7; nome na fonte: Pavieste\nAtividade: Pavimentos em betão\nLocalidade/morada: Gaia\nContactos na fonte: 227 410 115/6\nEmails na fonte: geral@pavieste.pt",
    "emails": [
      "geral@pavieste.pt"
    ],
    "phones": [
      "227410115"
    ]
  },
  {
    "key": "mesasmarmore",
    "nome": "Mesas&Mármore",
    "acao": "existente",
    "alvo": "b9fbe875-eea8-41ea-bc13-10b6ea33ec19",
    "alvo_nome": "Mesas & Mármore",
    "email": "geral@mesasemarmore.com",
    "telefone": "969642276",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 10; nome na fonte: Mesas&Mármore\nAtividade: Ladrilhador\nLocalidade/morada: Cascais\nContactos na fonte: 969642276\nEmails na fonte: geral@mesasemarmore.com",
    "emails": [
      "geral@mesasemarmore.com"
    ],
    "phones": [
      "969642276"
    ]
  },
  {
    "key": "stonecare",
    "nome": "STONECARE",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "218109010",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 18; nome na fonte: STONECARE\nAtividade: Restauração de pedra\nContactos na fonte: 218109010",
    "emails": [],
    "phones": [
      "218109010"
    ]
  },
  {
    "key": "techlam",
    "nome": "Techlam",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "techlam@galrao.com",
    "telefone": "934820133",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 20; nome na fonte: Techlam\nAtividade: Pedra sinterizada\nLocalidade/morada: Av. Da Liberdade, 153, 2715-004 Pêro Pinheiro, Portugal\nContactos na fonte: 351934820133\nEmails na fonte: techlam@galrao.com",
    "emails": [
      "techlam@galrao.com"
    ],
    "phones": [
      "934820133"
    ]
  },
  {
    "key": "bondeck",
    "nome": "Bondeck",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "catarina.zanatti@bondeck.pt",
    "telefone": "917527931",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 21; nome na fonte: Bondeck\nAtividade: Fornecimento e instalação de revestimentos exteriores.\nLocalidade/morada: Rua do Tejo 63, 1º Esq. Cascais, Portugal\nContactos na fonte: 917527931\nEmails na fonte: catarina.zanatti@bondeck.pt\nObservações da fonte: bondeck.pt",
    "emails": [
      "catarina.zanatti@bondeck.pt"
    ],
    "phones": [
      "917527931"
    ]
  },
  {
    "key": "cdmstravitec",
    "nome": "CDM Stravitec",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "226877907 / 934979864",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 24; nome na fonte: CDM Stravitec\nAtividade: Pavimentos de Construção Seca vs em Betão\nLocalidade/morada: Reutenbeek 9-11 Overijse 3090 Belgium\nContactos na fonte: +32 2 687 79 07\nEmails na fonte: info@cdm-stravitec.com\n\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 26; nome na fonte: CDM Stravitec\nAtividade: Sistemas de isolamento acústico e de vibração para edifícios e mercados industriais.\nLocalidade/morada: Avenida Cáceres Monteiro, 10, 4º Piso, Fração N Edificio Arquiparque II 1495-192 Algés\nContactos na fonte: 934979864\nEmails na fonte: s.quaresma@cdm-stravitec.com\nObservações da fonte: Sérgio Quaresma, 217 110 430",
    "emails": [
      "info@cdm-stravitec.com",
      "s.quaresma@cdm-stravitec.com"
    ],
    "phones": [
      "226877907",
      "934979864"
    ]
  },
  {
    "key": "normagem",
    "nome": "Normagem",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "joao.miguel@normamargem.pt",
    "telefone": "215825485",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PAVIMENTOS E REVESTIMENTOS; linha: 25; nome na fonte: Normagem\nAtividade: Empresa de mármore\nLocalidade/morada: R. de São Pedro 10, 2715-771 Terrugem\nContactos na fonte: 215825485\nEmails na fonte: joao.miguel@normamargem.pt",
    "emails": [
      "joao.miguel@normamargem.pt"
    ],
    "phones": [
      "215825485"
    ]
  },
  {
    "key": "avelinorte",
    "nome": "Avelinorte",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@avelinorte.pt",
    "telefone": "229510518",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PINTURAS; linha: 6; nome na fonte: Avelinorte\nAtividade: Gesso cartonado e pinturas\nLocalidade/morada: Matosinhos\nContactos na fonte: 229 510 518\nEmails na fonte: geral@avelinorte.pt",
    "emails": [
      "geral@avelinorte.pt"
    ],
    "phones": [
      "229510518"
    ]
  },
  {
    "key": "danilocandido",
    "nome": "Danilo Candido",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "968206549",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PINTURAS; linha: 8; nome na fonte: Danilo Candido\nAtividade: Pintor\nContactos na fonte: 968206549",
    "emails": [],
    "phones": [
      "968206549"
    ]
  },
  {
    "key": "texcoatrevestimentosepinturaslda",
    "nome": "Texcoat - Revestimentos e Pinturas, Lda",
    "acao": "existente",
    "alvo": "09cae0ad-dc58-46a3-be1e-a686e5642ac9",
    "alvo_nome": "Texcoat - Revestimentos e Pinturas, Lda",
    "email": "geral@texcoat.pt",
    "telefone": "217622428 / 966800250",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PINTURAS; linha: 13; nome na fonte: Texcoat - Revestimentos e Pinturas, Lda\nAtividade: Revestimentos e Pinturas\nLocalidade/morada: Benfica\nContactos na fonte: 217 622 428 966 800 250\nEmails na fonte: geral@texcoat.pt",
    "emails": [
      "geral@texcoat.pt"
    ],
    "phones": [
      "217622428",
      "966800250"
    ]
  },
  {
    "key": "verdeperiodicolda",
    "nome": "Verde Periódico, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "itrenovacoes@gmail.com",
    "telefone": "939361738",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PINTURAS; linha: 21; nome na fonte: Verde Periódico, Lda\nAtividade: Acabamentos, Pinturas, Barramentos, Pladur\nContactos na fonte: 939361738\nEmails na fonte: itrenovacoes@gmail.com",
    "emails": [
      "itrenovacoes@gmail.com"
    ],
    "phones": [
      "939361738"
    ]
  },
  {
    "key": "trophic",
    "nome": "Trophic",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@trophic.pt",
    "telefone": "910742814",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PISCINAS; linha: 6; nome na fonte: Trophic\nAtividade: Piscinas Naturais, Lagos Biológicos\nContactos na fonte: 910742814\nEmails na fonte: info@trophic.pt",
    "emails": [
      "info@trophic.pt"
    ],
    "phones": [
      "910742814"
    ]
  },
  {
    "key": "mergulhosalgado",
    "nome": "Mergulho Salgado",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "patricia@mergulhosalgado.pt",
    "telefone": "962444011",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PISCINAS; linha: 7; nome na fonte: Mergulho Salgado\nAtividade: Piscinas e Jacuzzis\nLocalidade/morada: Sintra\nContactos na fonte: 962444011\nEmails na fonte: patricia@mergulhosalgado.pt\nObservações da fonte: Patrícia Alves",
    "emails": [
      "patricia@mergulhosalgado.pt"
    ],
    "phones": [
      "962444011"
    ]
  },
  {
    "key": "pavistampportugal",
    "nome": "PAVISTAMP PORTUGAL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial.portugal@pavistamp.com",
    "telefone": "914721100",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PISCINAS; linha: 13; nome na fonte: PAVISTAMP PORTUGAL\nAtividade: Soluções em microcimento e revestimento para piscinas\nLocalidade/morada: Espanha\nEmails na fonte: comercial.portugal@pavistamp.com\nObservações da fonte: Sr. Rogério Neto\n\nFolha: TINTAS; linha: 6; nome na fonte: PAVISTAMP Portugal\nAtividade: Tinta de cimento (sistema decosol)\nLocalidade/morada: Espanha\nContactos na fonte: 351914721100\nEmails na fonte: comercial.portugal@pavistamp.com\nObservações da fonte: Rute Neto",
    "emails": [
      "comercial.portugal@pavistamp.com"
    ],
    "phones": [
      "914721100"
    ]
  },
  {
    "key": "mavigrade",
    "nome": "Mavigrade",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "mavigrade@gmail.com",
    "telefone": "219677066",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PORTAS, PORTÕES E JANELAS; linha: 7; nome na fonte: Mavigrade\nAtividade: Fabrico de Portas, Grades Metálicas e Automatismos\nLocalidade/morada: Sintra\nContactos na fonte: 219677066/9\nEmails na fonte: mavigrade@gmail.com",
    "emails": [
      "mavigrade@gmail.com"
    ],
    "phones": [
      "219677066"
    ]
  },
  {
    "key": "flexiportas",
    "nome": "Flexiportas",
    "acao": "existente",
    "alvo": "628b37ae-0e12-46da-8afe-f44fab998615",
    "alvo_nome": "Flexiportas, Lda",
    "email": "geral@flexiportas.com",
    "telefone": "219584029",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PORTAS, PORTÕES E JANELAS; linha: 9; nome na fonte: Flexiportas\nAtividade: Portas e Automatismos\nLocalidade/morada: Alverca\nContactos na fonte: 219584029\nEmails na fonte: geral@flexiportas.com\nObservações da fonte: Sr. Pedro Lima",
    "emails": [
      "geral@flexiportas.com"
    ],
    "phones": [
      "219584029"
    ]
  },
  {
    "key": "doorwork",
    "nome": "DoorWork",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "224103415",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PORTAS, PORTÕES E JANELAS; linha: 10; nome na fonte: DoorWork\nAtividade: Portas e Automatismos\nLocalidade/morada: Maia\nContactos na fonte: 224103415\nEmails na fonte: doorwork.pt",
    "emails": [],
    "phones": [
      "224103415"
    ]
  },
  {
    "key": "gercima",
    "nome": "Gercima",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "gercima@gercima.com.pt",
    "telefone": "252951748",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PORTAS, PORTÕES E JANELAS; linha: 12; nome na fonte: Gercima\nAtividade: Indústria de janelas em madeira e portas isolantes\nLocalidade/morada: Terra Negra, R. da Covilhã nº155, 4775-206 Negreiros\nContactos na fonte: 252951748\nEmails na fonte: gercima@gercima.com.pt",
    "emails": [
      "gercima@gercima.com.pt"
    ],
    "phones": [
      "252951748"
    ]
  },
  {
    "key": "rudder",
    "nome": "Rudder",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "rudder.pt@gmail.com",
    "telefone": "917344799",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PORTAS, PORTÕES E JANELAS; linha: 14; nome na fonte: Rudder\nAtividade: Portões e Automatismo\nContactos na fonte: 917344799\nEmails na fonte: rudder.pt@gmail.com",
    "emails": [
      "rudder.pt@gmail.com"
    ],
    "phones": [
      "917344799"
    ]
  },
  {
    "key": "proestor",
    "nome": "Proestor",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "anacleto.fernandes14@gmail.com",
    "telefone": "917552513",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PROTEÇÃO SOLAR; linha: 6; nome na fonte: Proestor\nAtividade: Estores, coberturas, proteção solar\nContactos na fonte: 917 552 513\nEmails na fonte: anacleto.fernandes14@gmail.com",
    "emails": [
      "anacleto.fernandes14@gmail.com"
    ],
    "phones": [
      "917552513"
    ]
  },
  {
    "key": "gradhermetic",
    "nome": "Gradhermetic",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "eteodoro@gradhermetic.es",
    "telefone": "935032542",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PROTEÇÃO SOLAR; linha: 7; nome na fonte: Gradhermetic\nAtividade: Proteção solar\nContactos na fonte: 935032542\nEmails na fonte: eteodoro@gradhermetic.es",
    "emails": [
      "eteodoro@gradhermetic.es"
    ],
    "phones": [
      "935032542"
    ]
  },
  {
    "key": "nearimaginationunipessoallda",
    "nome": "Near Imagination, Unipessoal, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "nearimagination@gmail.com",
    "telefone": "241406446 / 965597621",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: PUBLICIDADE; linha: 7; nome na fonte: Near Imagination, Unipessoal, Lda\nAtividade: Design, impressão, serigrafia, brindes\nLocalidade/morada: Belver\nContactos na fonte: 241 406 446 965 597 621\nEmails na fonte: nearimagination@gmail.com",
    "emails": [
      "nearimagination@gmail.com"
    ],
    "phones": [
      "241406446",
      "965597621"
    ]
  },
  {
    "key": "mtcpeople",
    "nome": "MTC People",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@mtcpeople.com",
    "telefone": "911797161",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 6; nome na fonte: MTC People\nAtividade: Recrutamento e seleção de perfis que mais se adequam às necessidades laborais do cliente\nLocalidade/morada: Rua do Poente, n.º 142 1º andar 4785-509 Trofa, Porto, Portugal\nContactos na fonte: 911797161\nEmails na fonte: geral@mtcpeople.com\nObservações da fonte: JOANA BROCHADO joanabrochado@mtcpeople.com (+351) 22 319 8139",
    "emails": [
      "geral@mtcpeople.com"
    ],
    "phones": [
      "911797161"
    ]
  },
  {
    "key": "orbitaoasica",
    "nome": "Orbita Oasica",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "orbita.mkg@gmail.com",
    "telefone": "914139142",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 9; nome na fonte: Orbita Oasica\nAtividade: Eletricistas, canalizadores, carpinteiros, pintores, colocadores de piso e pedreiro\nLocalidade/morada: Rua de Angola, 7800-468, Beja\nContactos na fonte: 914139142\nEmails na fonte: orbita.mkg@gmail.com",
    "emails": [
      "orbita.mkg@gmail.com"
    ],
    "phones": [
      "914139142"
    ]
  },
  {
    "key": "timing",
    "nome": "Timing",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@timing.pt",
    "telefone": null,
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 10; nome na fonte: Timing\nAtividade: Trabalho temporário e Recursos humanos\nLocalidade/morada: Lisboa, Algarve e Madeira\nContactos na fonte: 707915566\nEmails na fonte: info@timing.pt",
    "emails": [
      "info@timing.pt"
    ],
    "phones": []
  },
  {
    "key": "voicewave",
    "nome": "Voice Wave",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "martin.laurent@voicewave.io",
    "telefone": "937144295",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 13; nome na fonte: Voice Wave\nAtividade: Mão de obra\nLocalidade/morada: Avenida Almirante Reis, 91 Andar - 1º Dt, Lisboa\nContactos na fonte: 937144295\nEmails na fonte: martin.laurent@voicewave.io",
    "emails": [
      "martin.laurent@voicewave.io"
    ],
    "phones": [
      "937144295"
    ]
  },
  {
    "key": "pw30",
    "nome": "PW30",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "218203230",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 15; nome na fonte: PW30\nAtividade: Recrutamento de pessoal especializado\nLocalidade/morada: Rua Alves Redol nº3 Loja 3 A 2675-285\nContactos na fonte: 218203230\nEmails na fonte: www.pw30.pt",
    "emails": [],
    "phones": [
      "218203230"
    ]
  },
  {
    "key": "escalaveteran",
    "nome": "Escala Veteran",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "luis.alves@escalaveterana.com",
    "telefone": "920656556",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 17; nome na fonte: Escala Veteran\nAtividade: Recrutamento de manobradores, carpinteiros, pedreiros, armadores de ferro, serventes\nContactos na fonte: 351920656556\nEmails na fonte: luis.alves@escalaveterana.com",
    "emails": [
      "luis.alves@escalaveterana.com"
    ],
    "phones": [
      "920656556"
    ]
  },
  {
    "key": "sparkjobs",
    "nome": "Spark Jobs",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@sparkjobs.pt",
    "telefone": "964557670",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: RECRUTAMENTO DE PESSOAL; linha: 19; nome na fonte: Spark Jobs\nAtividade: Fornecimento de equipa qualificada\nLocalidade/morada: Rua Ramalho Ortigão Nr: 6 Loja Esq, sala A,\nContactos na fonte: 964557670\nEmails na fonte: geral@sparkjobs.pt",
    "emails": [
      "geral@sparkjobs.pt"
    ],
    "phones": [
      "964557670"
    ]
  },
  {
    "key": "pollistonepolimentoevitrificacao",
    "nome": "POLLISTONE - Polimento e Vitrificação",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@pollistone.pt",
    "telefone": "912166014",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: REVESTIMENTOS EM PEDRA; linha: 5; nome na fonte: POLLISTONE - Polimento e Vitrificação\nAtividade: Polimento e Vitrificação\nLocalidade/morada: Praceta da Rosa, Nº 2 - 1º Dtº Paço de Arcos\nContactos na fonte: 912166014\nEmails na fonte: geral@pollistone.pt",
    "emails": [
      "geral@pollistone.pt"
    ],
    "phones": [
      "912166014"
    ]
  },
  {
    "key": "porcelanosagrupo",
    "nome": "Porcelanosa Grupo",
    "acao": "existente",
    "alvo": "c03c80b9-2b44-465c-ad94-2e58b82e6555",
    "alvo_nome": "PORCELANOSA Grupo",
    "email": "atencaoaocliente@lisboa.porcelonosa.com",
    "telefone": "218313020",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: REVESTIMENTOS EM PEDRA; linha: 7; nome na fonte: Porcelanosa Grupo\nAtividade: Fabricante de revestimentos cerâmicos\nLocalidade/morada: Av. Infante D. Henrique, Nº325 1800-217 Lisboa Portugal\nContactos na fonte: 218313020\nEmails na fonte: atencaoaocliente@lisboa.porcelonosa.com",
    "emails": [
      "atencaoaocliente@lisboa.porcelonosa.com"
    ],
    "phones": [
      "218313020"
    ]
  },
  {
    "key": "maxivitor",
    "nome": "Maxivitor",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "maxivitor@maxivitor.pt",
    "telefone": "214690198",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 12; nome na fonte: Maxivitor\nAtividade: Serralharia\nLocalidade/morada: Atrozela\nContactos na fonte: 214690198\nEmails na fonte: maxivitor@maxivitor.pt",
    "emails": [
      "maxivitor@maxivitor.pt"
    ],
    "phones": [
      "214690198"
    ]
  },
  {
    "key": "metalogalva",
    "nome": "Metalogalva",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "metalogalva@metalogalva.pt",
    "telefone": "252400520",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 13; nome na fonte: Metalogalva\nAtividade: Galvanização\nContactos na fonte: 252400520\nEmails na fonte: metalogalva@metalogalva.pt",
    "emails": [
      "metalogalva@metalogalva.pt"
    ],
    "phones": [
      "252400520"
    ]
  },
  {
    "key": "martifer",
    "nome": "Martifer",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "pedro.rodrigues@martifer.com",
    "telefone": "935990245",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 16; nome na fonte: Martifer\nAtividade: Construção metálica, alumínios\nLocalidade/morada: Oliveira de Frades\nContactos na fonte: 935 990 245\nEmails na fonte: pedro.rodrigues@martifer.com\nObservações da fonte: Pedro Rodrigues",
    "emails": [
      "pedro.rodrigues@martifer.com"
    ],
    "phones": [
      "935990245"
    ]
  },
  {
    "key": "cubotonic",
    "nome": "CUBOTÓNIC",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@cubotonic.pt",
    "telefone": "210497230",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 23; nome na fonte: CUBOTÓNIC\nAtividade: Corte a laser, quinagens, tranf de metais\nLocalidade/morada: Venda do Pinheiro\nContactos na fonte: 210497230\nEmails na fonte: geral@cubotonic.pt",
    "emails": [
      "geral@cubotonic.pt"
    ],
    "phones": [
      "210497230"
    ]
  },
  {
    "key": "lusamar",
    "nome": "Lusamar",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@lusamar.pt",
    "telefone": "219861858",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 24; nome na fonte: Lusamar\nAtividade: Serralharia industrial\nLocalidade/morada: Malveira\nContactos na fonte: 219861858\nEmails na fonte: geral@lusamar.pt",
    "emails": [
      "geral@lusamar.pt"
    ],
    "phones": [
      "219861858"
    ]
  },
  {
    "key": "solmetrik",
    "nome": "Solmetrik",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral.solmetrik@hotmail.com",
    "telefone": "219673183",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 26; nome na fonte: Solmetrik\nAtividade: CORTE / QUINAGEM, FURAÇÕES ESPECIAIS,CORTE A PLASMA\nLocalidade/morada: Montelavar\nContactos na fonte: 219673183\nEmails na fonte: geral.solmetrik@hotmail.com",
    "emails": [
      "geral.solmetrik@hotmail.com"
    ],
    "phones": [
      "219673183"
    ]
  },
  {
    "key": "hidrauludalda",
    "nome": "HIDRÁULUDA, Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "252911327 / 914852788",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 31; nome na fonte: HIDRÁULUDA, Lda\nAtividade: Serralharia e Metalomecânica\nLocalidade/morada: Rua Nova, nº381, S. Cosme do Vale, 4770-563 V. N. Famalicão\nContactos na fonte: 252 911 327 914 852 788\nEmails na fonte: gestao.serralharia@anfersilinvest.pt filipe.martins@anfersilgrupo.pt\nObservações da fonte: Grupo ANFERSIL",
    "emails": [
      "gestao.serralharia@anfersilinvest.pt",
      "filipe.martins@anfersilgrupo.pt"
    ],
    "phones": [
      "252911327",
      "914852788"
    ]
  },
  {
    "key": "desimetal",
    "nome": "DESIMETAL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "antonio.antunes@desimetal.pt",
    "telefone": "219221857",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SERRALHARIAS; linha: 35; nome na fonte: DESIMETAL\nAtividade: Serralharia Geral\nLocalidade/morada: Rua das Flores, Bairro São Carlos, Mem Martins\nContactos na fonte: 219 221 857\nEmails na fonte: antonio.antunes@desimetal.pt\nObservações da fonte: António Antunes (917 643 121)",
    "emails": [
      "antonio.antunes@desimetal.pt"
    ],
    "phones": [
      "219221857"
    ]
  },
  {
    "key": "cesarinox",
    "nome": "CESAR INOX",
    "acao": "existente",
    "alvo": "1140b7a5-a284-4dfd-bb52-3f0c6255709a",
    "alvo_nome": "CesarINOX",
    "email": "geral@cesarinox.com",
    "telefone": "925162414",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SOLUÇÕES EM INOX; linha: 6; nome na fonte: CESAR INOX\nAtividade: Soluções em inox\nLocalidade/morada: Leiria\nContactos na fonte: 925162414\nEmails na fonte: geral@cesarinox.com",
    "emails": [
      "geral@cesarinox.com"
    ],
    "phones": [
      "925162414"
    ]
  },
  {
    "key": "corrige",
    "nome": "Corrige",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@corrige.pt",
    "telefone": "219826810",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SISTEMA CAPOTO - ETICS; linha: 7; nome na fonte: Corrige\nAtividade: Execução de Capoto\nLocalidade/morada: Loures\nContactos na fonte: 219826810\nEmails na fonte: geral@corrige.pt",
    "emails": [
      "geral@corrige.pt"
    ],
    "phones": [
      "219826810"
    ]
  },
  {
    "key": "isotherm",
    "nome": "Isotherm",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@isotherm.pt",
    "telefone": "214057389",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SISTEMA CAPOTO - ETICS; linha: 8; nome na fonte: Isotherm\nAtividade: Execução de Capoto\nLocalidade/morada: Loures\nContactos na fonte: 214057389\nEmails na fonte: info@isotherm.pt",
    "emails": [
      "info@isotherm.pt"
    ],
    "phones": [
      "214057389"
    ]
  },
  {
    "key": "ptetos",
    "nome": "PTETOS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "914315648",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SISTEMA CAPOTO - ETICS; linha: 11; nome na fonte: PTETOS\nAtividade: Capoto e tetos falsos\nContactos na fonte: 914 315 648",
    "emails": [],
    "phones": [
      "914315648"
    ]
  },
  {
    "key": "odibol",
    "nome": "Odibol",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "964017472",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SISTEMA CAPOTO - ETICS; linha: 12; nome na fonte: Odibol\nAtividade: Execução de Capotos\nLocalidade/morada: Odivelas\nContactos na fonte: 964017472",
    "emails": [],
    "phones": [
      "964017472"
    ]
  },
  {
    "key": "nadiasinalizacao",
    "nome": "Nadia-Sinalização",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@nadia-sinalizacao.com",
    "telefone": "214251760",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SINALIZAÇÃO; linha: 5; nome na fonte: Nadia-Sinalização\nAtividade: Sinalização e segurança rodoviária\nLocalidade/morada: Amadora\nContactos na fonte: 214251760\nEmails na fonte: geral@nadia-sinalizacao.com",
    "emails": [
      "geral@nadia-sinalizacao.com"
    ],
    "phones": [
      "214251760"
    ]
  },
  {
    "key": "smartpath",
    "nome": "SMARTPATH",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "info@smartpath.pt",
    "telefone": "215868730 / 915697558",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SINALIZAÇÃO; linha: 6; nome na fonte: SMARTPATH\nAtividade: Sinalização e segurança rodoviária\nLocalidade/morada: Abrunheira\nContactos na fonte: 215 868 730 915 697 558\nEmails na fonte: info@smartpath.pt",
    "emails": [
      "info@smartpath.pt"
    ],
    "phones": [
      "215868730",
      "915697558"
    ]
  },
  {
    "key": "laborelda",
    "nome": "LABORE, LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "labore@sinalplus.pt",
    "telefone": "219738190",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SINALIZAÇÃO; linha: 7; nome na fonte: LABORE, LDA\nAtividade: Sinalização e segurança rodoviária\nLocalidade/morada: Vialonga\nContactos na fonte: 219738190\nEmails na fonte: labore@sinalplus.pt",
    "emails": [
      "labore@sinalplus.pt"
    ],
    "phones": [
      "219738190"
    ]
  },
  {
    "key": "tecjob",
    "nome": "TecJob",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "moliveira@tecjob.pt",
    "telefone": "269441200",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SINALIZAÇÃO; linha: 8; nome na fonte: TecJob\nAtividade: Empresa especializada no fabrico de sinalização fotoluminescente de segurança e identificação\nLocalidade/morada: Zona Industrial Ligeira Lote 3 7570-224 Grândola\nContactos na fonte: 269441200\nEmails na fonte: moliveira@tecjob.pt",
    "emails": [
      "moliveira@tecjob.pt"
    ],
    "phones": [
      "269441200"
    ]
  },
  {
    "key": "tracossemelhancasconstrucaocivillda",
    "nome": "Traços & Semelhanças-Construção Civil Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "219755625",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 7; nome na fonte: Traços & Semelhanças-Construção Civil Lda\nLocalidade/morada: Avenida Portugal 9-N Póvoa da Galega 2665-357 MILHARADO\nContactos na fonte: 219755625",
    "emails": [],
    "phones": [
      "219755625"
    ]
  },
  {
    "key": "cansyfree",
    "nome": "CANSYFREE",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "933092573",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 8; nome na fonte: CANSYFREE\nAtividade: Construções, Silvicultura e Imobiliário\nLocalidade/morada: Santarém\nContactos na fonte: 933 092 573",
    "emails": [],
    "phones": [
      "933092573"
    ]
  },
  {
    "key": "ergsilva",
    "nome": "Ergsilva",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@ergsilva.com",
    "telefone": "244686326",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 9; nome na fonte: Ergsilva\nAtividade: Construção, Restauro e Reabilitação\nLocalidade/morada: Leiria\nContactos na fonte: 244 686 326\nEmails na fonte: geral@ergsilva.com",
    "emails": [
      "geral@ergsilva.com"
    ],
    "phones": [
      "244686326"
    ]
  },
  {
    "key": "matamataconstrucoeslda",
    "nome": "Mata & Mata - Construções Lda",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "219111194",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 10; nome na fonte: Mata & Mata - Construções Lda\nLocalidade/morada: Rio de Mouro\nContactos na fonte: 21 911 11 94",
    "emails": [],
    "phones": [
      "219111194"
    ]
  },
  {
    "key": "place2b",
    "nome": "Place2B",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@place2b.pt",
    "telefone": "915772981",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 11; nome na fonte: Place2B\nAtividade: Engenharia e design\nLocalidade/morada: Estoril\nContactos na fonte: 915 772 981\nEmails na fonte: geral@place2b.pt",
    "emails": [
      "geral@place2b.pt"
    ],
    "phones": [
      "915772981"
    ]
  },
  {
    "key": "padroessoberanosconstrucaoremodelacaolda",
    "nome": "Padrões Soberanos Construção & Remodelação Lda.",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral.padroesoberanos@hotmail.com",
    "telefone": "967755934",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 12; nome na fonte: Padrões Soberanos Construção & Remodelação Lda.\nAtividade: Construção e remodelação\nLocalidade/morada: Sintra\nContactos na fonte: 967 755 934\nEmails na fonte: geral.padroesoberanos@hotmail.com",
    "emails": [
      "geral.padroesoberanos@hotmail.com"
    ],
    "phones": [
      "967755934"
    ]
  },
  {
    "key": "soprotaco",
    "nome": "SOPROTACO",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "pedro@soprotaco.com",
    "telefone": "963906001",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 13; nome na fonte: SOPROTACO\nAtividade: Tetos falsos, fornecimento, assentamento pav. madeira\nLocalidade/morada: Vila Franca de Xira\nContactos na fonte: 963 906 001\nEmails na fonte: pedro@soprotaco.com\nObservações da fonte: Pedro Pires",
    "emails": [
      "pedro@soprotaco.com"
    ],
    "phones": [
      "963906001"
    ]
  },
  {
    "key": "sonhobra",
    "nome": "Sonhobra",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "sonhobra@sapo.pt",
    "telefone": "929189789",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 18; nome na fonte: Sonhobra\nAtividade: Materiais de contrução e decoração\nLocalidade/morada: Torres Vedras\nContactos na fonte: 929 189 789\nEmails na fonte: sonhobra@sapo.pt\nObservações da fonte: Bruno Leandro",
    "emails": [
      "sonhobra@sapo.pt"
    ],
    "phones": [
      "929189789"
    ]
  },
  {
    "key": "jtfconstrucoes",
    "nome": "JTF. Construções",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral.contrucoes2008@gmail.com",
    "telefone": "215819856 / 915469277",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 19; nome na fonte: JTF. Construções\nAtividade: Remodelações gerais\nLocalidade/morada: Amadora\nContactos na fonte: 215 819 856 915 469 277\nEmails na fonte: geral.contrucoes2008@gmail.com\nObservações da fonte: Pedro Ferreira",
    "emails": [
      "geral.contrucoes2008@gmail.com"
    ],
    "phones": [
      "215819856",
      "915469277"
    ]
  },
  {
    "key": "betabrand",
    "nome": "Betabrand",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "diogo.amaral@betabrand.pt",
    "telefone": "916197373",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 20; nome na fonte: Betabrand\nAtividade: Desenvolvimento, produção e implementação de soluções de Imagem Corporativa e Mobiliário Comercial\nLocalidade/morada: Lisboa\nContactos na fonte: 916 197 373\nEmails na fonte: diogo.amaral@betabrand.pt",
    "emails": [
      "diogo.amaral@betabrand.pt"
    ],
    "phones": [
      "916197373"
    ]
  },
  {
    "key": "grupode3lda",
    "nome": "Grupo de 3, LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "barros-batalha@hotmail.com",
    "telefone": "910848473",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 30; nome na fonte: Grupo de 3, LDA\nAtividade: Construção de edifícios de raíz, limpezas de obras, carpinteiros, fornecimento de mão de obra\nLocalidade/morada: Queluz\nContactos na fonte: 910848473\nEmails na fonte: barros-batalha@hotmail.com",
    "emails": [
      "barros-batalha@hotmail.com"
    ],
    "phones": [
      "910848473"
    ]
  },
  {
    "key": "camontol",
    "nome": "Camontol",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial.camontol@gmail.com",
    "telefone": "969053491",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUBEMPREITEIRO GERAL; linha: 31; nome na fonte: Camontol\nAtividade: Fabrico, comércio e montagem de mobiliário, estruturas e carpintaria de madeira e metais, revestimentos e impermeabilizações.\nLocalidade/morada: Torres Vedras\nContactos na fonte: 969053491\nEmails na fonte: comercial.camontol@gmail.com",
    "emails": [
      "comercial.camontol@gmail.com"
    ],
    "phones": [
      "969053491"
    ]
  },
  {
    "key": "ambimarto",
    "nome": "Ambimarto",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "ambimarto@gmail.com",
    "telefone": "963263318",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: SUCATA; linha: 5; nome na fonte: Ambimarto\nAtividade: Sucatas e Metais\nLocalidade/morada: Trajouce\nContactos na fonte: 963263318\nEmails na fonte: ambimarto@gmail.com",
    "emails": [
      "ambimarto@gmail.com"
    ],
    "phones": [
      "963263318"
    ]
  },
  {
    "key": "belgrani",
    "nome": "BELGRANI",
    "acao": "existente",
    "alvo": "9b0fad9f-6950-4339-aeec-974ce80d3f20",
    "alvo_nome": "Belgrani Lda",
    "email": "administrativo@belgrani.com",
    "telefone": "219678190",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TAMPOS; linha: 5; nome na fonte: BELGRANI\nAtividade: Tampos (Silestone, dekton e pedras naturais)\nLocalidade/morada: Sintra\nContactos na fonte: 219 678 190\nEmails na fonte: administrativo@belgrani.com",
    "emails": [
      "administrativo@belgrani.com"
    ],
    "phones": [
      "219678190"
    ]
  },
  {
    "key": "carbobasalt",
    "nome": "CarboBasalt",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@carbobasalt-composites.pt",
    "telefone": "218275903",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TETOS FALSOS E DIVISÓRIAS; linha: 8; nome na fonte: CarboBasalt\nAtividade: Painéis em sanduíche\nLocalidade/morada: Rua do Centro Empresarial Bloco A Lote 13, Sintra\nContactos na fonte: 218275903\nEmails na fonte: geral@carbobasalt-composites.pt",
    "emails": [
      "geral@carbobasalt-composites.pt"
    ],
    "phones": [
      "218275903"
    ]
  },
  {
    "key": "alfredocosteira",
    "nome": "Alfredo Costeira",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "920425804",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TELHADOS; linha: 5; nome na fonte: Alfredo Costeira\nAtividade: Telhados\nContactos na fonte: 920 425 804",
    "emails": [],
    "phones": [
      "920425804"
    ]
  },
  {
    "key": "xicoflecha",
    "nome": "Xico Flecha",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "966152077",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TELHADOS; linha: 8; nome na fonte: Xico Flecha\nAtividade: Telhados, pedreiro\nContactos na fonte: 966 152 077",
    "emails": [],
    "phones": [
      "966152077"
    ]
  },
  {
    "key": "fabioemotelha",
    "nome": "Fabio Emotelha",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": null,
    "telefone": "912072970",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TIJOLO, LADRILHO E REBOCO; linha: 7; nome na fonte: Fabio Emotelha\nAtividade: Equipa de Tijolo\nContactos na fonte: 912072970",
    "emails": [],
    "phones": [
      "912072970"
    ]
  },
  {
    "key": "magjacol",
    "nome": "MAGJACOL",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "comercial3@magjacol.pt",
    "telefone": "212362137 / 937718027",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TINTAS; linha: 5; nome na fonte: MAGJACOL\nAtividade: Tintas aquosas\nContactos na fonte: 212 362 137 937 718 027\nEmails na fonte: comercial3@magjacol.pt\nObservações da fonte: Sr. Bruno Baiona",
    "emails": [
      "comercial3@magjacol.pt"
    ],
    "phones": [
      "212362137",
      "937718027"
    ]
  },
  {
    "key": "marmoreis",
    "nome": "MARMOREIS",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@marmoreis.com",
    "telefone": "249521734 / 917263235",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TRABALHO DECORATIVO; linha: 5; nome na fonte: MARMOREIS\nAtividade: Trabalhos decorativos\nLocalidade/morada: Rua da Lagoa, N. Srª das Misericórdias Bairro Ourém\nContactos na fonte: 249 521 734 917 263 235\nEmails na fonte: geral@marmoreis.com\nObservações da fonte: www.marmoreis.com",
    "emails": [
      "geral@marmoreis.com"
    ],
    "phones": [
      "249521734",
      "917263235"
    ]
  },
  {
    "key": "rotaspropostasunipessoallda",
    "nome": "ROTAS PROPOSTAS, UNIPESSOAL, LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "rotaspropostas.unipessoal@gmail.com",
    "telefone": "930413248",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: TRANSPORTE DE MERCADORIAS; linha: 5; nome na fonte: ROTAS PROPOSTAS, UNIPESSOAL, LDA\nAtividade: Transportes de mercadorias\nLocalidade/morada: Arruda dos Vinhos\nContactos na fonte: 930413248\nEmails na fonte: rotaspropostas.unipessoal@gmail.com\nObservações da fonte: Sr. Ricardo Azevedo",
    "emails": [
      "rotaspropostas.unipessoal@gmail.com"
    ],
    "phones": [
      "930413248"
    ]
  },
  {
    "key": "infracercalda",
    "nome": "INFRACERCA, LDA",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@infracerca.pt",
    "telefone": "289148524",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: VEDAÇÕES; linha: 6; nome na fonte: INFRACERCA, LDA\nAtividade: Infraestruturas de Madeira e Vedações\nLocalidade/morada: Quarteira\nContactos na fonte: 289148524\nEmails na fonte: geral@infracerca.pt",
    "emails": [
      "geral@infracerca.pt"
    ],
    "phones": [
      "289148524"
    ]
  },
  {
    "key": "videtra",
    "nome": "Videtra",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "videtra.jorgeneves@sapo.pt",
    "telefone": "912559051",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: VIDROS E ESPELHOS; linha: 6; nome na fonte: Videtra\nAtividade: Vidros\nLocalidade/morada: Sintra\nContactos na fonte: 91 255 90 51\nEmails na fonte: videtra.jorgeneves@sapo.pt\nObservações da fonte: Jorge Neves",
    "emails": [
      "videtra.jorgeneves@sapo.pt"
    ],
    "phones": [
      "912559051"
    ]
  },
  {
    "key": "polivitrium",
    "nome": "Polivitrium",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@polivitrium.com",
    "telefone": "219225400",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: VIDROS E ESPELHOS; linha: 8; nome na fonte: Polivitrium\nAtividade: Comércio e montagem de vidros\nLocalidade/morada: Mem Martins\nContactos na fonte: 219225400\nEmails na fonte: geral@polivitrium.com",
    "emails": [
      "geral@polivitrium.com"
    ],
    "phones": [
      "219225400"
    ]
  },
  {
    "key": "vidrofornense",
    "nome": "Vidrofornense",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "geral@vidrofornense.pt",
    "telefone": "219242000",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: VIDROS E ESPELHOS; linha: 9; nome na fonte: Vidrofornense\nAtividade: Transformação e comércio de vidros\nLocalidade/morada: Sintra\nContactos na fonte: 219242000\nEmails na fonte: geral@vidrofornense.pt",
    "emails": [
      "geral@vidrofornense.pt"
    ],
    "phones": [
      "219242000"
    ]
  },
  {
    "key": "vidromax",
    "nome": "Vidromax",
    "acao": "novo",
    "alvo": null,
    "alvo_nome": null,
    "email": "vidromax@vidromax.pt",
    "telefone": "231947500",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: VIDROS E ESPELHOS; linha: 10; nome na fonte: Vidromax\nAtividade: Vidro plano\nLocalidade/morada: Mealhada\nContactos na fonte: 231947500\nEmails na fonte: vidromax@vidromax.pt",
    "emails": [
      "vidromax@vidromax.pt"
    ],
    "phones": [
      "231947500"
    ]
  },
  {
    "key": "centividro",
    "nome": "Centividro",
    "acao": "existente",
    "alvo": "57b877b0-8927-45f1-8209-eef2f565ed98",
    "alvo_nome": "Centividro Unipessoal, Lda",
    "email": "centividro@gmail.com",
    "telefone": "962095754 / 219137766",
    "notas": "[Fonte Excel bfef7e7a88189bee — dados históricos a confirmar]\nFolha: VIDROS E ESPELHOS; linha: 13; nome na fonte: Centividro\nAtividade: Fornecimento e montagem de vidros\nLocalidade/morada: Cacém\nContactos na fonte: 962 095 754 219 137 766\nEmails na fonte: centividro@gmail.com\nObservações da fonte: D. Marlene",
    "emails": [
      "centividro@gmail.com"
    ],
    "phones": [
      "962095754",
      "219137766"
    ]
  }
]
$fornecedores_fonte$::jsonb) as s(key text,nome text,acao text,alvo uuid,alvo_nome text,email text,telefone text,notas text,emails text[],phones text[]);
create temp table _forn_snapshot on commit drop as
select * from jsonb_to_recordset($fornecedores_snapshot$[{"id":"2409b10a-d210-405f-87f1-dee41d4fde68","nome":"3SJ Construções"},{"id":"e90d2573-5948-49d6-8631-93fe5d4a7087","nome":"A Cimenteira do Louro, S.A"},{"id":"5f2f011a-9d41-456e-9014-e88c6469f2e1","nome":"A Físico Piscinas (Antonio Augusto Fisico Lourenço)"},{"id":"e35958d0-8d37-43f3-bfb2-d1360df5f782","nome":"A. & A. M. Vicente - Canalizações, Lda"},{"id":"8ff5945c-b69d-4196-8a5b-f974c98139b2","nome":"A. Pinto & Marques, Lda"},{"id":"3d2ec73e-bd42-4080-b35d-19cf666b9588","nome":"A. Reis & J. Lopes, Lda"},{"id":"de7da5f7-f62e-484a-ba54-0c9a8a564646","nome":"A. Sousa Alves - Revestimentos de Zinco e Cobre Lda"},{"id":"5ccdea1a-cecc-4098-a5ba-0bddbc4057fc","nome":"A.J. Navalho, Lda"},{"id":"86493d47-cdf0-4218-b69b-8e4155005923","nome":"a.j.silva bento, lda"},{"id":"df195cb5-9950-4745-946b-634722c44002","nome":"Absoluthome"},{"id":"65c370bb-d384-4941-8e88-0ff4947c31c7","nome":"Acriglobal Acrílicos, Lda"},{"id":"5d28cae3-e2b2-4843-8de6-b045cffc5e12","nome":"Adn - Aquarium Design Lda"},{"id":"4d761786-28f2-413a-951b-8b4d9f07f07e","nome":"Adulai Embalo"},{"id":"db0c8d6d-6124-4220-b449-2d1d8320d080","nome":"AEG"},{"id":"95e12ff1-c735-4430-9017-456634b728b8","nome":"AGA - Mat. Const. Jardinagem"},{"id":"deac3309-9214-480d-82f2-0fbb4d993cd6","nome":"Aglomadeiras do Estoril, Lda"},{"id":"cd4feb24-9af6-4b41-9403-104ab5335d13","nome":"Aires Fernandes de Almeida, Lda"},{"id":"25784d7a-35c1-4c2c-9e9f-18be2fa1815d","nome":"Airoferragens, Lda"},{"id":"f90e6a5c-f315-4be3-8b3e-9db57eaf7506","nome":"Aki Cascais"},{"id":"b83ff75e-040d-4563-a65a-f9fa476bcf5a","nome":"Akv Lda"},{"id":"8403627b-90f3-48e9-bd37-1ae21b0a6682","nome":"Alaire Living"},{"id":"60a66973-da93-41ad-9c26-095b467c58f1","nome":"Alarmoeste - Sistemas Electrónicos Lda"},{"id":"ab066951-5d0e-40b4-a0f1-28b4c0381c97","nome":"ALDI"},{"id":"f935c62d-c25a-4723-9898-450b17a3dc8a","nome":"Alfilux"},{"id":"926ea0cb-5557-431b-a58f-ffe0b4726bf4","nome":"Algarlixo Gestão Adm. Residuos Lda"},{"id":"51183ab0-4623-4470-abe3-be0c93871f6c","nome":"Algarsilva - Comércio de Equipamentos Agrícolas Lda"},{"id":"1856d79d-e206-4424-bf3b-794511c984c0","nome":"Algo Moderno Unip., Lda"},{"id":"76cf7db3-7aee-438c-9a97-481e63556ca5","nome":"Alicerce Peculiar Unip., Lda"},{"id":"3ae1af9d-c27a-4022-901b-b387ae08ce23","nome":"Allmat - Álvaro Covelo & Pinto, Lda"},{"id":"2db856d6-1eeb-4ecf-9809-10353093c74a","nome":"Almabarão"},{"id":"2b62022e-a07d-4c95-9bd9-ea2fdece18f7","nome":"Almacla"},{"id":"67f68177-1353-4c1a-a120-35a35c7bbdcd","nome":"Altamiro & Batista - Construções, Lda"},{"id":"b266a738-f768-4109-a7fa-14f48372c151","nome":"Altamiro Gomes Oliveira"},{"id":"e57cb547-ecb6-47d0-bd10-77470c23fc2e","nome":"Alumais - Ind"},{"id":"c81b310e-118e-4a6c-a994-869f3d60cdc9","nome":"Alumais, Lda"},{"id":"a5375468-6dc7-4b9f-a199-bfec0f2aa339","nome":"Alumínios Cortizo (Portugal) Lda"},{"id":"16b2e8bb-26fb-4542-a38b-b1dc840fef45","nome":"Alunik (World System Aluminium) - Alumínios Lda"},{"id":"9062ef0f-bfd2-458b-892f-ec56f28ae8d4","nome":"ALUSTORIL"},{"id":"330dfc91-d050-4566-bda2-07178b583fac","nome":"Álvaro Covelo & Pinto, Lda"},{"id":"1e3c15f8-94a3-4a50-899e-0327440ca82c","nome":"Álvaro Figueiredo & Filhos, Lda"},{"id":"a5b8c841-e282-4423-8a4f-2c20d4330682","nome":"Alvestone, Lda"},{"id":"3ffe6a86-e3bb-4093-8247-65f8b83fe2aa","nome":"Alviga, Lda"},{"id":"c55a825b-e736-491b-b9c6-b0d6d05a0ef8","nome":"Alysson Diego Gonçalves Magalhães"},{"id":"91f0c960-0d7d-4818-9c66-1f51134f9f5f","nome":"amazon (China)"},{"id":"f33ad595-0c58-497e-898a-b784321f6e0e","nome":"amazon (Haomei)"},{"id":"5ae2b06c-9c2f-4b19-975e-718d555cb93e","nome":"amazon (Minglang)"},{"id":"b71468d4-ff49-4e2d-8456-d7c0dfeb081b","nome":"Amazon.de"},{"id":"84497d8d-746e-4bd8-a05f-9e94e14bf761","nome":"AMFG, Unip - Lda"},{"id":"a3f9bda0-3759-4f97-b3d0-03502b22b1d7","nome":"Amigos do Lar Construções Lda"},{"id":"cd8c97e9-7779-4f1a-956f-3fc28c452951","nome":"Andaluga - Aluguer De Andaimes E Máquinas Para A Construção, Lda"},{"id":"8705022e-202a-4485-9e41-bb5d75693647","nome":"ANDARAJARDINS Unip, Lda"},{"id":"7589a89c-1f6a-49c4-87cd-08f02ee97d97","nome":"Ângulopigmentado Soluções Const. Unip., Lda"},{"id":"f92fd2fa-1bd1-471b-b908-fb311d6501f1","nome":"Ângulopigmentado Soluções de Construção Unipessoal Lda"},{"id":"1c8cd497-9e31-4ae5-b9a3-dcf3a02e00d7","nome":"Anicolor - Aluminios Lda"},{"id":"61304a10-7951-47e5-873e-9352d58c8eff","nome":"António Anacleto"},{"id":"b62cc3b6-661e-4137-bb68-56c8842e3455","nome":"Antonio Augusto Fisico Lourenço"},{"id":"7948e6a1-e6e9-4483-ba08-cfbfe19fe8e3","nome":"António Coimbra das Neves, Lda"},{"id":"70333ff2-360c-4799-b6c5-10003c041164","nome":"António e Lopes Mat. Const., Lda"},{"id":"40aaeb3a-5fbd-4ac0-af1b-ffbcb175f3de","nome":"Antonio Manuel Ferreira Gomes, Unipessoal, Lda"},{"id":"12c935b6-1abd-42a8-b885-3f064298df65","nome":"António Marques & Gomes Lda"},{"id":"a626621d-52ab-44e3-8360-c4dbfa57bb91","nome":"Aquamatic, SA"},{"id":"28faa28a-29a8-4aa2-a0c3-82de4b819a11","nome":"Arestalfer, S.A"},{"id":"87ffd900-f957-4314-81a7-b9d6b14e1565","nome":"Aristides Tete Unipessoal, Lda"},{"id":"4fb03a2e-b94f-4f57-9d87-6492cfa481b8","nome":"Aristides Tete Unipessoal, Lda (Calçada)"},{"id":"1563f602-21dd-4840-80e5-468a486455ed","nome":"ARMASUL"},{"id":"f81f55d8-0f0d-41f5-a79a-861a0798628f","nome":"Arménio Ramos, Unipessoal Lda"},{"id":"f7ab1040-9fe2-44f5-b168-df46822e08e2","nome":"Armindo & Coelho, Lda"},{"id":"eeb9ca20-3c4e-4b32-b7cd-841c8e92c21d","nome":"ARO e FD"},{"id":"b9082bfe-79c2-4e3d-80e8-fdceaa070f26","nome":"Artes e Fogo - Indústria de Cerâmica, Lda"},{"id":"4f4213b5-2994-4984-8044-a729016cee5b","nome":"Aspilusa Portugal, Lda"},{"id":"e7a5883b-eb9f-4010-a76e-7210295e51fc","nome":"Aspinrev, S.A"},{"id":"6b4e66f6-ea8d-457e-93f5-e2335376a17b","nome":"Aspirvacum - Asiração central unipessoal Lda"},{"id":"83370c71-404e-41fa-89b4-5d2df388fc2a","nome":"Astrasul - Construção Civil e Tratamento de Água Lda"},{"id":"b9dc82b3-93d1-491a-a09e-615fe1d4fd4d","nome":"Attackgás, Lda"},{"id":"090631e0-c4c4-41a8-9a42-1f5c895cb864","nome":"AUCHAN"},{"id":"e8ba1937-8546-4419-b411-01a9d98bd31c","nome":"Axerclima Equipamentos De Energia E Gás, Lda"},{"id":"5c19756b-24c9-4e78-b9b4-9985f85c4a63","nome":"Azulcomum, Lda"},{"id":"d291785b-7fbd-4274-9473-463ca528bb90","nome":"Bacofra (Gonçalo Batalha, Unipessoal Lda)"},{"id":"09e8cbb9-92b5-49e9-af3a-09c1aec3dcbb","nome":"Balcof - Cofragens e Constuções, Lda"},{"id":"faa03f9d-a568-4deb-acc6-c9e0f375f943","nome":"Balneo (Leroy Merlin)"},{"id":"981cd839-314a-4b03-9e64-ab5e3b3db443","nome":"Baltazar"},{"id":"9e3fe910-b78c-4f10-a6c2-47e5cf7a1c17","nome":"Banoideo (Gruparsa Digital SL)"},{"id":"4330af71-4dbd-413d-8cac-367325a0cb9d","nome":"Barreirinhas - Artefactos Em Cimento Lda"},{"id":"d6e19656-4bcd-4d4f-9aa7-3e514787ee0d","nome":"Battistuta Caetano, Lda - Moss n Art"},{"id":"d01247d1-602e-4fdf-ad4b-35ee53003fe2","nome":"Baukonzept - Soluções Técnicas Para Construção, Lda"},{"id":"25867d3a-3b83-4fd5-b13e-214a8bcb8c43","nome":"BCM Bricolage S.A."},{"id":"0d9da558-889c-4140-a814-6331ae535b44","nome":"Beef Eater"},{"id":"9b0fad9f-6950-4339-aeec-974ce80d3f20","nome":"Belgrani Lda"},{"id":"14902e2b-439f-4b1c-bea5-ea3f11328415","nome":"Beringela-Sociedade Unipessoal, Lda"},{"id":"fc729493-a9e8-4137-a230-3abd4a485db3","nome":"Beringela, Lda"},{"id":"323de70e-49a2-4c48-a2e8-db1dac725202","nome":"Berner"},{"id":"59e71db3-4bc7-47f7-8a6b-72f4b326207b","nome":"BERNSTEIN"},{"id":"f0c7d490-9f08-4ee0-99bf-4c62c42abace","nome":"Betão Liz S.A"},{"id":"b764997e-8e31-49b8-9d3b-7094d9c58eb4","nome":"Biciway, Lda"},{"id":"652dc3af-96de-40fa-83da-781cd59c236e","nome":"Boomerangmágico Unipessoal, Lda"},{"id":"109bcabe-dd3a-424b-958d-d815a481b674","nome":"BP"},{"id":"f4147b03-d0be-4581-85d7-f08548ec16b6","nome":"Brico Butikk"},{"id":"f770fd72-27c9-452c-8151-7863241a040d","nome":"Brico Depôt"},{"id":"10c7817a-59b2-44bb-af8a-25642371a936","nome":"BricoMarché"},{"id":"41bedeac-076c-4f5b-a69f-de72c8872563","nome":"Bricovitor / Tecnidom, Lda"},{"id":"e8e10af9-e0da-47ec-ab25-146f04e4c677","nome":"Brilhoeste - Serv. De Limpeza, Lda"},{"id":"c8adec27-f369-4a0f-a828-7fa5d1aac890","nome":"Brisa Colorida - Construção Civil, Lda"},{"id":"03fed68c-0d3d-400b-a570-362d78b385bd","nome":"BruciMac"},{"id":"9630efd9-4f2d-4173-921e-6a07ac940fa5","nome":"Bruno Serra"},{"id":"d0b05b1d-8049-4fdc-bac9-a7728980377c","nome":"CAIXIAVE, SA"},{"id":"8d7841a4-3bd2-4252-b1bc-331f8a424cad","nome":"Canalizassist Canalização, Unipessoal Lda"},{"id":"7f99e3a2-081d-4e51-bd73-ddb8073d4f74","nome":"Cantarias (valores Orçamento da PL)"},{"id":"99b79d9d-0545-4d6e-8ee3-437c1735ad8a","nome":"Carlos Alberto dos Reis Silva Cruz"},{"id":"671cb0fa-88c7-400c-9ad4-eb5795661617","nome":"Carlos Manuel Espada Eufemia"},{"id":"1ff3c587-bbec-4bf1-b8ca-4ae13a2156e1","nome":"Carpincasais - Sociedade Técnica de Carpintarias S.A"},{"id":"b4f7bd21-29e8-4b27-b94e-aa2eb3d525af","nome":"Carpintaria - Antonio Manuel"},{"id":"ee4843fc-5b59-4508-994f-6aa63f4c8b0a","nome":"Carriço & Filhos 2, Lda"},{"id":"8dc78499-00e7-4b85-9a94-d240ba177910","nome":"Cartório Notarial de Francisca Castro"},{"id":"5eebfe13-636e-4aab-aedd-f65eb76c3dc3","nome":"Carvalho & Afonso"},{"id":"f5bb77ca-9578-4c8a-8829-fe532a554c00","nome":"Carvalho & Maia, Lda"},{"id":"9b125e44-75bf-416f-9f16-6e6b951ee612","nome":"Carvalho, Batista, Lda"},{"id":"56a29748-e948-4059-9789-8b9a29888c26","nome":"Casa Carvalho"},{"id":"29fa3024-869b-4939-adfe-194ea1700dfe","nome":"Castanresin - Comercialização de Produtos Químicos Para A Construção Lda"},{"id":"725bcf26-e089-4e25-a921-7d8bcc4f3e50","nome":"Catarina Silva"},{"id":"a71eb2d6-a7e9-4d61-a6ff-d3cf6fcb5e91","nome":"Catia Raquel Neves dos Santos Gonçalves"},{"id":"c6d67d95-d94d-486f-a84a-029885aa37ca","nome":"Celson Lourenço Espindola, Unip,"},{"id":"57b877b0-8927-45f1-8209-eef2f565ed98","nome":"Centividro Unipessoal, Lda"},{"id":"f95db46a-5dd1-4bcc-99ed-ae69d9c94e34","nome":"Central Serralharia Lda"},{"id":"1140b7a5-a284-4dfd-bb52-3f0c6255709a","nome":"CesarINOX"},{"id":"d4e1669c-c1a3-494e-bfa7-59cd701f48fe","nome":"Chagas, SA"},{"id":"8108df80-31d8-424e-92f9-a2f4d3aa4b8b","nome":"Cimpaurb. Lda"},{"id":"c433290f-7e62-4adb-94c8-01971db9f0d9","nome":"CIN, SA"},{"id":"a384fb7a-a602-4c1e-ab7d-94fd9133dd84","nome":"Cintrafer"},{"id":"71ab8c1d-78a5-4e49-afc6-6dd2e79fdf64","nome":"Cipriano & Antunes, Sa"},{"id":"29d02ce8-7ec0-4999-8cc1-668fb555bda6","nome":"CITAC"},{"id":"84cc6316-aa0a-4c4e-a4d0-89ff5afb61eb","nome":"Climacer, S.A"},{"id":"92593778-5439-4a01-844d-a01fa8d2dabd","nome":"Climobra - Instalações Técnicas Especiais, S.A"},{"id":"b2e1a335-d1cf-456c-989b-ae627adb50a8","nome":"CMC Extintores, Lda"},{"id":"5a24a2bc-bb25-4af1-b323-b20349c47e1f","nome":"Cobercam - Revestimentos de Coberturas, Unipessoal Lda"},{"id":"4031662f-04a6-485c-8ffe-8ee76b862e23","nome":"Coberfuzi - Coberturas e Funilarias Zinco, Lda"},{"id":"2da63519-0665-46d1-972b-0076400e3861","nome":"Coframax, Lda"},{"id":"f1073df6-7a29-4728-9df7-f9f6299ec500","nome":"Combustop, Lda (BP)"},{"id":"9315f771-3548-4d7c-a0fc-b6d6026cf148","nome":"Confrasilvas - Construções, S.A"},{"id":"5d000c91-e108-4014-a306-45762475ddb8","nome":"Construterm ( Marguifaz - Construção Civil, Lda )"},{"id":"1c098906-57ea-4387-8fab-4e25f1d830d9","nome":"Construtora de Nafarros Lda"},{"id":"544e5d09-f716-4d1f-b09b-e9312f806926","nome":"CONTINENTE"},{"id":"32e8f0ac-8312-46d8-a568-5f840778aa49","nome":"Continsol - Comércio de Tintas Costa do Sol"},{"id":"80f7bfa3-a15a-41c0-9268-64c9d9e02bf5","nome":"ControlPortas"},{"id":"b3709356-4b5b-4fc5-9eff-3850dc7acd49","nome":"Controsol - Controlo Solar e Decoração Lda"},{"id":"a518f978-fb5f-4ac8-b555-945293de54e6","nome":"Coriasensation, Lda"},{"id":"11c37937-5f2c-41e2-bc08-574f62829656","nome":"Costa Azul - Construções e Instalações Especiais, Sociedade Unipessoal Lda"},{"id":"696daae1-9b0f-423d-9734-49ac62896ded","nome":"Criacrilicos - Indústria Mobiliário e Decoração Lda"},{"id":"db20890f-7a14-456c-ba65-94861111f50c","nome":"Cristalmax - Indústria de Vidros, S.A"},{"id":"558864e3-2da2-458b-a999-dd782bd0d76b","nome":"Cristina Siopa, Lda"},{"id":"99f1fdfe-cbfa-46ce-acdf-579a058e4db3","nome":"CRNT - Manutenção Total, Lda"},{"id":"eb7a4f96-208e-4bd8-a74a-08d1a25fdb82","nome":"CRUZFER"},{"id":"02f23dd8-dfac-4bfc-9718-510eb59a367b","nome":"Cruzfer-Representações, Materiais e Ferragens Lda"},{"id":"008c8997-2b00-4494-ae01-6bda6ac0709c","nome":"CT Painting"},{"id":"5e1f8e46-5525-43d9-9b4b-05c544c726e2","nome":"Custódio Fernandes - Construções, SA"},{"id":"1bb8b296-0c6c-4ed8-ad31-c93b27782d3c","nome":"D & D, Lda"},{"id":"da8342b4-a49d-4809-9acd-5ba36728ea57","nome":"D. Fernanda Coelho"},{"id":"8269ebca-079f-4334-99f8-462e8df9f7f2","nome":"Daportas Automaticas Lda"},{"id":"c9935225-897f-45b4-ab6c-b61fdb9c9900","nome":"Davide & Filhos, Lda"},{"id":"746ee312-7a2c-427d-a1c8-2924f548bdbe","nome":"Decathlon"},{"id":"97d6e775-fa05-43ac-a82e-5ece01f2acc0","nome":"Decathlon Sintra"},{"id":"ddeacd9e-5c1a-4f89-ad10-a2c41416f577","nome":"Decoresse - Decoração de Interiores, Unipessoal Lda"},{"id":"e7be593d-a63e-45eb-9818-59aac33ec2a4","nome":"Decorpita - Materiais de Construção, Sa"},{"id":"652d6937-cf4f-4cde-8a8a-6e9d8e1d60bf","nome":"Decorpita/Mantovani"},{"id":"16ec826b-6ff7-4188-a7a5-7a267c904fc8","nome":"Definelight"},{"id":"342eff7f-47ac-46a9-b410-6eb819b59f56","nome":"Delarobia, Lda"},{"id":"d42f3ff2-4120-4a13-acf2-34b93231ed8c","nome":"Desafio Ótimo, Lda"},{"id":"38181ce4-8514-4da1-a6cc-709fa30caf5c","nome":"DHE - Eletrodomésticos, Lda"},{"id":"630e7abb-660b-4d09-a7b4-2a40b7215a74","nome":"Dia Portugal Supermercados"},{"id":"542cd90d-5d8e-4c09-a2a6-730cea205dd5","nome":"Diálogo Celestial, Lda (Altamiro)"},{"id":"a7f26ccf-053c-4990-b84e-e5b06bb0c4b6","nome":"Diasen Iberica, Lda"},{"id":"c9428e5a-7cd9-47e0-98e4-88ee28a9eeb4","nome":"Dierre Ibérica - Indústria de Portas, S.A"},{"id":"71c46903-5db2-4502-a73a-e9dbf36034d8","nome":"Dina Martins & Paulo-Comércio"},{"id":"685923c1-3067-4fb7-841b-168514edff35","nome":"Domingos Diniz & Filhos, LDA"},{"id":"7aae785a-e48a-47d4-a023-29f484ae89c7","nome":"Domintegra, Lda"},{"id":"2399862e-863a-4a7a-bda3-cdaa38385751","nome":"Domusfirme - Soluções de Segurança Lda"},{"id":"c610c02e-9360-4857-a465-f45934f6ace7","nome":"Drogaria Cajoar, Lda"},{"id":"6881ee1d-b010-47e0-8249-3d62b928e04b","nome":"Drogaria Costa, Lda"},{"id":"1c7016e9-cff8-455d-ac7a-9b360552bf86","nome":"Drogaria Rodrigues"},{"id":"09e76862-d09d-48b6-84ff-b31b353c57dc","nome":"Drogas e Ferragens, Lda"},{"id":"f3b2ffe2-d169-4d08-b13f-6c89b089a94b","nome":"Duarte & Vieira Lda"},{"id":"06890498-80e8-460d-a482-1a1d1679e08c","nome":"Dumitru Reaboi"},{"id":"82945c95-116d-4f12-a07b-7f870b4b5710","nome":"DuoService"},{"id":"9b05d17d-2d86-4605-9543-1a17324e5799","nome":"Duvibri"},{"id":"fe0190bc-72a6-4588-8b90-267a705fbf3c","nome":"DYD - Desentup. e Desinf., Lda"},{"id":"c9738559-5f88-41af-be56-936601f7dd9f","nome":"Ebe Indústria, Lda"},{"id":"6699ee70-49d3-453a-9a4b-1ece333c1168","nome":"Eben - Mobiliário Por Medida, Lda"},{"id":"d95bd5b2-b2f4-4ace-9940-49e84581e8c6","nome":"Ecodepur"},{"id":"2b22c88d-2ab3-405b-8b74-79f98de52a7f","nome":"Ecoplace Lda"},{"id":"7a3394ae-7c44-4aca-afb3-0c1067a1eb6f","nome":"Ecoreflexus, Lda"},{"id":"8a65fca6-1fa5-4f8b-ac30-48c63378dc31","nome":"EcoReform"},{"id":"cf110988-7751-48db-a92f-91561fb9e718","nome":"Ecosteel, SA"},{"id":"2b5bec53-efb9-416f-bf02-3cdbb17d6ba1","nome":"Eduardo Costa"},{"id":"dd406b2b-5803-42aa-b89e-312bb36ca438","nome":"Eduardo Frade Wallcovering, Unip"},{"id":"bbea8078-722f-413a-ba0c-c47c55ae2a8b","nome":"EfectoLed"},{"id":"509ae05a-f93b-43e2-9f4f-474f47259d0d","nome":"Effusive Spirit, Lda"},{"id":"03f37aaf-ea64-4866-aad0-9a07e6b2cb4f","nome":"Electro - Marcus Lda"},{"id":"61681c9b-0df8-4796-a002-c0aaedfceb37","nome":"Electro - Sacavém  de António A. Maio, Lda"},{"id":"d3f77396-a2a4-4c7a-9ccb-237a2d4cad3a","nome":"Electrosacavém"},{"id":"0b8a8748-4d11-4142-953a-21885bc5da8e","nome":"Elizabeth Carezia de Gouveia, Unipessoal Lda"},{"id":"5346cdc7-5f3b-4f82-8840-9f62f9adf8f7","nome":"Empowerment Express Unipessoal Lda"},{"id":"cef559a4-9514-4af0-832b-27f202affc4a","nome":"Eneraqua - Gestão Água e Energia"},{"id":"a9192855-5188-40c8-94bf-2cce46167a65","nome":"Engimat - Engª e Construção, Lda"},{"id":"e190ab6c-54d6-4f09-b836-1eb2323252bb","nome":"Equipa de Aluguer"},{"id":"1ef39495-20a4-44dc-b0ca-dc9589e03cf7","nome":"Esfera Cristalizada, Lda"},{"id":"d7058549-9b4a-459f-8b8b-4b6e0c3dc8f9","nome":"Esferovite"},{"id":"a2e4b904-e049-4aa1-bd9a-9d42291b0ca4","nome":"Espaço Vidro - Com. Ind. Vidros e Espelhos, Lda"},{"id":"0d777327-6673-4a68-ba2f-f624fe73241b","nome":"Espaço Vidro, Lda"},{"id":"8690322f-1fd0-4e33-81da-3cd33e5e7e4b","nome":"Estores"},{"id":"1feccb99-a347-468d-891e-8d989b975d83","nome":"Etopi"},{"id":"34b34da1-5928-49a5-82ab-0d4c9febf243","nome":"Eugénio das Neves, Lda"},{"id":"ed3322f7-fe6e-41af-833a-64e421bfa8f1","nome":"EuroBuild"},{"id":"31b2e495-04bc-4082-b8a5-f2e62f76256c","nome":"EVAG - Materiais de construção"},{"id":"398393db-efee-403d-97aa-fbbed0fc20b7","nome":"EVCC - Electric Vehicle C.C., Lda"},{"id":"d8cee55e-aa60-4aa2-acd1-b809ca0d80e9","nome":"F. & J. Lotra - Montagem e Caixilharia Em Alumínio Lda"},{"id":"bc249e64-db8b-4982-b9b6-55604ca94d55","nome":"F.C. Sousa, Lda"},{"id":"6dd08a5a-5ef8-44ee-ba25-f9c6bc10edc4","nome":"F2J, Lda"},{"id":"b43773a7-31c6-44f1-9aa4-667d5ff38e48","nome":"Fábrica de Tintas 2000, SA"},{"id":"0efd688b-8212-465a-aae7-3e32923ad9d6","nome":"Farmácia da Beloura"},{"id":"b063edf7-927b-4c3a-be20-30654111a99d","nome":"Farmacia Silveira Alcoitão"},{"id":"639cce07-3074-41f7-96c6-96f5fc321caf","nome":"Farmacia Silveira Birre"},{"id":"b18eb3ef-fdee-4f67-841d-98314b887028","nome":"Ferbroca, Lda"},{"id":"1f958617-1fb9-4171-a36d-b60077a97e25","nome":"Ferca, SA"},{"id":"982ee2a0-ad5b-463f-8c0f-1b28dff4107a","nome":"Ferlito, SA"},{"id":"c3df32dd-f378-438e-a81c-445cecc23602","nome":"Ferragens Drogaria Torre, Lda"},{"id":"518ac2ef-6b82-4ad5-8ef8-dcba7411165e","nome":"Ferragens e Drogaria Alcaide, Lda"},{"id":"2628ddea-104c-43a1-ab8c-80d7f297b812","nome":"Ferreira & Almeida, Lda"},{"id":"a205d671-8b85-41e9-bb95-b44919dd1ebd","nome":"Ferro Aços Laranjeira. Almeida. Lda"},{"id":"5cb9b4a2-1c6d-4753-b5db-8a94672ef635","nome":"Fibrosom Industria, Lda"},{"id":"97df2b0c-6bf8-45ff-8d55-665e891efd61","nome":"FioCerto Unipessoal, Lda"},{"id":"50b44dd8-6d51-408b-91ad-4848f89f2c76","nome":"Fischer Mobel GmbH"},{"id":"12ad77bf-dfff-4eae-bb44-ccc1d31d6aee","nome":"Fixol, Lda"},{"id":"42c5b811-630a-426f-b341-8091e5cdd227","nome":"Flexipiso - Pavimentos Lda"},{"id":"628b37ae-0e12-46da-8afe-f44fab998615","nome":"Flexiportas, Lda"},{"id":"46f7a822-ef7e-4a3f-92b0-69ecbf6c2c50","nome":"Fluxion, Unipessoal Lda"},{"id":"30dac092-cf7d-4264-ac89-b59f0847e45c","nome":"Fonteval - Sistema de filtragem de água, Lda"},{"id":"bb01e180-b91f-483c-ba21-e256333dc3ea","nome":"FPM-Madeiras, Pavimentos e Componentes"},{"id":"f06c349f-86b9-4505-9a82-b2c2864b905a","nome":"Francisco Bernardo"},{"id":"f8d030bc-2f68-47ec-9a55-cadc2212291f","nome":"Francisco J.P. Mendes, Unip., Lda"},{"id":"cc215143-d912-4f4c-97eb-e618d6f408d9","nome":"Frazoaluminios - Comercio e Montagem de Caixilharias Em Aluminio Lda"},{"id":"768ce41e-6924-4613-a018-aaf2e823fe76","nome":"Frostline - Climatização e Refrigeração Lda"},{"id":"2349257d-732e-42b7-8146-678c6199a1a6","nome":"FUTURLUZ"},{"id":"7315052f-f573-4956-8672-641ef747a962","nome":"Garden Props, Lda"},{"id":"e6b26e42-a658-4425-9026-cbf5bbe71b01","nome":"GÁS"},{"id":"6a9c914b-dee9-48bc-a32a-be4f1e493274","nome":"Geo-Patente, Lda"},{"id":"5f1c8f13-e06a-4a2b-a5a5-8276a29f49cf","nome":"Geotérmica – Sociedade de Instalações Térmicas, Lda"},{"id":"1cb38fbc-0312-4c65-a663-27584b113a1e","nome":"Gift and everyday supermarkt"},{"id":"45cbabbf-555d-4997-85b2-2be14b529f62","nome":"Gilson Fernandes, Lda"},{"id":"811bd8d1-da79-4ea5-b276-1d60ed3d6b56","nome":"Gilson Santos Fernandes"},{"id":"00df7ac5-76cf-45f6-98e0-2c9a874c61c8","nome":"Gimmersta"},{"id":"dd07dffb-5541-4dea-b3a9-be8031a12a84","nome":"GlobalPav - Pavimentos e construção Lda"},{"id":"2aa0164e-d585-4ac3-9ea1-0256f45afdae","nome":"GLP Iberica Unipessoal, Lda"},{"id":"fcd83fb0-0f30-4a71-ab2f-a1cf66eac4e0","nome":"Goritmo - Tecnologias, Unipessoal, Lda"},{"id":"e931eabf-7c7e-4059-bf1b-e710c6c555b6","nome":"Gotflow, S.A"},{"id":"4b010494-60e8-482c-ad9f-c4ae5d5b9fa1","nome":"Greendreams"},{"id":"40dfdb30-b89a-469e-a23b-194e7ace48f3","nome":"Greenice (Leroy Merlin)"},{"id":"b873250a-d043-41d4-827b-a290ff358262","nome":"Greenpark"},{"id":"7da31bdb-a484-448c-87c4-419571d132f0","nome":"Grow Forever - Unipessoal, Lda"},{"id":"40d5f2e4-083b-46ba-bf98-c0c7377b1b97","nome":"Grupo 8"},{"id":"2a2c14bc-2957-495e-89cf-1d176eedf780","nome":"Grupo Vendap, S.A"},{"id":"9a79b956-20a0-44a6-97fc-b7a987571164","nome":"Gruvenda"},{"id":"65a0f45c-94af-4b75-85f9-639a557e7a77","nome":"Guarda Mor, Lda"},{"id":"795b1988-1a8e-4b6f-9a44-6c0c26f4efd1","nome":"Gustavo Cardoso Borges"},{"id":"0b2f0c30-32fd-44c9-9297-ae1957feb8f8","nome":"H2Pool - Sociedade de Construção de Piscinas e Equipamentos Lda"},{"id":"9124d653-5fc9-4d6d-a6bc-dc983a6c9946","nome":"Habitium"},{"id":"1fe796e2-790d-4c56-8072-17137d8e3e4d","nome":"Haeger"},{"id":"7865b46d-416e-4dfd-b3e6-c58d90a1b9ac","nome":"Haier"},{"id":"10856b6e-ed32-4d8e-bd10-c5084878bc58","nome":"Haier Europe"},{"id":"862799f5-e55f-48e6-9be5-a998ab1f3f58","nome":"Handlie"},{"id":"e5cf4db5-ba99-4ed4-9060-1fdd2712f306","nome":"Havwoods"},{"id":"7cbe9252-dc8a-4d5b-9f44-9bef0b515814","nome":"Hiper Cascais"},{"id":"57bff840-fec4-404d-8217-f15cef072c35","nome":"HJ-Andaimes Unipessoal, Lda"},{"id":"a788eae0-bc11-4690-b113-5afa5a808ae8","nome":"Hormann Portugal - Técnica e Inovação Industrial Lda"},{"id":"3c703855-2baa-4ac3-a548-dbc94abff58a","nome":"Horto do Campo Grandes, SA"},{"id":"60c5f0ea-d9ac-42e6-a5c3-5850a8c5c92d","nome":"Idealhouse - Mat. Construção"},{"id":"2c483c18-c414-484f-b0d8-262129bbd4cb","nome":"Idrisa Cande"},{"id":"e37bd3ec-f849-4cca-ac26-939ff14cded6","nome":"Ieol, Lda"},{"id":"c25e13d8-99ac-4ea4-8db5-a674f76506c7","nome":"IKEA"},{"id":"e656b968-3462-4e4f-92cb-129399422271","nome":"Inácio Bento, Lda"},{"id":"f6e8297e-8ba5-4e58-8dab-ac53962b87cd","nome":"Indopave - Pavimentos e Construção Lda"},{"id":"b5d8ce26-174f-4279-9191-49349bdc6fe5","nome":"Inovconcept, Lda"},{"id":"5434228c-86d8-4003-a8a1-1225d8b55508","nome":"Instruel - Sistemas de Controlo de Processos Industriais Lda"},{"id":"df01f3fa-e0bf-40f9-8bb4-da4a23c6bc10","nome":"Ion Popa Unipessoal, Lda"},{"id":"3c1a54fe-086c-418b-93db-11d726f457a2","nome":"Ionut Radu Farcau"},{"id":"5c0d4ab7-d4d1-4f2b-9cd0-f77e190fd02e","nome":"IRI - Isolam., Revest., Imperm., Lda"},{"id":"1fba07b8-e2da-4fd6-b358-609769b5cdf9","nome":"Íris Amarelo, Lda"},{"id":"42fab36a-5857-4703-8ffe-3aef1df416b1","nome":"Isolamestre, Lda"},{"id":"be9eacd0-60f4-4823-815e-646c12e1339e","nome":"Isoland - Impermeabilizações, Unipessoal Lda"},{"id":"5bb6020d-b138-4987-a1d3-5f5cd8a9ad65","nome":"Isolaterm (Maria Alice Santos - Unip., Lda)"},{"id":"4fe5b6b0-d837-4857-8115-443e1cb3d55b","nome":"Isolpedro Unipessoal, Lda"},{"id":"90fd7d84-41a6-4326-a69e-f868683f93b8","nome":"Isotexsa - Impermeabilizações Para A Construção Civil Lda"},{"id":"34b2e8a7-be56-43f4-98c2-243069db9fe3","nome":"ISPT Requalificação, Lda"},{"id":"7e5bb956-4d59-41b4-92c9-25c2338fe3c5","nome":"Israel & Filho, Lda"},{"id":"ed2c0513-bc73-437d-a2f5-545d0947b428","nome":"ITG - Instituto Tecnológico do Gás"},{"id":"bc839326-c7db-4631-9fa9-09a046ab9986","nome":"Ivo Almeida Home Styling Unip."},{"id":"f863cf7d-20a3-4dd3-b965-af0770f88138","nome":"Ivo Silva Unipessoal, Lda"},{"id":"f8f91a66-05fa-4b1b-af16-bcb34e783f53","nome":"J M Silva, Lda"},{"id":"cddc35a6-a18b-40d0-8521-81c9703ecccd","nome":"J R Dias, Lda"},{"id":"327e951f-c8af-4589-a1e7-036711b68267","nome":"J. Clemente & Filhos, Lda"},{"id":"0809937e-79e5-47f1-877a-9adbd4037c09","nome":"J.& J.teixeira S.A"},{"id":"56335680-eb25-465f-8560-50292a893baa","nome":"Jard Garcia da Orta"},{"id":"ba2b8705-4bf9-4254-a98d-0c68ae44e54a","nome":"Jardim Primavera, Lda"},{"id":"e1d7ce7c-5168-4616-9293-e609649e4d21","nome":"JLMG Soluções, Unipessoal Lda"},{"id":"d6088b51-eb32-4464-9136-8b7584f9f224","nome":"JM Silva"},{"id":"1e1708d4-962d-4730-b1f1-c04fee44b6d4","nome":"João Jose da Fonseca, Lda"},{"id":"e9907cdf-7095-49b8-8423-e9c07ec4d64a","nome":"João José da Fonseca, Lda"},{"id":"c6a34ad4-7530-40d8-8408-0f00846c8ba8","nome":"João Lopes"},{"id":"b73991a5-7126-4177-a6e3-1ff1c60cbf16","nome":"João Moreira & Filhos, Unipessoal, Lda"},{"id":"0598c35b-e8b8-4a92-9368-ac0b69c0c6ce","nome":"Joeltec, Lda"},{"id":"c5ca7d81-41dc-487b-9240-bf5ef299ae3d","nome":"Jofebar, S.A"},{"id":"8a3d92c5-83d5-458e-ad19-baa8a173c90e","nome":"Jorge Miguel Judice Norte Correia"},{"id":"d37b7c52-8bd4-4b95-9628-8171c8b760aa","nome":"José Eduardo & Santos, Lda"},{"id":"540444d6-8ad0-4b6d-a0e7-ce6fcbc0edc5","nome":"Jular - Jular Madeiras, Sa"},{"id":"426d8857-db89-4dfb-a33c-2703e5939965","nome":"Jular - Madeiras S.A"},{"id":"66c6516d-74d9-442d-9f2f-41998c16f604","nome":"JULAR Madeiras"},{"id":"eb751bf7-dcd8-403a-a2bb-e63097acbbc8","nome":"Junwei Jin"},{"id":"9129792d-9e0a-4a89-bc61-572a1040be4f","nome":"Kaiserkraft"},{"id":"729e6759-c020-4d6e-8c51-37bf9ad69485","nome":"KCBerry Microcimento"},{"id":"114963a7-b3a6-4032-b294-4a10528bdf9d","nome":"Kentex Tintas"},{"id":"90cfc491-5ee9-4fd3-88d2-a2440575dde7","nome":"KERCORIAN"},{"id":"7b0735b5-b170-4410-9662-24cf3fb204be","nome":"Klein"},{"id":"4b1d9a3f-bbf7-41ec-8ce1-d78c0b411652","nome":"Koklatt, Lda"},{"id":"c1aff3e8-b224-461c-a016-8c74585e88c9","nome":"KOMAT S.A."},{"id":"bf179c7f-c214-4911-82f7-3e9118cd8323","nome":"Kong Weiqin"},{"id":"1d213285-8a71-4330-b061-1913966de3b7","nome":"Kubercano, Unipessoal Lda"},{"id":"06bb2a58-b75d-4ed2-8515-9e5e9e586a85","nome":"Labo Portugal, S.A."},{"id":"7213f7c5-ad23-415d-beb1-f41b0def030e","nome":"Lacagem Calado"},{"id":"3499e5e6-ee38-4286-8bf3-b3d0e0819e3e","nome":"Lamadas e Luz"},{"id":"2ed8bfdd-4386-4eb0-b478-5df7c90c8c9b","nome":"Lamp Twist"},{"id":"be0ec810-97d2-4dc5-bb6f-632736ca7bc7","nome":"Larfogo"},{"id":"1d2b2cfb-a9d5-479a-9ed0-78a62d4b8073","nome":"Larfogo - Lareiras e Recuperadores de Calor, Lda"},{"id":"458a861f-d721-4715-985f-8d037898ab2e","nome":"Leandro Miguel Ferreira Bento"},{"id":"5639266f-9b45-49fa-80db-f2d6b1db5ced","nome":"LedLux"},{"id":"de392a65-7d39-4a8b-864c-2e594dbb3b33","nome":"Leonardo Morais Lopes, Lda"},{"id":"8b4d30dd-7d76-47ed-9455-9ca5d0de166e","nome":"Leonor Martins Almeida"},{"id":"7c6f2b7f-551e-46a0-b7ee-02af15daca84","nome":"Leroy Merlin"},{"id":"ac1f67ce-81df-47e6-823b-c0255aab30e0","nome":"Leroy Merlin(Balneo)"},{"id":"bd54f75c-a89f-4be8-9d1c-732f85cd2354","nome":"Leroy Merlin(Ceramicalia9)"},{"id":"aa913ac7-13a3-405d-95ad-e250f942a378","nome":"LIDL"},{"id":"cddcdcc2-60ed-44f2-9c4e-e3625410d0b6","nome":"Liftech, SA"},{"id":"afd303c8-5b33-4447-b798-ceb38d38ad3f","nome":"Lisnautica, Lda"},{"id":"13708baa-6b40-43c9-8871-112a329b5172","nome":"Listacos, Pavimentos e Decorações, Unipessoal Lda"},{"id":"849e3f37-5023-4d27-91ed-c489bd7a6c97","nome":"Live It, Lda"},{"id":"1e74f93e-2bdd-4cca-950a-d811ae490946","nome":"Liveplace - Palegessos, SA"},{"id":"6ddcc95b-23f9-4066-b750-41c4ba4c60cf","nome":"LMS - Gestão Projectos Engª, Unip."},{"id":"f4ba1e32-9121-4eff-8721-919162da845a","nome":"Loja Cascais"},{"id":"06ca9025-215d-41e8-8cf6-bc45264fc6a8","nome":"Loja do Campo, Lda (WeGarden)"},{"id":"f7ea1c22-107f-4c4b-ad11-61a431aef2b7","nome":"Longuinho - Mármores e Granitos"},{"id":"1557b216-7498-4dd3-b5cf-d9287f3d64cb","nome":"Louresfibra, Lda"},{"id":"ca1f6c09-dce7-4d05-9c2a-45f2a95aa69e","nome":"Louriestuque Soc. Estuques e Pintura Lda"},{"id":"414d8db2-2120-4a2c-9ef1-c47b6b7b566d","nome":"Louros, Lda"},{"id":"af590809-29a3-4101-a556-00501d4d76a5","nome":"Loxam Portugal S.A."},{"id":"865aedf3-6983-4cfc-8286-5671c3418daa","nome":"Luban Assistência Técnica Lda"},{"id":"6785806c-2fd8-4e80-83a3-4fb8c756872a","nome":"Lucia Marques"},{"id":"56c8b037-6c4f-4a86-b0f3-90ad4c93c433","nome":"Luciano H.Correia/Euripedes C Leal"},{"id":"2e49885f-8b23-43ad-9133-4c98e2969c5c","nome":"Ludcont - Ludgero Dias Caetano Unip. Lda"},{"id":"805fa0e0-c009-4b09-bac5-aa14baede40e","nome":"Lumories"},{"id":"cbd35fe1-70a3-4f18-9416-a58179ebe134","nome":"Luso Tulhos"},{"id":"adfcba2a-85dd-49e3-89b2-28cc7a9b8c05","nome":"Lusomembrana, Unipessoal, Lda"},{"id":"f88027f2-3a48-46bb-aab7-13f8269a6412","nome":"Lx Selecta"},{"id":"862a9971-8855-4ae9-9aef-a34dff09fb6f","nome":"M.E.R. Construções, Unipessoal Lda"},{"id":"5bb72b01-b6f9-40aa-8f22-148a65c24e43","nome":"M&M - Molduras Minuto, Lda"},{"id":"da091203-b7c4-4c43-857c-e5b5d212235f","nome":"Machaves"},{"id":"321c3995-ec03-4ca4-80ab-525aa35cd76f","nome":"Mafrigessos, Lda"},{"id":"458a54f0-9ccf-4129-bb08-d8307515c0a0","nome":"MAGFIL - Manuel Antonio Gomes & Filhos, Lda"},{"id":"d0ea380e-d208-4553-98f2-66dc11e00016","nome":"Majoli Tiles, Lda"},{"id":"b446fe5c-d578-4b82-9b89-116d6f156bb2","nome":"Mantovani"},{"id":"5b4d7ee2-d8b7-4aa0-b424-31bf50fc70b1","nome":"Manuel & Cardoso Lda"},{"id":"af66895e-68d6-4e47-8d43-e5d58ae82a77","nome":"Manusa - Portugal , Sociedade Unipessoal, Lda"},{"id":"0ec0eb04-c2bc-4cb2-b782-2fa9b98993b8","nome":"Mapp Unipessoal, Lda"},{"id":"a0928da2-2c86-478f-8aaa-ed03879bd304","nome":"Maquimoi"},{"id":"bfa9b9f8-139c-4ef4-9946-9c2318f44ecc","nome":"Marco Garcia Antunes, Lda"},{"id":"840a37ca-8340-43d9-93f9-9f285adaaabc","nome":"Margralves-Marmores e Granitos Lda"},{"id":"36468765-1777-4e2d-8f45-bec867babbdc","nome":"Maria Hortense Simão Rodrigues Umberlino"},{"id":"92aa62bd-2a1e-4356-9a3e-1fdc556be376","nome":"Marmistoi"},{"id":"9d871f0c-d715-43b0-86b4-62c48c9225ec","nome":"Marmores Galrão-Eduardo Galrão Jorge & Filhos S.A"},{"id":"522a4768-b1fb-47f6-ab9e-36d3a49fbe13","nome":"marrakech design"},{"id":"cd202ba7-5608-47c5-900a-dc5b6b842481","nome":"Marta Isabel Luís Da Avó"},{"id":"c9fbfb07-8499-4800-a427-8f44a0ee1fb7","nome":"Masorosa, Lda"},{"id":"1c86a9ad-9be3-4ec9-9c42-5cc1eeb3cec9","nome":"Materfut , S.A"},{"id":"75ad9799-3d36-4b80-8840-fb8592cf829b","nome":"Matermaxime - Materiais de Construção, Lda"},{"id":"529f2a53-8337-4e58-918c-19bce0b8045c","nome":"Matobra, SA"},{"id":"1d07c9ed-2deb-4f1d-a18a-16865cdb5f60","nome":"Mauresmak, Unipessoal Lda"},{"id":"0fc32584-8552-4eb0-9921-f75048ba56f9","nome":"Maxmat"},{"id":"2ed69ec0-ce80-448d-8206-ec70e8905e06","nome":"Mdit - Instalações Técnicas Especiais, Lda"},{"id":"be5ad28e-8217-4a23-87fe-806f934e690a","nome":"Megaluz, Unipessoal, Lda"},{"id":"c78ca6df-3fb3-4b40-9cf8-82f9fc35be0f","nome":"Megaroof - Construção Civil, Unipessoal Lda"},{"id":"bcc50536-66cd-457a-882e-4501ba90dd30","nome":"Mendes & Irmãos, SA"},{"id":"74411509-a538-4413-9307-4de3166772cd","nome":"Mercearia da Aldeia"},{"id":"b9fbe875-eea8-41ea-bc13-10b6ea33ec19","nome":"Mesas & Mármore"},{"id":"821c622d-f5ee-4ac2-9531-2768266a2259","nome":"Mestremat Portugal, Lda"},{"id":"38af1214-961c-4ace-9f64-433c5833a3f5","nome":"Metaldesign, Lda"},{"id":"d025ec8a-85be-45e0-9224-850ea1ae0d09","nome":"Metalofarense - Produtos Siderúrgicos, S.A"},{"id":"e8419cc0-b9e2-4be3-93fc-778db55c8bfa","nome":"Microcrete Factory, Unipessoal Lda"},{"id":"b48f5850-dad5-4f1c-acd6-2e097e5493ad","nome":"Mideia, Unipessoal Lda"},{"id":"52616d61-ed69-4fb5-964c-3f845af94457","nome":"Miguel Feiteira, Lda"},{"id":"2693e226-a4c1-4234-a23d-d49017636f33","nome":"Mil Coisas Esquadria Elegante, Lda"},{"id":"83fbc6b1-205a-425f-a7c8-2d77f33be334","nome":"Minipreço Cascais"},{"id":"8def336b-bd72-4163-9c2f-89a05dc2d1ad","nome":"Minit Spain, SA"},{"id":"b53810c7-ccae-4f34-89fe-a362b83d345a","nome":"Miragem - Iluminação Arquitectural"},{"id":"d219db40-ff26-4ea6-9157-3d59c3cfdf28","nome":"Miratubos, Lda"},{"id":"0088467e-2049-459c-9b83-ca8cc83cec50","nome":"Misto de Perfeição"},{"id":"353ee27b-c63e-42d1-85f6-0dc74910100e","nome":"Mobili Fiver"},{"id":"0c5f037e-9dc5-4617-a13e-ec0a4d5c1562","nome":"Modernilux - Instalações Eléctricas Lda"},{"id":"05af9147-28ba-4d48-8143-e4c8b2d5adda","nome":"Moldacoria Lda"},{"id":"98eef440-be78-493d-9a61-ec001f5ffa87","nome":"Moldacoria, Lda"},{"id":"7c38183f-bd08-4334-a5b0-9047ce8560cc","nome":"MONTAEL SA"},{"id":"12e1a4da-471d-4fa6-85e4-bace7516ea39","nome":"Montalgarve-Materiais e Equipamentos Industriais S.A"},{"id":"aa939f3b-d88e-41f8-8216-9a2ed30627b3","nome":"Motivo Visionário - Ferro e Cofragem, Unipessoal, Lda"},{"id":"a78677d8-8b29-4f61-b7bf-07857e28e337","nome":"Mourelec, Unipessoal Lda"},{"id":"eb30a1b7-6d6c-4b8d-99cd-7e45874edbb5","nome":"Movilima, Lda"},{"id":"fe45eb24-596f-45e4-b47c-0e18314a9ae7","nome":"MTL - Madeiras Tratadas"},{"id":"23a4ff58-2a0b-46d7-be11-c6e457c8e71a","nome":"Multividros"},{"id":"cc244bff-3c0d-4ee8-942f-adf2383cd76d","nome":"Multiwindows"},{"id":"c556b863-d798-4fdb-96a2-1b8e6a1818d5","nome":"Mundimat, S.A"},{"id":"401c0807-12c3-49d1-b28c-c39412d48d22","nome":"Mundo ao Quadrado"},{"id":"7d10a131-1b7f-4e04-bbe1-d7820f68c0a9","nome":"Mundo ao Quadrado, Lda"},{"id":"eb44ff91-86cc-4463-ab49-11618f5a4ba2","nome":"Mundo dos Canalizadores, Lda"},{"id":"5f0b132b-fcc3-4471-ba60-7690ffb4d631","nome":"Natura - Centro de Jardinagem"},{"id":"fe6e63c6-4d2b-4505-b795-8240b0c8478d","nome":"Nicolau & Rosa, Lda"},{"id":"e2534277-bd2c-4fbb-8497-ac36a20a9a7c","nome":"Norauto"},{"id":"ad466c77-8db7-4918-b6da-52ebdebcf33a","nome":"Normo Identidade, Lda"},{"id":"7a314f50-bf3d-4080-92da-7ccf1bf183e7","nome":"Norpavi, Lda"},{"id":"81afe4f9-e208-4131-9348-97458b38fbd5","nome":"NoSun Unipessoal Lda"},{"id":"6ccc678c-458f-4650-abd6-aedc678e40e6","nome":"Nuno Epifânio"},{"id":"fa305d69-33ec-4498-ad74-e5c30d77ea67","nome":"Nuno Filipa Coelho Pinto"},{"id":"958d534b-7cdd-4f64-bcd5-c7a75a2317ee","nome":"Nuno Leitão"},{"id":"f6db1b15-820e-4dc5-b42f-1745fd82b73c","nome":"Nuno Manuel da Silva Marques"},{"id":"92ebbd3b-777f-4dc3-b3bd-c9b88b3bdf75","nome":"NV Gás, Unipessoal Lda"},{"id":"5f61ca47-2b8e-48fc-84b4-8f59c6924ba3","nome":"O Meu Jardim (Wiseworries, Lda)"},{"id":"486bb2db-e245-472c-ac91-57aba008b481","nome":"Obramat"},{"id":"dff77ca3-6416-4cd3-9dde-6c6e7aeb9bc2","nome":"Obras 360 by SOTECNISOL"},{"id":"17342ac4-6bc1-42e1-80e7-2d0943432d49","nome":"Obriesquadria, Lda"},{"id":"002bf395-a2f2-42d8-b4e7-506e1fca38ac","nome":"ODEM Portugal, SA"},{"id":"3f6b0d18-d535-4e82-8747-43f13136cb36","nome":"Odifercol, Lda"},{"id":"78044472-507a-4b23-925a-2fec576cefca","nome":"OKGRES, Lda"},{"id":"771a0fcc-b585-4c25-a89f-c4a16d7765b9","nome":"OLT - Gestão de Resíduos e Demolições"},{"id":"affb876d-05e8-4fcc-b41b-7a3e1fbb061d","nome":"Ourividro-Vidreira Ouriense S.A"},{"id":"c6ee4d69-5bdf-4804-83be-fadb19735adb","nome":"P.A Moeve Cascais-Birre"},{"id":"565f7e6c-f6f4-4f1f-b7bb-f20c7c130687","nome":"Padrão Secular - Unipessoal Lda"},{"id":"59a0d3cc-b6a3-4a2d-8afb-c73bd3e6f886","nome":"Panorama Delicado (Radu)"},{"id":"21422580-1ab3-405f-82ab-790806230f17","nome":"Parâmetros e Segmentos, Lda"},{"id":"35f41937-d0a3-45cd-8189-7c92ece02551","nome":"Paulo Fernandes Wefixit"},{"id":"2adb140a-6e6a-4261-8ccb-ca04e2fa5b5d","nome":"Paulo Henriques, Lda"},{"id":"62000486-9d81-4702-b6d0-e50a907b86f3","nome":"Paulo Jorge Amado Ribeiro"},{"id":"fb0eaf4b-0ce7-4fc5-ae00-17aabc74609a","nome":"Paulo José Silva Seguro"},{"id":"3ef63602-50c0-4567-b0d3-48c920327b89","nome":"Paulo Neto, Lda"},{"id":"c85f8b1e-26c5-42d3-8ecb-0331f59e0a36","nome":"Pavimentos Guara"},{"id":"0467fa0e-e0ed-428f-8613-df2ca3b52591","nome":"Paviséqua - Materiais de Construção Lda"},{"id":"83f7b67f-f634-424f-bc46-48b6bafce63b","nome":"PCDIGA, Lda"},{"id":"f0f4e313-4fb7-482c-aded-ff8f4eec35a1","nome":"Pé d' Cabra"},{"id":"f2067949-aaf0-476c-ad98-34610b8d38e4","nome":"Pecimouse, Lda"},{"id":"7798ec82-cc91-4396-8883-6be6ccb45661","nome":"Pecol, SA"},{"id":"dddc63fa-14ec-4531-b62b-140ab058ae6f","nome":"Pedra Matizada, Unipessoal Lda"},{"id":"ed369383-aa2e-4467-ba7b-d9072c06ae58","nome":"Pedramalba - Recuperação de Mármores, Unipessoal Lda"},{"id":"9ea504eb-9f0e-4c6c-816e-6ff0d7ecf4e5","nome":"Pedras - António Manuel"},{"id":"7651c591-6446-4147-ba34-7d7c986150bf","nome":"Pedro Miguel Casimiro Fonseca"},{"id":"9ca62a23-d498-42fc-b6b0-b3c868ec0f30","nome":"Pedrosa & Filhos"},{"id":"9b9767f6-bd7e-4ead-81d7-edb159a5518f","nome":"Pereira & Valongo"},{"id":"d53215b0-2864-4ebb-9089-2c8d74de8449","nome":"Perímetro Direto, Uni, Lda"},{"id":"c03ddc83-9656-4d71-b6be-9db12ff47e8e","nome":"Pigmentos - Loja de Tintas"},{"id":"cd5d704f-6ddd-4e1a-8c27-a4e7233b73de","nome":"PILARES METÁLICOS"},{"id":"4d7f729d-3539-4917-8f38-23f4941b1f43","nome":"Pimarttex (M.Pires Nogueira, Lda)"},{"id":"cdaa73c0-1e3e-4dbd-a429-4dc259be97e6","nome":"Pingo Doce"},{"id":"aea86db8-a1dd-48cf-88f9-db395d618fcf","nome":"Placofix - Revestimentos, S.A"},{"id":"979bce50-b499-495f-af1e-f6dc284068ee","nome":"Planta no Ponto, Lda"},{"id":"0b1b719c-232a-4577-99f4-dcd905645f61","nome":"Planthiza"},{"id":"1d41cb03-81fb-4e96-a594-30f58e2dad75","nome":"Polistone, Lda"},{"id":"d22b394c-41d7-4c47-b988-485a7e86e3e2","nome":"Polo Zero, Lda"},{"id":"817aae78-2100-43a7-b28c-5a8f7250f8a7","nome":"Ponto Singular, Lda"},{"id":"c03c80b9-2b44-465c-ad94-2e58b82e6555","nome":"PORCELANOSA Grupo"},{"id":"373210e9-b4f1-43d0-a5f5-bd01517c4aec","nome":"Portrisa"},{"id":"10ebf86a-50e8-49d4-b5bc-d7225524f15a","nome":"Portrisa - Indústria de Portas, S.A"},{"id":"ec00cb57-fd4f-4003-b88e-4a27d7aa0d7a","nome":"Preceram, SA"},{"id":"2c010ae5-c93d-4f0d-9552-078d39945db1","nome":"Prestigial"},{"id":"649bc7ad-9fc4-4344-99ca-224f3ffa89e2","nome":"Primedoor, Unipessoal Lda"},{"id":"055506c9-ccc3-48d9-8b78-7b3e156f2450","nome":"Printlar, Unipessoal Lda"},{"id":"a82fc0f0-58db-4e3b-b8e7-8a652e36d978","nome":"Privilégio Forasteiro"},{"id":"84cfb9c2-9488-4672-9bb4-ae9c86cf7c83","nome":"Projeep Multimarca"},{"id":"56eb4247-ca92-4b4d-b0f6-2f5236297c73","nome":"Racinair, Lda"},{"id":"2f602f8f-b28b-4860-ac5c-06af8b03080f","nome":"Rainha das Chaves"},{"id":"561a23ed-42a5-4109-aafb-2e3e55a0e936","nome":"Rainha das Chaves, Lda"},{"id":"4c7e8014-4686-4a74-9b5f-8a285f5ea916","nome":"Red Tower, Lda"},{"id":"70c2ca2c-3f64-456c-b006-4548ce2b7e13","nome":"Relpa, Unipessoal, Lda"},{"id":"b9d45b1b-f00e-4f73-8a88-2d7658672eb5","nome":"Relva Viva, Lda"},{"id":"5948861d-49a4-4137-9f5f-7aaa3b225f42","nome":"Representações Esferovite, Lda"},{"id":"a318e923-4937-41ce-bde3-cf069e686f5d","nome":"Represtor-Representações de Estores, S.A"},{"id":"36a49cb3-0f2e-44fc-b765-1a73978cb07e","nome":"Restaurante Paraíso Alentejo"},{"id":"8d8602c6-9273-47a5-ae81-adbba577bc27","nome":"Reuter Europe"},{"id":"dfefc04c-57ee-4e58-b3e8-fcd45627d472","nome":"Ricardo Martins"},{"id":"812881c6-24af-45ad-ae0a-12f4ddd23fec","nome":"Ricardo Miguel  Botelho da Silva"},{"id":"b7082420-fd95-44cf-807d-60c808dc5e71","nome":"Ricardo Miguel Botelho Silva"},{"id":"0270bcba-9706-45ca-9ac7-9de08910e9fb","nome":"Richard Helmrich"},{"id":"7b48bc07-7383-40a1-aa3d-56abe798dc60","nome":"Richimi"},{"id":"6bf18ade-be65-4903-925f-6da210df1b6f","nome":"Rodrigo M. Brás Construções, Lda"},{"id":"3a768e5d-04f8-4d2e-ba56-dbeca3f623af","nome":"Rota de Vidro, Lda"},{"id":"abaf1bdc-d0e3-496c-8417-f341f2cd7c1c","nome":"RP Gruas"},{"id":"dfc64000-e26f-4883-8813-aa4eea51e9c9","nome":"RS Wood - Montagem Carpintaria"},{"id":"eb4a1867-3a07-4601-9dd3-5fe28b789e0c","nome":"Ruben Ramos - Transp. Especiais, Lda"},{"id":"64a41f0e-12d4-4142-969c-9ad77ca173ce","nome":"Ruben Ramos Tranp Especiais, Lda"},{"id":"a02f6bb0-dc1a-4c86-8e1a-85d611cc30f7","nome":"Rubinetteria Shop SRL"},{"id":"c3759410-b6ce-4223-97b6-09e2bcb1cbc8","nome":"Rui Miguel Gonçalves"},{"id":"06dcb447-a404-4384-a479-b69d00618167","nome":"Rui Pedro Teixeira Unipessoal, Lda"},{"id":"6eaa26dd-7de8-462a-ac43-7d7fec2efc06","nome":"Ruslan, Lda"},{"id":"e553c1e7-d603-4a8d-b172-13e7eca82a47","nome":"SAM'S, Lda"},{"id":"3ccdcc37-b2c8-4a3b-8d54-f7445173b8b4","nome":"Sancovedras, Lda"},{"id":"a63f23b0-c7e9-4b7e-9f4d-3608b081c375","nome":"Saniluz"},{"id":"45aa14ac-ff75-4b47-86b1-821775b01296","nome":"Sanimaia"},{"id":"10b47d66-ac31-4452-8457-9ae4fdb48597","nome":"Sanitop, Lda"},{"id":"a0c504d3-ef68-40d9-a05f-5da6cbabdbfc","nome":"Sanitorres - Materiais de Construção, Lda"},{"id":"0c4f4ba4-0a98-4183-a7a6-4be9977898f9","nome":"São Januário, Lda (GALP)"},{"id":"ff099e17-8f29-499d-943f-aa6a194a830c","nome":"SAT - Disterm.pt"},{"id":"b3a70be4-2e3d-4e74-bec7-b9198ea9f966","nome":"Sat Disterm (serviço asssistencia tecnica)"},{"id":"2da8cb2b-1004-4843-9264-255e285eb1da","nome":"Schuss"},{"id":"d3fa856d-1307-4522-9943-e4dfd1d0bb5f","nome":"SCIC Portuguesa-Cozinhas Italianas, Lda"},{"id":"b80155aa-b9b6-484d-8111-8e7266c70776","nome":"Secil"},{"id":"f1d65e0e-e923-4944-a054-b4bbb37daaae","nome":"Secil Betão, SA"},{"id":"254d4a5b-d614-4742-b5d0-a211b1e2136b","nome":"Security Center"},{"id":"92fc4fe2-6482-461f-bf48-7dbb413009cc","nome":"Security Center Cascais"},{"id":"251795aa-446d-4209-9ab4-e2c29e534302","nome":"Sérgio Manuel Martins Nunes"},{"id":"1ba4b8b2-1ebb-4d3a-bb16-c1477296f2d3","nome":"Serralharia de Fialho & André Lda"},{"id":"5a2a72c3-b55b-4383-8f84-94b4b13f8685","nome":"Serviplaco Revestimentos S.A"},{"id":"a3fb9b08-5e9a-464e-9e10-9de7480590aa","nome":"Seveme - Indústrias Metalurgicas S.A"},{"id":"3fed6615-17c8-4f72-8bdf-889cab4d5a41","nome":"SGR ambiente"},{"id":"1bb10be8-7696-4895-b2a2-b2830e8d2555","nome":"Sika"},{"id":"84d47410-92e9-43f1-b6bc-bfcfbf208d73","nome":"Sika Portugal, SA"},{"id":"5f47d078-9b04-491d-a1a1-28f8acd93a14","nome":"Silvas - Madeiras e Revestimentos"},{"id":"c7909794-bf97-4e00-93d8-96d41c9522f9","nome":"Sirolis-Prefabricados de Betão S.A"},{"id":"99e03979-f5f2-4e63-b0ef-42d2d33bc5ac","nome":"SL Material Eléctrico, Lda"},{"id":"3f79ac43-1972-4eb7-9c20-a774e757b6c1","nome":"Smartestor, Lda"},{"id":"bb283a3e-8106-4f5c-b2b8-d425cd44486d","nome":"Sobreira & Serras"},{"id":"59d279e8-caea-417c-8912-972422641141","nome":"Socaleiras"},{"id":"31890d0a-9b54-4dcf-b933-f26717e122eb","nome":"Sociedade Engenharia Avathar, Lda"},{"id":"8a41f686-2f23-4c08-ac50-54dace5c66f9","nome":"Sograma Jardins, SA"},{"id":"ded50e08-187e-4798-9cc9-6b69afc46ad4","nome":"SOLIUS"},{"id":"485a2fb3-8365-47a2-a63f-4563b5c777bc","nome":"Somapil, Lda"},{"id":"ae0fef49-e5f5-4f54-836d-721b66934590","nome":"Sotécnica-Sociedade Electrotécnica S.A"},{"id":"48250bfc-6c20-452c-9ad8-41adc1e3eeb1","nome":"Sotecnisol, S.A"},{"id":"aaa33bab-8378-4a4a-ba59-1c10a6621290","nome":"Sousa Alhadef, Unipessoal, Lda"},{"id":"b3277a79-66c1-4bb9-9961-df9e1c1ef3eb","nome":"Sr. Anacleto"},{"id":"a20f38f1-8fc9-438e-b1e2-fbaf10d25ac0","nome":"Sr. Bento (Ana Jose Ramos Ferreira)"},{"id":"621de2c0-18f3-4cf0-977e-450eee539bbb","nome":"Staples"},{"id":"af73c1de-acf2-41b8-917d-0711342d40a2","nome":"Startphase - Instalações Elétricas, Telecomunicações e Manutenção , Lda"},{"id":"f56a1f44-11c9-4431-a3bd-41f06baf11cc","nome":"Stone Ceramic"},{"id":"20cc5301-e52d-4ae0-9c5b-c190e7d023ea","nome":"Stone Soul, Importação e Exportação Unip. Lda"},{"id":"df20dfd4-6f3b-452e-a503-9119c0690815","nome":"Sublimetais, Lda"},{"id":"ee137a96-6cd6-4585-92e0-9f558a7f9604","nome":"Sucessabstrato, Lda"},{"id":"f2f4c4da-2df2-456e-8964-a0e2d0a6d3e1","nome":"Suldernus - Soluções de Engenharia, Lda"},{"id":"dc2fec58-ff3b-40d3-94c3-9f59e5bf605e","nome":"Sunblock Tech, Lda"},{"id":"a65b9fc4-6ed6-4110-9bca-11dcc91d4eb6","nome":"SuperCaleiras"},{"id":"663fae99-2ce2-427a-a035-1927b4149c31","nome":"Susan Fischer"},{"id":"18e55097-47b1-4f45-a5cb-1724a45af70a","nome":"Tailored, Lda"},{"id":"374f7107-6119-4a4f-b40b-1ad8d8bb216b","nome":"Tampcor - Transformação e Criatividade, Lda"},{"id":"6069d084-d348-4204-9e16-b477d20dceb6","nome":"Taviplac - Materiais de Reabilitação e Conforto, Unipessoal Lda"},{"id":"69abbe96-fe95-4bc2-9b1e-7755b7334570","nome":"Tecnilopes - Manutenções Eletricas, Lda"},{"id":"d13af486-9ddd-42ae-a121-9acb9457e817","nome":"Tecniquitel, SA"},{"id":"7a19e3f3-0b8b-4280-97ff-1debb9c553fe","nome":"Tecnisis -Tec Sistemas Industriais Lda"},{"id":"441080a9-ffd0-4b09-9784-869354c28b08","nome":"Tecnocamper"},{"id":"aa3b5067-4a34-447f-b950-8239246ccbbc","nome":"TecnoDome, Lda"},{"id":"b2764d0e-c37d-46c6-b3f6-e2c5fd9a7133","nome":"Termipol - Isolamentos Termicos e Acusticos S.A"},{"id":"2227f5b5-7a88-4f76-bd46-90f060962aad","nome":"Termoacumulador"},{"id":"f537e009-4048-4481-ab4c-0830cc8dd86c","nome":"Termolan - Isolamentos Termo-Acústicos S.A"},{"id":"db7196f7-53e4-4a58-af35-c3a2b4308f0a","nome":"Terracell"},{"id":"09cae0ad-dc58-46a3-be1e-a686e5642ac9","nome":"Texcoat - Revestimentos e Pinturas, Lda"},{"id":"e060f213-47d2-49c9-998a-5d3b3c1f5f32","nome":"Textura Positiva"},{"id":"473fb894-e55c-42fc-87d6-ce5709958e36","nome":"Thomaz Dos Santos"},{"id":"8baf808b-64bb-458a-81fe-a039a563ab67","nome":"TIBA - Com. Ind. Mat. Const, SA"},{"id":"1758188e-5dec-4875-8ea1-12dde8b381c5","nome":"Tico da Figueirinha"},{"id":"99ef962a-921e-4b78-a43b-c35ee24cce06","nome":"Tintas Robbialac, Sa"},{"id":"fafc4e62-d9fe-4ccd-b76b-cfa93ed66aa7","nome":"ToldoDesign, Lda"},{"id":"8d6b4f92-5b2e-4238-9aab-4ce2891530b3","nome":"Topgim Ibrafer Material Desportivo e Fitness, Unipessoal Lda"},{"id":"28ab54bf-49f7-4b1e-a269-d75217a7d57b","nome":"Topogarve - Gabinete Técnico de Topografia Lda"},{"id":"282c444c-67fb-4a9c-922c-feeb1180584f","nome":"Toscca"},{"id":"a0f72e6a-6af3-47ed-bfe0-5993687f5460","nome":"Transportes Artur Simões, Lda"},{"id":"2f5557ca-5b4a-466a-b86f-3f3969817b2d","nome":"Transportes Cá Vai Sintra, Lda"},{"id":"ee4ab3c7-c878-4b80-93f5-5dff5d613c4c","nome":"Tria - Serviços, Materiais e Equipamentos, S.A"},{"id":"b0405b11-6b88-48bd-9692-787a9fa01114","nome":"Tributo Ousado - Unipessoal, Lda"},{"id":"a4cc7264-1f55-455d-9c5d-d485ba5449c5","nome":"Tricontacto - Instalações e Comércio de Material Eléctrico Lda"},{"id":"f9e0d26c-aaed-42f2-bd24-2ec124dfa9a6","nome":"Tuboshape"},{"id":"2eec5ed0-1929-411b-b426-41bc1f833567","nome":"Ulma Portugal - Cofragens e Andaimes Lda"},{"id":"4c0f4f2c-e233-46c4-8d89-470136734a81","nome":"Ulma Portugal, Lda"},{"id":"127116c2-8b7f-468c-bdd9-d6f58f145b22","nome":"Universo Cristalizado Unipessoal, Lda"},{"id":"0a5e1017-9ca3-4486-b472-64825b632ea1","nome":"Up Energy"},{"id":"d451ee33-3ce0-4ec8-a819-38f43ad4b9d5","nome":"Urbanas Tabacarias"},{"id":"3cb6f0d4-829c-4387-afd8-8915058884ab","nome":"Urizalome - Construções Unipessoal, Lda"},{"id":"ca83a1e3-3165-4920-a758-850da10a4b8f","nome":"Valarme"},{"id":"dda95e73-d49b-42f4-b890-93f6fc367e20","nome":"Valdeci Sobrinho de Souza"},{"id":"cb47839e-88ca-4043-babb-fcd7ddcefc46","nome":"Valdemar Películas, Lda"},{"id":"58b913c1-73b6-4704-9e47-10e50268437a","nome":"VALORSINES SA"},{"id":"1d1a90d3-5976-4e4c-8af7-f92d4858dc9c","nome":"Valportas"},{"id":"998dee01-2de2-4731-b458-5a5d0485ab12","nome":"Valter Manuel Antunes da Silva"},{"id":"4464e02c-0176-41ae-9959-71026a2c8cd0","nome":"Vecourbandesign, Unipessoal Lda"},{"id":"990e3c1b-de7f-4761-a976-d077a8a404a6","nome":"Venancio P. Gamito"},{"id":"9c704194-4b45-458c-8b38-b1a23128831f","nome":"Vereda Exaustiva, Lda"},{"id":"1f7017c0-5637-4f24-975c-6f04388f8dd8","nome":"Vetor 3 - Importação E Exportação, Lda"},{"id":"cce1534c-dff4-4ab0-bcb3-ded1d5a6d8d4","nome":"Vicente & Ramos Carpintaria, Lda"},{"id":"4b5cc8ae-b5dd-4d5d-ae71-5dea88d7595c","nome":"Vicente & Ramos, Lda"},{"id":"e0553458-fb2a-4be6-8a35-466b0eae6cd5","nome":"Vida XL International B.V."},{"id":"8a84b5d7-1d98-4719-ae14-1f1132c11adc","nome":"Videlmáquina, Lda"},{"id":"c2e638f7-bda8-4359-b0a3-2f3ea926015a","nome":"Vidreira Algarvia, Unipessoal, Lda"},{"id":"8edaf4a8-2b83-46fc-b11e-c2ff26f94ea1","nome":"Vidreira Central do Feijó Lda"},{"id":"cdfb644d-f6c9-45e3-9175-2577cca840ef","nome":"Vidrotempra - Comércio e Transformação de Vidros, Unipessoal Lda"},{"id":"e0efa54a-9905-41a1-bd63-e37e1bf163f8","nome":"VipFox - Construções Lda"},{"id":"e2c478f4-5079-477f-b14d-59197b0634db","nome":"Virclar - Vidreira Central Povoense Lda"},{"id":"ac52e4ae-5f8d-427c-b407-bc9ba1d84b35","nome":"Vírgulinsólita - Unipessoal Lda (Lojas HUB)"},{"id":"c3f6c1ce-c37a-49ed-83fa-ce358087aa37","nome":"Vitor Manuel Silva Santos"},{"id":"dc643b2c-f5b1-49be-9884-8c9cadd86945","nome":"Vitorino Domingos Gonçalves"},{"id":"ddd9945f-ec68-43bf-bbfa-58705a9fc8bf","nome":"Vola"},{"id":"1423fba9-2774-44c8-8593-a24c851e1dba","nome":"Vpelículas"},{"id":"c11c0fa6-a7f5-48ab-a4c2-c0fb6cd2e561","nome":"VRR"},{"id":"7d5bda35-3f4d-4dc8-a82c-ee0c7c0cf9a7","nome":"Watchclimb - Materiais de Construção, Lda"},{"id":"f5eb3656-2c27-4e7b-9f81-e79665cfbdc4","nome":"Waterproof, Lda"},{"id":"3c5b32b3-822f-48e3-8266-f119572fa93f","nome":"Wclean Esgoto, Unipessoal, Lda"},{"id":"fa918426-d730-4688-9f03-67395ce4e7c3","nome":"WeGarden (Loja do Campo, Lda)"},{"id":"4d226d1d-4d8f-4e2b-8ec3-033dc62dc650","nome":"Werber de Sousa - Const. Civil"},{"id":"4f536c64-4c4d-4c58-8fbf-4b490db9cbfe","nome":"Windoor - Horizonte Trivial, Lda"},{"id":"0464e981-8080-47dc-9a73-2ae9564c7b7e","nome":"WoodLab (Wall Up)"},{"id":"bee6715a-49e8-450d-bb55-3c417c98b89b","nome":"Worten"},{"id":"39acca63-71e9-4e40-829c-63827cc1c335","nome":"Wovar"},{"id":"26dafa18-896c-46c5-b0ac-8f2edb5e3fc9","nome":"Wurth Portugal, Lda"},{"id":"7b8bcd23-78bf-4c8c-8527-4833b37d881c","nome":"Wxy, Lda"},{"id":"2aaa6663-b480-40cf-a552-5d1f0e8ef9a9","nome":"Zara Home"},{"id":"4877eae6-91ac-4b30-bb87-59901b436dea","nome":"Zara Home / Normo"}]$fornecedores_snapshot$::jsonb) as s(id uuid,nome text);
create temp table _forn_resultado(nome text,acao text,fornecedor_id uuid,campos text[],motivo text) on commit drop;

create or replace function pg_temp.forn_norm(v text) returns text language sql immutable as $norm$
 select regexp_replace(translate(lower(coalesce(v,'')),
 'áàãâäéèêëíìîïóòõôöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),'[^a-z0-9]','','g');
$norm$;

-- Impede alterações concorrentes durante a validação/gravação do lote.
lock table public.fornecedores in share row exclusive mode;
lock table public.fornecedores_aliases in share row exclusive mode;
do $importar$
declare
  o record; s record; v_atual public.fornecedores%rowtype; depois public.fornecedores%rowtype;
  campos text[]; chave uuid; marcador text; alterado boolean;
begin
  select * into o from _forn_opcao;
  marcador:='[Fonte Excel '||left(o.fonte_hash,16)||' — dados históricos a confirmar]';
  if not exists(select 1 from public.empresas where id=o.empresa_id) then raise exception 'Empresa não encontrada.'; end if;
  -- Deteta nomes removidos/mesclados/renomeados ou contactos novos desde a exportação.
  if exists(select 1 from _forn_snapshot b left join public.fornecedores f on f.id=b.id and f.empresa_id=o.empresa_id
    where f.id is null or f.nome is distinct from b.nome) then
    raise exception 'O diretório foi renomeado/mesclado desde a exportação. Exporte novamente; nada foi gravado.';
  end if;
  if exists(select 1 from public.fornecedores f where f.empresa_id=o.empresa_id
    and not exists(select 1 from _forn_snapshot b where b.id=f.id)
    and not exists(select 1 from _forn_fonte q where q.acao='novo' and q.key=pg_temp.forn_norm(f.nome)
      and position(marcador in coalesce(f.notas,''))>0)) then
    raise exception 'Existem novos cadastros desde a exportação. Exporte novamente para prevenir duplicados.';
  end if;

  if o.aplicar then
    create table if not exists public.fornecedores_excel_historico (
      id uuid primary key default gen_random_uuid(),
      empresa_id uuid not null, fornecedor_id uuid not null,
      fonte_hash text not null, nome_fonte text not null, operacao text not null,
      antes jsonb, depois jsonb, criado_em timestamptz not null default now(),
      utilizador_id uuid, sessao_sql text not null
    );
    alter table public.fornecedores_excel_historico enable row level security;
    revoke all on public.fornecedores_excel_historico from public,anon,authenticated;
  end if;

  for s in select * from _forn_fonte order by acao,nome loop
    campos:='{}'; chave:=null;
    if s.acao='existente' then
      select * into v_atual from public.fornecedores where id=s.alvo and empresa_id=o.empresa_id for update;
      if not found or v_atual.nome is distinct from s.alvo_nome then raise exception 'Cadastro mudou: %',s.nome; end if;
      if nullif(btrim(v_atual.email),'') is null and s.email is not null then campos:=array_append(campos,'email'); end if;
      if nullif(btrim(v_atual.telefone),'') is null and s.telefone is not null then campos:=array_append(campos,'telefone'); end if;
      if nullif(btrim(v_atual.notas),'') is null and s.notas is not null then campos:=array_append(campos,'notas'); end if;
      alterado:=cardinality(campos)>0;
      if o.aplicar and alterado then
        update public.fornecedores set
          email=case when 'email'=any(campos) then s.email else email end,
          telefone=case when 'telefone'=any(campos) then s.telefone else telefone end,
          notas=case when 'notas'=any(campos) then s.notas else notas end
        where id=v_atual.id and empresa_id=o.empresa_id returning * into depois;
        insert into public.fornecedores_excel_historico(empresa_id,fornecedor_id,fonte_hash,nome_fonte,operacao,antes,depois,utilizador_id,sessao_sql)
          values(o.empresa_id,v_atual.id,o.fonte_hash,s.nome,'preenchimento',to_jsonb(v_atual),to_jsonb(depois),public.fn_utilizador_atual_id(),session_user);
      end if;
      insert into _forn_resultado values(s.nome,case when alterado then case when o.aplicar then 'preenchido' else 'a_preencher' end else 'sem_alteracao' end,v_atual.id,campos,null);
    else
      -- Registos criados por este mesmo lote são reconhecidos na repetição.
      select f.id into chave from public.fornecedores f where f.empresa_id=o.empresa_id
        and pg_temp.forn_norm(f.nome)=s.key and position(marcador in coalesce(f.notas,''))>0;
      if chave is not null then
        insert into _forn_resultado values(s.nome,'ja_importado',chave,'{}',null); continue;
      end if;
      -- Revalida nomes, aliases e contactos ATUAIS; nunca associa automaticamente por telefone.
      if exists(select 1 from public.fornecedores f where f.empresa_id=o.empresa_id and (
        pg_temp.forn_norm(f.nome)=s.key
        or exists(select 1 from unnest(s.emails) e where position(e in lower(coalesce(f.email,'')))>0)
        or exists(select 1 from unnest(s.phones) p where position(p in regexp_replace(coalesce(f.telefone,'')||coalesce(f.contacto,''),'[^0-9]','','g'))>0)))
      or exists(select 1 from public.fornecedores_aliases a where a.empresa_id=o.empresa_id and (
        pg_temp.forn_norm(a.nome)=s.key or exists(select 1 from unnest(s.emails) e where position(e in lower(coalesce(a.email,'')))>0))) then
        insert into _forn_resultado values(s.nome,'ignorado_conflito',null,'{}','Nome, alias ou contacto já presente; rever manualmente'); continue;
      end if;
      if o.aplicar then
        insert into public.fornecedores(empresa_id,nome,email,telefone,notas,tipo_entidade,estado_confianca)
          values(o.empresa_id,s.nome,s.email,s.telefone,s.notas,null,'nao_avaliado') returning * into depois;
        chave:=depois.id;
        insert into public.fornecedores_excel_historico(empresa_id,fornecedor_id,fonte_hash,nome_fonte,operacao,antes,depois,utilizador_id,sessao_sql)
          values(o.empresa_id,chave,o.fonte_hash,s.nome,'insercao',null,to_jsonb(depois),public.fn_utilizador_atual_id(),session_user);
      end if;
      insert into _forn_resultado values(s.nome,case when o.aplicar then 'inserido' else 'a_inserir' end,chave,array['nome','email','telefone','notas'],null);
    end if;
  end loop;
end $importar$;

select (select aplicar from _forn_opcao) as aplicado,
  count(*) filter(where acao='a_inserir') as novos_previstos,
  count(*) filter(where acao='inserido') as novos_inseridos,
  count(*) filter(where acao='a_preencher') as cadastros_a_completar,
  count(*) filter(where acao='preenchido') as cadastros_completados,
  count(*) filter(where acao='sem_alteracao') as sem_alteracao,
  count(*) filter(where acao='ja_importado') as ja_importados,
  count(*) filter(where acao='ignorado_conflito') as conflitos_na_execucao,
  429 as nomes_para_revisao,
  coalesce(jsonb_agg(jsonb_build_object('nome',nome,'motivo',motivo)) filter(where acao='ignorado_conflito'),'[]') as detalhes_conflitos
from _forn_resultado;
commit;
