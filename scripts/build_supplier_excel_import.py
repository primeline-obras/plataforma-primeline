from __future__ import annotations

import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
INPUT_DIR = ROOT / "ficheiros-fornecedores"
OUTPUT = Path(__file__).resolve().parents[1] / "supabase" / "preencher_fornecedores_fontes_excel.sql"


def text(value) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    return re.sub(r"\s+", " ", str(value).replace("\u00a0", " ")).strip(" ;\t\r\n")


def norm(value) -> str:
    value = unicodedata.normalize("NFKD", text(value).lower())
    value = "".join(char for char in value if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]", "", value)


def company_base(value) -> str:
    normalized = unicodedata.normalize("NFKD", text(value).lower())
    normalized = "".join(char for char in normalized if not unicodedata.combining(char))
    tokens = re.findall(r"[a-z0-9]+", normalized)
    while tokens and tokens[-1] in {"lda", "sa", "unipessoal", "unip", "ltd"}:
        tokens.pop()
    return "".join(tokens)


def split_values(value, kind: str) -> list[str]:
    value = text(value)
    if not value:
        return []
    if kind == "email":
        candidates = re.findall(r"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}", value, re.I)
        return [item.lower() for item in candidates]
    if kind == "phone":
        candidates = re.findall(r"(?:\+?351\s*)?(?:\d[\s.\-/]*){9}", value)
        return [re.sub(r"[^0-9+]", "", item) for item in candidates]
    return [part.strip() for part in re.split(r"[;\n]+", value) if part.strip()]


SPECIALTY_RULES = [
    (("carpint", "madeira"), "Carpintarias"),
    (("serralhar", "metalica", "aco leve"), "Serralharias"),
    (("inox",), "Soluções em inox"),
    (("caixilhar", "aluminio"), "Caixilharias"),
    (("canaliz", "agua", "esgoto", "hidraulic"), "Canalização e hidráulica"),
    (("cantaria", "marmore", "granito", "pedra"), "Cantarias"),
    (("cobertura", "telhado", "rufo", "zinco"), "Coberturas"),
    (("demolic", "residuo", "entulho"), "Demolições e gestão de resíduos"),
    (("elevador",), "Elevadores"),
    (("cozinha",), "Equipamentos de cozinha"),
    (("cofragem", "betao", "estrutura"), "Estruturas e betões"),
    (("impermeabil",), "Impermeabilizações"),
    (("gas",), "Instalação de gás"),
    (("eletric", "electric"), "Instalações elétricas"),
    (("jardin", "paisag", "viveiro"), "Jardinagem e paisagismo"),
    (("limpeza",), "Limpeza"),
    (("movimento terra", "escavac", "desmat"), "Movimento de terras"),
    (("pavimento", "revestimento", "ladrilh"), "Pavimentos e revestimentos"),
    (("pintura",), "Pinturas"),
    (("piscina",), "Piscinas"),
    (("porta", "portao", "estore", "toldo", "protecao solar"), "Portas, estores e toldos"),
    (("servente",), "Serventes"),
    (("sondagem", "furo artesiano", "captacao agua"), "Sondagens e captação de água"),
    (("transporte", "grua"), "Transportes, gruas e equip. especiais"),
    (("vidro", "espelho"), "Vidros e espelhos"),
    (("climat", "avac", "ar condicionado"), "Avac / Climatização"),
    (("betonilha", "enchimento"), "Betonilhas e enchimento"),
    (("construcao", "remodel", "renovacao", "pedreiro"), "Construção civil geral"),
    (("decor", "mobiliario"), "Decoração e mobiliário"),
    (("manutencao", "reparacao"), "Manutenção geral"),
]


LISBON_MARKERS = tuple(norm(value) for value in (
    "Lisboa", "Cascais", "Estoril", "Sintra", "Alcabideche", "Alfragide", "Amadora",
    "Odivelas", "Loures", "Sacavém", "Oeiras", "Queluz", "Rio de Mouro", "Mafra",
    "Almada", "Seixal", "Amora", "Azeitão", "Barreiro", "Charneca da Caparica",
    "Margem Sul", "Torres Vedras", "Lourinhã", "Frielas", "Pontinha", "Ramada",
    "Vila Franca de Xira", "Alverca", "Azambuja", "Montijo", "Belas", "Linhó",
))
ALGARVE_MARKERS = tuple(norm(value) for value in (
    "Algarve", "Faro", "Albufeira", "Loulé", "Quarteira", "Portimão", "Lagos", "Tavira",
    "Olhão", "Silves", "Almancil", "Vila Real de Santo António", "Moncarapacho", "Lagoa",
))


def specialty_for(category: str) -> list[str]:
    normalized = unicodedata.normalize("NFKD", text(category).lower())
    normalized = "".join(char for char in normalized if not unicodedata.combining(char))
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized).strip()

    def matches(marker: str) -> bool:
        clean = re.sub(r"[^a-z0-9]+", " ", unicodedata.normalize("NFKD", marker.lower())
            .encode("ascii", "ignore").decode("ascii")).strip()
        if len(clean) <= 4:
            return bool(re.search(rf"(?:^|\s){re.escape(clean)}(?:$|\s)", normalized))
        return clean in normalized

    return sorted({label for markers, label in SPECIALTY_RULES if any(matches(marker) for marker in markers)})


def zones_for(locality: str) -> list[str]:
    normalized = norm(locality)
    zones = []
    if any(marker and marker in normalized for marker in LISBON_MARKERS):
        zones.append("lisboa_cascais")
    if any(marker and marker in normalized for marker in ALGARVE_MARKERS):
        zones.append("algarve")
    return zones


def base_rows(path: Path) -> list[dict]:
    rows = []
    book = pd.ExcelFile(path)
    ignored = {norm(value) for value in ("índice", "indice", "folha1", "folha2", "folha3")}
    for sheet in book.sheet_names:
        if norm(sheet) in ignored:
            continue
        frame = pd.read_excel(path, sheet_name=sheet, header=None, dtype=object)
        header_index = None
        for index, row in frame.head(10).iterrows():
            values = [norm(value) for value in row.tolist()]
            if any(value == "nome" for value in values) and any(value.startswith("ativ") for value in values):
                header_index = index
                break
        if header_index is None:
            continue
        for _, row in frame.iloc[header_index + 1 :].iterrows():
            values = list(row.tolist()) + [None] * 6
            name, activity, locality, phone, email, observations = map(text, values[:6])
            if not name or norm(name) in {"nome", norm(sheet)}:
                continue
            if not any((activity, locality, phone, email, observations)):
                continue
            rows.append({
                "nome": name,
                "atividade": activity or sheet,
                "localidade": locality,
                "telefone": phone,
                "email": email,
                "representante": "",
                "observacoes": observations,
                "categoria": sheet,
                "fonte": "Base de Dados de Subempreiteiros e Fornecedores.xlsx",
            })
    return rows


def consultation_rows(path: Path) -> list[dict]:
    frame = pd.read_excel(path, sheet_name="LISTA", header=2, dtype=object)
    rows = []
    for _, row in frame.iterrows():
        values = list(row.tolist()) + [None] * 8
        category, name, representative, phone, email, _, _, observations = map(text, values[:8])
        if not name or norm(name) in {"subempreiteirofornecedor2", "subempreiteirofornecedor"}:
            continue
        rows.append({
            "nome": name,
            "atividade": category,
            "localidade": "",
            "telefone": phone,
            "email": email,
            "representante": representative,
            "observacoes": observations,
            "categoria": category,
            "fonte": "Mapa de Consultas.xlsx",
        })
    return rows


def unique_join(values: list[str], separator: str, limit: int = 1800) -> str:
    output = []
    seen = set()
    for value in values:
        clean = text(value)
        key = norm(clean)
        if clean and key and key not in seen:
            output.append(clean)
            seen.add(key)
    return separator.join(output)[:limit]


def consolidate(rows: list[dict]) -> tuple[list[dict], dict]:
    grouped = defaultdict(list)
    for row in rows:
        grouped[norm(row["nome"])].append(row)
    output = []
    skipped = []
    for name_norm, group in grouped.items():
        group.sort(key=lambda row: 0 if row["fonte"].startswith("Mapa") else 1)
        names = [row["nome"] for row in group]
        canonical_name = names[0]
        eligible = bool(name_norm) and len(name_norm) >= 5 and "�" not in canonical_name
        if not eligible:
            skipped.append(canonical_name)
        emails = []
        phones = []
        representatives = []
        specialties = set()
        zones = set()
        note_parts = []
        for row in group:
            emails.extend(split_values(row["email"], "email"))
            phones.extend(split_values(row["telefone"], "phone"))
            representatives.extend(split_values(row["representante"], "text"))
            specialties.update(specialty_for(row["categoria"]))
            zones.update(zones_for(row["localidade"]))
            details = []
            if row["atividade"]:
                details.append(f"atividade: {row['atividade']}")
            if row["localidade"]:
                details.append(f"localidade: {row['localidade']}")
            if row["observacoes"]:
                details.append(f"obs.: {row['observacoes']}")
            if details:
                note_parts.append("; ".join(details))
        output.append({
            "nome": canonical_name,
            "nome_norm": name_norm,
            "nome_base": company_base(canonical_name),
            "email": unique_join(emails, "; ", 500),
            "telefone": unique_join(phones, " / ", 300),
            "representante": unique_join(representatives, " / ", 500),
            "notas": unique_join(note_parts, " | ", 1800),
            "zonas": sorted(zones),
            "especialidades": sorted(specialties),
            "elegivel": eligible,
            "fontes": sorted({row["fonte"] for row in group}),
        })
    output.sort(key=lambda row: row["nome_norm"])
    return output, {
        "linhas_brutas": len(rows),
        "empresas_consolidadas": len(output),
        "elegiveis": sum(row["elegivel"] for row in output),
        "com_email": sum(bool(row["email"]) for row in output),
        "com_telefone": sum(bool(row["telefone"]) for row in output),
        "com_representante": sum(bool(row["representante"]) for row in output),
        "com_zona": sum(bool(row["zonas"]) for row in output),
        "com_especialidade": sum(bool(row["especialidades"]) for row in output),
        "nomes_nao_seguros": len(skipped),
        "exemplos_nao_seguros": skipped[:20],
    }


SQL_TEMPLATE = """-- PRIMELINE GO | Preenchimento seguro do diretório a partir dos dois Excel históricos
-- Não cria empresas novas, não funde duplicados e não substitui valores já preenchidos.
begin;

do $guard$
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só a Gestão da Plataforma ou o Administrativo pode preencher o diretório.' using errcode='42501';
  end if;
end;
$guard$;

create temp table _fonte_excel_fornecedores on commit drop as
select * from jsonb_to_recordset($source$
__PAYLOAD__
$source$::jsonb) as x(
  nome text, nome_norm text, nome_base text, email text, telefone text, representante text,
  notas text, zonas text[], especialidades text[], elegivel boolean, fontes text[]
);

create temp table _alvos_excel on commit drop as
with fontes as (
  select s.*,count(*) over(partition by s.nome_base) as repeticoes_base_fonte
  from _fonte_excel_fornecedores s
), fornecedores_normalizados_base as (
  select f.*,
    regexp_replace(translate(lower(coalesce(f.nome,'')),
      'áàãâäéèêëíìîïóòõôöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'), '[^a-z0-9]', '', 'g') as nome_norm,
    regexp_replace(translate(lower(regexp_replace(coalesce(f.nome,''),
      '([,[:space:].-]*(unipessoal|unip|lda|ltd|s[.]?[[:space:]]*a[.]?))+$','','i')),
      'áàãâäéèêëíìîïóòõôöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'), '[^a-z0-9]', '', 'g') as nome_base
  from public.fornecedores f
  join public.utilizadores u on u.id=public.fn_utilizador_atual_id()
   and u.empresa_id=f.empresa_id and coalesce(u.ativo,true)
), fornecedores_normalizados as (
  select f.*,
    count(*) over(partition by f.nome_norm) as repeticoes_nome,
    count(*) over(partition by f.nome_base) as repeticoes_base
  from fornecedores_normalizados_base f
), candidatos as (
  select f.id fornecedor_id,s.*,
    f.email as atual_email,f.telefone as atual_telefone,
    f.representante as atual_representante,f.notas as atuais_notas,
    case when f.nome_norm=s.nome_norm then 1 else 2 end as prioridade,
    min(case when f.nome_norm=s.nome_norm then 1 else 2 end)
      over(partition by s.nome_norm) as melhor_prioridade_fonte,
    min(case when f.nome_norm=s.nome_norm then 1 else 2 end)
      over(partition by f.id) as melhor_prioridade_fornecedor
  from fornecedores_normalizados f
  join fontes s on s.elegivel and (
    (f.nome_norm=s.nome_norm and f.repeticoes_nome=1)
    or (f.nome_base=s.nome_base and f.repeticoes_base=1
      and s.repeticoes_base_fonte=1 and length(s.nome_base)>=6)
  )
), candidatos_unicos as (
  select c.*,
    count(*) filter(where c.prioridade=c.melhor_prioridade_fonte)
      over(partition by c.nome_norm) as candidatos_fonte,
    count(*) filter(where c.prioridade=c.melhor_prioridade_fornecedor)
      over(partition by c.fornecedor_id) as fontes_fornecedor
  from candidatos c
)
select f.fornecedor_id, f.nome, f.nome_norm, f.nome_base, f.email, f.telefone,
  f.representante, f.notas, f.zonas, f.especialidades, f.elegivel, f.fontes,
  nullif(btrim(f.atual_email),'') is null as preencher_email,
  nullif(btrim(f.atual_telefone),'') is null as preencher_telefone,
  nullif(btrim(f.atual_representante),'') is null as preencher_representante,
  nullif(btrim(f.atuais_notas),'') is null as preencher_notas
from candidatos_unicos f
where f.prioridade=f.melhor_prioridade_fonte
  and f.prioridade=f.melhor_prioridade_fornecedor
  and f.candidatos_fonte=1 and f.fontes_fornecedor=1;

update public.fornecedores f
set email=case when a.preencher_email then nullif(a.email,'') else f.email end,
    telefone=case when a.preencher_telefone then nullif(a.telefone,'') else f.telefone end,
    representante=case when a.preencher_representante then nullif(a.representante,'') else f.representante end,
    notas=case when a.preencher_notas then nullif(a.notas,'') else f.notas end
from _alvos_excel a
where f.id=a.fornecedor_id
  and ((a.preencher_email and nullif(a.email,'') is not null)
    or (a.preencher_telefone and nullif(a.telefone,'') is not null)
    or (a.preencher_representante and nullif(a.representante,'') is not null)
    or (a.preencher_notas and nullif(a.notas,'') is not null));

insert into public.fornecedores_zonas(fornecedor_id,zona,criado_por)
select distinct a.fornecedor_id,z.zona,public.fn_utilizador_atual_id()
from _alvos_excel a cross join lateral unnest(a.zonas) z(zona)
where z.zona in ('lisboa_cascais','algarve')
on conflict(fornecedor_id,zona) do nothing;

insert into public.fornecedores_especialidades(fornecedor_id,especialidade_id,origem)
select distinct a.fornecedor_id,e.id,'historico'
from _alvos_excel a
cross join lateral unnest(a.especialidades) x(nome)
join public.especialidades e
  on regexp_replace(translate(lower(e.nome),'áàãâäéèêëíìîïóòõôöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),'[^a-z0-9]','','g')
   =regexp_replace(translate(lower(x.nome),'áàãâäéèêëíìîïóòõôöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),'[^a-z0-9]','','g')
where not exists (
  select 1 from public.fornecedores_especialidades fe
  where fe.fornecedor_id=a.fornecedor_id and fe.especialidade_id=e.id
);

select
  (select count(*) from _fonte_excel_fornecedores) as empresas_nas_fontes,
  (select count(*) from _fonte_excel_fornecedores where elegivel) as nomes_seguros_nas_fontes,
  (select count(*) from _alvos_excel) as empresas_correspondentes_na_plataforma,
  (select count(*) from _alvos_excel where preencher_email and nullif(email,'') is not null) as emails_preenchidos,
  (select count(*) from _alvos_excel where preencher_telefone and nullif(telefone,'') is not null) as telefones_preenchidos,
  (select count(*) from _alvos_excel where preencher_representante and nullif(representante,'') is not null) as representantes_preenchidos,
  (select count(*) from _alvos_excel where preencher_notas and nullif(notas,'') is not null) as notas_preenchidas,
  (select count(*) from _alvos_excel where cardinality(zonas)>0) as empresas_com_zona_identificada,
  (select count(*) from _alvos_excel where cardinality(especialidades)>0) as empresas_com_especialidade_identificada,
  (select count(*) from _fonte_excel_fornecedores s where s.elegivel and not exists
    (select 1 from _alvos_excel a where a.nome_norm=s.nome_norm)) as nomes_para_revisao;

commit;
"""


def main() -> None:
    base = base_rows(INPUT_DIR / "Base de Dados de Subempreiteiros e Fornecedores.xlsx")
    consultations = consultation_rows(INPUT_DIR / "Mapa de Consultas.xlsx")
    consolidated, stats = consolidate(consultations + base)
    payload = json.dumps(consolidated, ensure_ascii=False, separators=(",", ":"))
    OUTPUT.write_text(SQL_TEMPLATE.replace("__PAYLOAD__", payload), encoding="utf-8")
    print(json.dumps({
        "mapa_consultas": len(consultations),
        "base_historica": len(base),
        **stats,
        "sql": str(OUTPUT),
        "sql_bytes": OUTPUT.stat().st_size,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
