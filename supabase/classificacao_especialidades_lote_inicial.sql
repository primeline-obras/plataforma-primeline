-- Lote inicial validado a partir de Classificacao_Especialidades_Subempreiteiros.pdf.
-- Inclui apenas confiança Alta/Média e exclui os dois pares assinalados
-- como possíveis duplicados (Ruben Ramos e Loja do Campo/WeGarden).
-- Resultado esperado: 97 fornecedores e 99 relações fornecedor↔especialidade.

begin;

create temp table lote_classificacao_especialidades (
  fornecedor_nome text not null,
  especialidade_pdf text not null,
  confianca text not null check (confianca in ('Alta', 'Média'))
) on commit drop;

insert into lote_classificacao_especialidades
  (fornecedor_nome, especialidade_pdf, confianca)
values
  ('A Físico Piscinas (Antonio Augusto Fisico Lourenço)', 'Piscinas', 'Alta'),
  ('Acriglobal Acrílicos, Lda', 'Caixilharias', 'Média'),
  ('Altamiro & Batista - Construções, Lda', 'Construção Civil Geral', 'Média'),
  ('ALUSTORIL', 'Caixilharias', 'Média'),
  ('AMFG - Carpintaria', 'Carpintarias', 'Alta'),
  ('Amigos do Lar Construções Lda', 'Construção Civil Geral', 'Média'),
  ('ANDARAJARDINS Unip, Lda', 'Jardinagem e Paisagismo', 'Alta'),
  ('Ângulopigmentado Soluções Const. Unip., Lda', 'Construção Civil Geral', 'Média'),
  ('Antonio Augusto Fisico Lourenço', 'Piscinas', 'Alta'),
  ('António Carneiro', 'Carpintarias', 'Média'),
  ('Aristides Tete Unipessoal, Lda (Calçada)', 'Cantarias', 'Média'),
  ('Attackgás, Lda', 'Instalação de Gás', 'Alta'),
  ('AXERCLIMA', 'AVAC / Climatização', 'Alta'),
  ('Balcof - Cofragens e Constuções, Lda', 'Estruturas e Betões', 'Alta'),
  ('Betonilhas (Boomerangmágico)', 'Betonilhas e Enchimentos', 'Alta'),
  ('Boomerangmágico Unipessoal, Lda', 'Betonilhas e Enchimentos', 'Alta'),
  ('Brilhoeste - Serv. De Limpeza, Lda', 'Limpeza', 'Alta'),
  ('CAIXIAVE, SA', 'Caixilharias', 'Média'),
  ('Carpintaria - Antonio Manuel', 'Carpintarias', 'Alta'),
  ('Carpintaria Silvas', 'Carpintarias', 'Alta'),
  ('Centividro Unipessoal, Lda', 'Vidros, Espelhos e Películas', 'Alta'),
  ('CesarINOX', 'Serralharias + Soluções em Inox', 'Alta'),
  ('Coberfuzi - Coberturas e Funilarias Zinco, Lda', 'Coberturas', 'Alta'),
  ('ControlPortas', 'Portas, Estores e Toldos', 'Alta'),
  ('CRNT - Manutenção Total, Lda', 'Manutenção Geral', 'Alta'),
  ('Custódio Fernandes - Construções, SA', 'Construção Civil Geral', 'Média'),
  ('Custódio Fernandes, SA.', 'Construção Civil Geral', 'Média'),
  ('DYD - Desentup. e Desinf., Lda', 'Canalização e Hidráulica', 'Alta'),
  ('Ecosteel, SA', 'Serralharias', 'Média'),
  ('Eduardo Frade Wallcovering, Unip', 'Pavimentos e Revestimentos', 'Alta'),
  ('Effusive Spirit, Lda', 'Manutenção Geral / Serventes', 'Alta'),
  ('Electrosacavém', 'Instalações Elétricas', 'Alta'),
  ('Engimat - Engª e Construção, Lda', 'Construção Civil Geral', 'Média'),
  ('Espaço Vidro - Com. Ind. Vidros e Espelhos, Lda', 'Vidros, Espelhos e Películas', 'Alta'),
  ('Espaço Vidro, Lda', 'Vidros, Espelhos e Películas', 'Alta'),
  ('Estores', 'Portas, Estores e Toldos', 'Alta'),
  ('Flexiportas, Lda', 'Portas, Estores e Toldos', 'Alta'),
  ('Fluxion, Unipessoal Lda', 'AVAC / Climatização', 'Alta'),
  ('Fonteval - Sistema de filtragem de água, Lda', 'Canalização e Hidráulica', 'Alta'),
  ('Garden Props, Lda', 'Jardinagem e Paisagismo', 'Alta'),
  ('GÁS', 'Instalação de Gás', 'Alta'),
  ('Geotérmica Lda', 'AVAC / Climatização', 'Média'),
  ('GlobalPav - Pavimentos e construção Lda', 'Pavimentos e Revestimentos', 'Alta'),
  ('Haier', 'Equipamentos de Cozinha', 'Alta'),
  ('Haier Europe', 'Equipamentos de Cozinha', 'Alta'),
  ('Isolamestre, Lda', 'Impermeabilizações e Isolamentos', 'Alta'),
  ('Isolaterm (Maria Alice Santos - Unip., Lda)', 'Impermeabilizações e Isolamentos', 'Alta'),
  ('Israel & Filho, Lda', 'Movimento de Terras', 'Média'),
  ('ITG - Instituto Tecnológico do Gás', 'Instalação de Gás', 'Alta'),
  ('Ivo Almeida Home Styling Unip.', 'Decoração e Mobiliário', 'Média'),
  ('Larfogo - Recuperadores de Calor', 'AVAC / Climatização', 'Alta'),
  ('Liftech, SA', 'Elevadores', 'Média'),
  ('Longuinho - Mármores e Granitos', 'Cantarias', 'Alta'),
  ('Louriestuque Soc. Estuques e Pintura Lda', 'Pinturas e Estuques', 'Alta'),
  ('Majoli Tiles, Lda', 'Pavimentos e Revestimentos', 'Alta'),
  ('Marmistoi', 'Cantarias', 'Média'),
  ('Mesas & Mármore', 'Cantarias', 'Alta'),
  ('Metaldesign, Lda', 'Serralharias', 'Média'),
  ('Mil Coisas Esquadria Elegante, Lda', 'Caixilharias', 'Alta'),
  ('Miratubos, Lda', 'Canalização e Hidráulica', 'Média'),
  ('Mourelec, Lda', 'Instalações Elétricas', 'Alta'),
  ('Multiwindows', 'Caixilharias', 'Alta'),
  ('Mundo dos Canalizadores, Lda', 'Canalização e Hidráulica', 'Alta'),
  ('NV Gás, Unipessoal Lda', 'Instalação de Gás', 'Alta'),
  ('O Meu Jardim (Wiseworries, Lda)', 'Jardinagem e Paisagismo', 'Alta'),
  ('Obriesquadria, Lda', 'Caixilharias', 'Alta'),
  ('OKGRES, Lda', 'Pavimentos e Revestimentos (material)', 'Média'),
  ('OLT - Gestão de Resíduos e Demolições', 'Demolições e Gestão de Resíduos', 'Alta'),
  ('Pedras - António Manuel', 'Cantarias', 'Alta'),
  ('PILARES METÁLICOS', 'Serralharias', 'Alta'),
  ('Prospesonda - Sondagens e Captações de Água', 'Sondagens e Captação de Água', 'Alta'),
  ('Racinair, Lda', 'AVAC / Climatização', 'Média'),
  ('Relva Viva, Lda', 'Jardinagem e Paisagismo', 'Alta'),
  ('Rota de Vidro, Lda', 'Vidros, Espelhos e Películas', 'Alta'),
  ('RP Gruas', 'Transportes, Gruas e Equip. Especiais', 'Alta'),
  ('RS Wood - Montagem Carpintaria', 'Carpintarias', 'Alta'),
  ('SERGIO', 'Canalização e Hidráulica', 'Alta'),
  ('Sérgio Manuel Martins Nunes', 'Canalização e Hidráulica', 'Média'),
  ('Silvas - Madeiras e Revestimentos', 'Carpintarias', 'Alta'),
  ('Smartestor, Lda', 'Portas, Estores e Toldos', 'Alta'),
  ('Socaleiras', 'Coberturas', 'Média'),
  ('Sograma Jardins, SA', 'Jardinagem e Paisagismo', 'Alta'),
  ('Sunblock Tech, Lda', 'Portas, Estores e Toldos', 'Média'),
  ('SuperCaleiras', 'Coberturas', 'Média'),
  ('Tecnilopes - Manutenções Eletricas, Lda', 'Instalações Elétricas', 'Alta'),
  ('ToldoDesign, Lda', 'Portas, Estores e Toldos', 'Alta'),
  ('Transportes Cá Vai Sintra, Lda', 'Transportes, Gruas e Equip. Especiais', 'Alta'),
  ('Tuboshape', 'Canalização e Hidráulica', 'Média'),
  ('Urizalome - Construções Unipessoal, Lda', 'Construção Civil Geral', 'Média'),
  ('Valdemar Películas, Lda', 'Vidros, Espelhos e Películas', 'Alta'),
  ('Vicente & Ramos Carpintaria, Lda', 'Carpintarias', 'Alta'),
  ('VipFox - Construções Lda', 'Construção Civil Geral', 'Média'),
  ('Vpelículas', 'Vidros, Espelhos e Películas', 'Média'),
  ('Wclean Esgoto, Unipessoal, Lda', 'Canalização e Hidráulica', 'Alta'),
  ('Werber de Sousa - Const. Civil', 'Construção Civil Geral', 'Alta'),
  ('Windoor - Horizonte Trivial, Lda', 'Caixilharias', 'Alta'),
  ('WoodLab (Wall Up)', 'Carpintarias', 'Média');

do $$
begin
  if (select count(*) from lote_classificacao_especialidades) <> 97 then
    raise exception 'Lote inválido: eram esperados 97 fornecedores Alta/Média após exclusões.';
  end if;
  if exists (
    select 1
    from lote_classificacao_especialidades
    where fornecedor_nome in (
      'Ruben Ramos - Transp. Especiais, Lda',
      'Ruben Ramos Tranp Especiais, Lda',
      'Loja do Campo, Lda (WeGarden)',
      'WeGarden (Loja do Campo, Lda)'
    )
  ) then
    raise exception 'Lote inválido: contém um fornecedor marcado como possível duplicado.';
  end if;
end $$;

-- Mantém os nomes oficiais já existentes e cria apenas as categorias novas.
with catalogo(nome) as (values
  ('AVAC / CLIMATIZAÇÃO'),
  ('BETONILHAS E ENCHIMENTO'),
  ('CAIXILHARIAS'),
  ('CANALIZAÇÃO E HIDRÁULICA'),
  ('CANTARIAS'),
  ('CARPINTARIAS'),
  ('COBERTURAS'),
  ('CONSTRUÇÃO CIVIL GERAL'),
  ('DECORAÇÃO E MOBILIÁRIO'),
  ('DEMOLIÇÕES E GESTÃO DE RESÍDUOS'),
  ('ELEVADORES'),
  ('EQUIPAMENTOS DE COZINHA'),
  ('ESTRUTURAS E BETÕES'),
  ('IMPERMEABILIZAÇÕES'),
  ('INSTALAÇÃO DE GÁS'),
  ('INSTALAÇÕES ELÉTRICAS'),
  ('JARDINAGEM E PAISAGISMO'),
  ('LIMPEZA'),
  ('MANUTENÇÃO GERAL'),
  ('MOVIMENTO DE TERRAS'),
  ('PAVIMENTOS E REVESTIMENTOS'),
  ('PINTURAS'),
  ('PISCINAS'),
  ('PORTAS, ESTORES E TOLDOS'),
  ('SERVENTES'),
  ('SERRALHARIAS'),
  ('SOLUÇÕES EM INOX'),
  ('SONDAGENS E CAPTAÇÃO DE ÁGUA'),
  ('TRANSPORTES, GRUAS E EQUIP. ESPECIAIS'),
  ('VIDROS E ESPELHOS')
)
insert into public.especialidades (nome)
select c.nome
from catalogo c
where not exists (
  select 1 from public.especialidades e
  where upper(trim(e.nome)) = upper(trim(c.nome))
);

update public.especialidades
set aplicavel_subempreiteiro = true
where upper(trim(nome)) in (
  'AVAC / CLIMATIZAÇÃO', 'BETONILHAS E ENCHIMENTO', 'CAIXILHARIAS',
  'CANALIZAÇÃO E HIDRÁULICA', 'CANTARIAS', 'CARPINTARIAS', 'COBERTURAS',
  'CONSTRUÇÃO CIVIL GERAL', 'DECORAÇÃO E MOBILIÁRIO',
  'DEMOLIÇÕES E GESTÃO DE RESÍDUOS', 'ELEVADORES', 'EQUIPAMENTOS DE COZINHA',
  'ESTRUTURAS E BETÕES', 'IMPERMEABILIZAÇÕES', 'INSTALAÇÃO DE GÁS',
  'INSTALAÇÕES ELÉTRICAS', 'JARDINAGEM E PAISAGISMO', 'LIMPEZA',
  'MANUTENÇÃO GERAL', 'MOVIMENTO DE TERRAS', 'PAVIMENTOS E REVESTIMENTOS',
  'PINTURAS', 'PISCINAS', 'PORTAS, ESTORES E TOLDOS', 'SERVENTES',
  'SERRALHARIAS', 'SOLUÇÕES EM INOX', 'SONDAGENS E CAPTAÇÃO DE ÁGUA',
  'TRANSPORTES, GRUAS E EQUIP. ESPECIAIS', 'VIDROS E ESPELHOS'
);

create temp table lote_relacoes_resolvidas on commit drop as
with expandidas as (
  select
    l.fornecedor_nome,
    l.confianca,
    unnest(case l.especialidade_pdf
      when 'Betonilhas e Enchimentos' then array['BETONILHAS E ENCHIMENTO']
      when 'Impermeabilizações e Isolamentos' then array['IMPERMEABILIZAÇÕES']
      when 'Manutenção Geral / Serventes' then array['MANUTENÇÃO GERAL', 'SERVENTES']
      when 'Pavimentos e Revestimentos (material)' then array['PAVIMENTOS E REVESTIMENTOS']
      when 'Pinturas e Estuques' then array['PINTURAS']
      when 'Serralharias + Soluções em Inox' then array['SERRALHARIAS', 'SOLUÇÕES EM INOX']
      when 'Vidros, Espelhos e Películas' then array['VIDROS E ESPELHOS']
      else array[upper(l.especialidade_pdf)]
    end) as especialidade_nome
  from lote_classificacao_especialidades l
)
select
  x.fornecedor_nome,
  x.especialidade_nome,
  x.confianca,
  f.id as fornecedor_id,
  e.id as especialidade_id
from expandidas x
left join public.fornecedores f
  on lower(regexp_replace(trim(f.nome), '\s+', ' ', 'g'))
   = lower(regexp_replace(trim(x.fornecedor_nome), '\s+', ' ', 'g'))
left join public.especialidades e
  on upper(trim(e.nome)) = x.especialidade_nome;

do $$
declare
  problemas text;
begin
  select string_agg(descricao, E'\n' order by descricao)
  into problemas
  from (
    select 'Fornecedor não encontrado: ' || fornecedor_nome as descricao
    from lote_relacoes_resolvidas
    where fornecedor_id is null
    union
    select 'Especialidade não encontrada: ' || especialidade_nome
    from lote_relacoes_resolvidas
    where especialidade_id is null
    union
    select 'Fornecedor ambíguo na base: ' || fornecedor_nome
    from lote_relacoes_resolvidas
    where fornecedor_id is not null
    group by fornecedor_nome, especialidade_nome
    having count(distinct fornecedor_id) > 1
  ) erros;

  if problemas is not null then
    raise exception E'Classificação não aplicada. Corrija primeiro:\n%', problemas;
  end if;

  if (select count(*) from lote_relacoes_resolvidas) <> 99 then
    raise exception 'Lote inválido: eram esperadas 99 relações após expandir especialidades compostas.';
  end if;
end $$;

insert into public.fornecedores_especialidades
  (fornecedor_id, especialidade_id, origem)
select distinct fornecedor_id, especialidade_id, 'manual'
from lote_relacoes_resolvidas
on conflict (fornecedor_id, especialidade_id) do nothing;

select
  97 as fornecedores_no_lote,
  99 as relacoes_no_lote,
  count(*) as relacoes_presentes_na_base
from public.fornecedores_especialidades fe
join (
  select distinct fornecedor_id, especialidade_id
  from lote_relacoes_resolvidas
) lote using (fornecedor_id, especialidade_id);

commit;
