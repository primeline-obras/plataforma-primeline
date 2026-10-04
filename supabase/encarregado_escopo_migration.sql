-- LOCAL: ainda não autorizado para produção. Não altera dados operacionais.
BEGIN;
SET LOCAL lock_timeout='5s';
LOCK TABLE public.colaboradores, public.subempreitadas, public.ausencias, public.fornecedores, public.fornecedores_aliases, public.fornecedores_mesclagens, public.avaliacoes_subempreiteiro, public.quadro_pessoal_alocacao IN SHARE ROW EXCLUSIVE MODE;
-- Fotografia real de 04/10/2026. Apenas catálogo; sem dados de produção no ficheiro.
DO $check$
DECLARE v jsonb;
BEGIN
 IF current_user <> 'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF current_setting('server_version_num')::integer / 10000 <> 17 THEN RAISE EXCEPTION 'SERVER_MAJOR_DRIFT'; END IF;
 v := (SELECT jsonb_build_object(
 'tables', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END ORDER BY CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END) FROM unnest(p.polroles) roleid),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
 'view_definition',CASE WHEN c.relkind IN('v','m') THEN pg_get_viewdef(c.oid,true) END) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p','v','m')),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',(SELECT array_agg(acl_item::text ORDER BY acl_item::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) acl_item),'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
));
 IF md5(v::text) <> '2be961099e9694bdd29ba95d3cc10173' THEN RAISE EXCEPTION 'CATALOG_DRIFT: interromper e repetir diagnóstico'; END IF;
END $check$;

DO $private$
BEGIN
 IF (SELECT nspowner<> 'postgres'::regrole FROM pg_namespace WHERE nspname='primeline_encarregado_20261004')
 OR NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_encarregado_20261004') THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<> 'postgres'::regrole) THEN RAISE EXCEPTION 'BACKUP_ACL_INVALID'; END IF;
 IF (SELECT count(*) FROM primeline_encarregado_20261004.snapshot)<>1
 OR (SELECT md5(catalogo::text) FROM primeline_encarregado_20261004.snapshot)<>'2be961099e9694bdd29ba95d3cc10173' THEN RAISE EXCEPTION 'BACKUP_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_attribute x JOIN pg_class c ON c.oid=x.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(x.attacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<>'postgres'::regrole) THEN RAISE EXCEPTION 'BACKUP_ACL_INVALID'; END IF;
END $private$;

-- Uma policy restritiva participa por AND: outra permissiva não reabre SELECT.
-- Não se revoga SELECT de authenticated, que é partilhado por todos os perfis.
CREATE FUNCTION public.fn_encarregado_acesso_direto_bloqueado()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
 SELECT NOT EXISTS(SELECT 1 FROM public.utilizadores u
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE
 AND u.funcao IN('gestao_plataforma','gerencia','administrativo','financeiro','diretor_obra','adjunto','preparador'));
$function$;
REVOKE ALL ON FUNCTION public.fn_encarregado_acesso_direto_bloqueado() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_encarregado_acesso_direto_bloqueado() TO authenticated;
CREATE POLICY encarregado_sem_select_direto ON public.colaboradores AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_select_direto ON public.subempreitadas AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());

-- O contexto mantém a temporalidade e os restantes campos; só retira o bypass global.
CREATE OR REPLACE FUNCTION public.fn_quadro_contexto_v1(p_inicio date, p_fim date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE u public.utilizadores; v_allocations jsonb; v_revisions jsonb; v_read jsonb; v_edit jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 IF NOT public.fn_quadro_pode_consultar_v1() THEN RAISE EXCEPTION 'PERMISSION_DENIED: sem responsabilidade autorizada para consultar o Quadro.' USING ERRCODE='42501'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>93 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo inválido.'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.data,q.id),'[]') INTO v_allocations
 FROM generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') d(data)
 CROSS JOIN LATERAL public.fn_quadro_resolver_data(d.data::date) q JOIN public.colaboradores c ON c.id=q.colaborador_id
 WHERE c.empresa_id=u.empresa_id AND q.data BETWEEN p_inicio AND p_fim
 AND (public.fn_quadro_leitura_global_v1() OR (q.tipo_alocacao='obra' AND public.fn_quadro_ler_obra(q.obra_id)));
 SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]') INTO v_revisions FROM public.quadro_dias_revisoes d
 JOIN public.colaboradores c ON c.id=d.colaborador_id WHERE c.empresa_id=u.empresa_id AND d.data BETWEEN p_inicio AND p_fim
 AND (public.fn_quadro_leitura_global_v1() OR EXISTS(SELECT 1 FROM unnest(d.obras_visiveis) w(id) WHERE public.fn_quadro_ler_obra(w.id)) OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a
 WHERE (a->>'colaborador_id')::uuid=d.colaborador_id AND (a->>'data')::date=d.data));
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_read FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id);
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_edit FROM public.obras o WHERE o.empresa_id=u.empresa_id AND (public.fn_quadro_pode_gerir_v1(o.id) OR public.fn_quadro_minha_obra_v1(o.id));
 RETURN jsonb_build_object('version',1,'allocations',v_allocations,'revisions',v_revisions,
 'can_manage_global',public.fn_quadro_pode_gerir_v1(NULL),'read_work_ids',v_read,'edit_work_ids',v_edit,
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'funcao',c.funcao,'data_admissao',c.data_admissao,'data_saida',c.data_saida) ORDER BY c.nome),'[]') FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND c.data_saida IS NULL AND (
 public.fn_quadro_leitura_global_v1() OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a WHERE (a->>'colaborador_id')::uuid=c.id))),
 'works',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'numero',o.numero,'nome',o.nome,'situacao',o.situacao) ORDER BY o.numero),'[]') FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id)));
END $function$;


-- Sem consumidor no frontend atual; ambas reservadas ao Encarregado, mas devolviam
-- pessoas globais/candidatos fora da equipa. Não criar o futuro seletor do Pacote 2.
REVOKE EXECUTE ON FUNCTION public.fn_quadro_ferias_encarregado_global(date,date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_equipa_obra_encarregado(date,uuid) FROM authenticated;

-- Projeção exata utilizada por RNC, sem custo, valor ou condição de pagamento.
CREATE FUNCTION public.fn_subempreitadas_operacionais_obra(p_obra_id uuid)
RETURNS TABLE(id uuid, obra_id uuid, fornecedor_id uuid, especialidade text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE u public.utilizadores;
BEGIN
 SELECT * INTO u FROM public.utilizadores
 WHERE utilizadores.id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR p_obra_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=u.empresa_id
 ) THEN RAISE EXCEPTION 'PERMISSION_DENIED: obra indisponível.' USING ERRCODE='42501'; END IF;
 IF u.funcao='encarregado' THEN
   IF NOT public.fn_quadro_minha_obra(p_obra_id) THEN
     RAISE EXCEPTION 'PERMISSION_DENIED: obra não atribuída.' USING ERRCODE='42501';
   END IF;
 ELSIF NOT public.fn_pode_ver_obra(p_obra_id) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: sem acesso à obra.' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT s.id,s.obra_id,s.fornecedor_id,s.especialidade
 FROM public.subempreitadas s WHERE s.obra_id=p_obra_id ORDER BY s.especialidade,s.id;
END $function$;
REVOKE ALL ON FUNCTION public.fn_subempreitadas_operacionais_obra(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_subempreitadas_operacionais_obra(uuid) TO authenticated;

-- Fecho consolidado: apenas autorização, sem alterar algoritmos económicos.
CREATE POLICY encarregado_sem_select_direto ON public.ausencias AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_select_direto ON public.fornecedores AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_select_direto ON public.fornecedores_aliases AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_select_direto ON public.fornecedores_mesclagens AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_select_direto ON public.avaliacoes_subempreiteiro AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_dml_direto ON public.quadro_pessoal_alocacao AS RESTRICTIVE
 FOR ALL TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado())
 WITH CHECK (NOT public.fn_encarregado_acesso_direto_bloqueado());

REVOKE ALL ON FUNCTION public.fn_ajustar_saida_prevista_mensal(uuid,date,numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ajustar_saida_prevista_mensal(uuid,date,numeric) TO service_role;
REVOKE ALL ON FUNCTION public.fn_atualizar_melhor_preco_comparativo(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_atualizar_melhor_preco_comparativo(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.fn_congelar_planeamento_baseline(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_congelar_planeamento_baseline(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.fn_verificar_congelamentos_pendentes() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verificar_congelamentos_pendentes() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_quadro_operar(p_acao text, p_dados jsonb, p_confirmar boolean DEFAULT false, p_versao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  u public.utilizadores;
  c public.colaboradores;
  src public.quadro_pessoal_alocacao;
  dest uuid;
  person uuid;
  day date;
  period text;
  kind text;
  description text;
  sid uuid;
  rows_before jsonb;
  v_version text;
  n integer;
  result_id uuid;
  manage boolean;
  result jsonb;
BEGIN
 IF public.fn_encarregado_acesso_direto_bloqueado() THEN
  RAISE EXCEPTION 'USE_QUADRO_V1: use a operação controlada v1.' USING ERRCODE='42501';
 END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);

  SELECT *
  INTO u
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id()
    AND ativo IS TRUE;

  IF u.id IS NULL THEN
    RAISE EXCEPTION 'Sessão sem utilizador ativo.'
    USING ERRCODE = '42501';
  END IF;

  manage := public.fn_pode_gerir_quadro(NULL);

  IF p_acao IS NULL
     OR p_acao NOT IN (
       'adicionar',
       'mover',
       'remover',
       'corrigir',
       'minha_obra'
     )
  THEN
    RAISE EXCEPTION 'Ação inválida.';
  END IF;

  IF NOT manage
     AND (
       u.funcao <> 'encarregado'
       OR p_acao <> 'minha_obra'
     )
  THEN
    RAISE EXCEPTION 'Sem autorização para editar o Quadro Geral.'
    USING ERRCODE = '42501';
  END IF;

  IF p_acao IN ('mover', 'remover', 'corrigir') THEN

    sid := nullif(p_dados->>'id', '')::uuid;

    SELECT *
    INTO src
    FROM public.quadro_pessoal_alocacao
    WHERE id = sid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Alocação não encontrada; recarregue.';
    END IF;

    person := src.colaborador_id;

  ELSE

    person := (p_dados->>'colaborador_id')::uuid;

  END IF;

  SELECT *
  INTO c
  FROM public.colaboradores
  WHERE id = person
    AND empresa_id = u.empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Colaborador não autorizado.'
    USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(person::text, 0)
  );

  IF sid IS NOT NULL THEN

    SELECT *
    INTO src
    FROM public.quadro_pessoal_alocacao
    WHERE id = sid
    FOR UPDATE;

    IF NOT FOUND
       OR src.colaborador_id <> person
    THEN
      RAISE EXCEPTION 'Origem alterada; recarregue.';
    END IF;

  END IF;

  day := coalesce(
    (p_dados->>'data')::date,
    src.data
  );

  period := coalesce(
    p_dados->>'periodo',
    src.periodo
  );

  dest := nullif(p_dados->>'obra_id', '')::uuid;

  kind := coalesce(
    p_dados->>'tipo_alocacao',
    'obra'
  );

  description := nullif(
    btrim(p_dados->>'descricao_livre'),
    ''
  );

  IF p_acao = 'remover' THEN
    dest := src.obra_id;
    kind := src.tipo_alocacao;
    description := src.descricao_livre;
  END IF;

  IF day IS NULL
     OR period IS NULL
     OR period NOT IN ('manha', 'tarde', 'dia_inteiro')
  THEN
    RAISE EXCEPTION 'Indique data e período válidos.';
  END IF;

  IF p_acao <> 'remover'
     AND (
       (
         c.data_saida IS NOT NULL
         AND c.data_saida <= day
       )
       OR c.data_admissao > day
     )
  THEN
    RAISE EXCEPTION 'Colaborador indisponível nesta data.';
  END IF;

  IF kind NOT IN (
       'obra',
       'garantia',
       'pontual',
       'escritorio'
     )
     OR (
       kind = 'obra'
       AND dest IS NULL
     )
     OR (
       kind <> 'obra'
       AND (
         dest IS NOT NULL
         OR description IS NULL
       )
     )
  THEN
    RAISE EXCEPTION 'Destino inválido.';
  END IF;

  IF kind = 'obra' THEN
    description := NULL;
  END IF;

  IF dest IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.obras o
       WHERE o.id = dest
         AND o.empresa_id = u.empresa_id
     )
  THEN
    RAISE EXCEPTION 'Destino de outra empresa.'
    USING ERRCODE = '42501';
  END IF;

  IF p_acao = 'minha_obra'
     AND (
       kind <> 'obra'
       OR NOT public.fn_quadro_minha_obra(dest)
     )
  THEN
    RAISE EXCEPTION
      'Só pode adicionar à obra em que é Encarregado.'
    USING ERRCODE = '42501';
  END IF;

  IF p_acao <> 'remover'
     AND EXISTS (
       SELECT 1
       FROM public.ausencias a
       WHERE a.colaborador_id = person
         AND a.data = day
     )
  THEN
    RAISE EXCEPTION
      'Este colaborador está de férias/ausente nesta data.';
  END IF;

  SELECT coalesce(
           jsonb_agg(
             to_jsonb(q)
             ORDER BY q.id
           ),
           '[]'::jsonb
         )
  INTO rows_before
  FROM public.quadro_pessoal_alocacao q
  WHERE q.colaborador_id = person
    AND q.data = day
    AND (
      q.periodo = period
      OR q.periodo = 'dia_inteiro'
      OR period = 'dia_inteiro'
    );

  IF p_acao = 'minha_obra' THEN

    IF EXISTS (
      SELECT 1
      FROM public.quadro_pessoal_alocacao q
      WHERE q.colaborador_id = person
        AND q.data = day
        AND q.periodo = period
        AND q.obra_id = dest
        AND q.tipo_alocacao = 'obra'
        AND q.descricao_livre IS NULL
    )
    THEN
      RAISE EXCEPTION
        'Destino já existente: nenhuma origem foi removida.';
    END IF;

    n := jsonb_array_length(rows_before);

    IF n > 1 THEN
      RAISE EXCEPTION
        'Várias origens: peça a resolução ao ADM/Gestão. Nada foi alterado.';
    END IF;

    IF n = 1 THEN

      SELECT *
      INTO src
      FROM jsonb_populate_record(
        NULL::public.quadro_pessoal_alocacao,
        rows_before->0
      );

      IF src.periodo <> period THEN
        RAISE EXCEPTION
          'Sobreposição parcial: peça a resolução ao ADM/Gestão.';
      END IF;

      sid := src.id;

    END IF;

  END IF;

  IF p_acao <> 'remover'
     AND EXISTS (
       SELECT 1
       FROM public.quadro_pessoal_alocacao q
       WHERE q.colaborador_id = person
         AND q.data = day
         AND q.periodo = period
         AND q.obra_id IS NOT DISTINCT FROM dest
         AND q.tipo_alocacao = kind
         AND q.descricao_livre IS NOT DISTINCT FROM description
         AND q.id IS DISTINCT FROM sid
     )
  THEN
    RAISE EXCEPTION 'Alocação idêntica já existente.'
    USING ERRCODE = '23505';
  END IF;

  v_version := md5(
    jsonb_build_object(
      'linhas', rows_before,
      'origem', to_jsonb(src),
      'dados', p_dados,
      'acao', p_acao
    )::text
  );

  result := jsonb_build_object(
    'versao', v_version,
    'colaborador', c.nome,
    'origem_id', sid,
    'obra_origem_id', src.obra_id,
    'obra_destino_id', dest,
    'data', day,
    'periodo', period,
    'acao',
      CASE
        WHEN p_acao = 'minha_obra'
          THEN CASE
                 WHEN sid IS NULL THEN 'adicionar'
                 ELSE 'mover'
               END
        ELSE p_acao
      END
  );

  IF NOT p_confirmar THEN
    RETURN result
      || jsonb_build_object(
           'estado',
           'PREVISUALIZACAO'
         );
  END IF;

  IF p_versao IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION
      'Pré-visualização desatualizada. Consulte novamente.';
  END IF;

  IF NOT manage THEN

    INSERT INTO public.quadro_pessoal_rpc_permit
    VALUES (
      txid_current(),
      u.id,
      person,
      sid,
      dest,
      day,
      period
    );

  END IF;

  IF p_acao = 'remover' THEN

    DELETE FROM public.quadro_pessoal_alocacao
    WHERE id = sid;

    result_id := sid;

  ELSIF sid IS NOT NULL THEN

    UPDATE public.quadro_pessoal_alocacao
    SET
      obra_id = dest,
      data = day,
      periodo = period,
      semana_inicio =
        date_trunc(
          'week',
          day::timestamp
        )::date,
      tipo_alocacao = kind,
      descricao_livre = description
    WHERE id = sid
    RETURNING id INTO result_id;

  ELSE

    INSERT INTO public.quadro_pessoal_alocacao (
      colaborador_id,
      obra_id,
      data,
      periodo,
      semana_inicio,
      tipo_alocacao,
      descricao_livre,
      criado_por
    )
    VALUES (
      person,
      dest,
      day,
      period,
      date_trunc(
        'week',
        day::timestamp
      )::date,
      kind,
      description,
      u.id
    )
    RETURNING id INTO result_id;

  END IF;

  DELETE FROM public.quadro_pessoal_rpc_permit
  WHERE transacao = txid_current()
    AND utilizador_id = u.id;

  RETURN result
    || jsonb_build_object(
         'estado',
         'GUARDADO',
         'alocacao_id',
         result_id
       );

END
$function$;

CREATE OR REPLACE FUNCTION public.fn_verificar_fatura_semelhante(p_fornecedor_id uuid, p_valor numeric, p_numero_doc text, p_excluir_fatura_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, obra_id uuid, obra_numero text, numero_doc text, valor numeric, data_fatura date, estado_aprovacao text, estado_pagamento text, tipo_correspondencia text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_atual public.utilizadores;
  v_tolerancia numeric;
begin
  IF NOT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id()
    AND u.ativo IS TRUE AND u.funcao IN('gestao_plataforma','administrativo','gerencia','financeiro','diretor_obra','adjunto','preparador')) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: pesquisa financeira não autorizada.' USING ERRCODE='42501';
  END IF;
  select * into v_atual
  from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id()
    and coalesce(u.ativo, true);

  if not found then
    raise exception 'Utilizador autenticado sem perfil ativo.';
  end if;

  if p_fornecedor_id is null or p_valor is null or p_valor < 0 then
    raise exception 'Fornecedor e valor são obrigatórios para verificar duplicados.';
  end if;

  v_tolerancia := greatest(1.00, abs(p_valor) * 0.005);

  return query
  select
    f.id,
    f.obra_id,
    o.numero::text,
    f.numero_doc,
    f.valor,
    f.data_fatura,
    f.estado_aprovacao,
    f.estado_pagamento,
    case
      when lower(btrim(f.numero_doc)) =
           lower(btrim(coalesce(p_numero_doc, '')))
        then 'exata'::text
      else 'semelhante'::text
    end
  from public.faturas f
  join public.obras o on o.id = f.obra_id
  where (public.fn_e_administrativo() OR public.fn_e_financeiro() OR public.fn_pode_ver_obra(f.obra_id))
    AND o.empresa_id=v_atual.empresa_id
    and f.fornecedor_id = p_fornecedor_id
    and f.id is distinct from p_excluir_fatura_id
    and (
      lower(btrim(f.numero_doc)) =
        lower(btrim(coalesce(p_numero_doc, '')))
      or abs(f.valor - p_valor) <= v_tolerancia
    )
  order by
    case
      when lower(btrim(f.numero_doc)) =
           lower(btrim(coalesce(p_numero_doc, '')))
      then 0
      else 1
    end,
    abs(f.valor - p_valor),
    f.data_fatura desc,
    f.criado_em desc
  limit 1;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_verificar_fatura_semelhante(p_fornecedor_id uuid, p_valor numeric, p_numero_doc text, p_obra_id uuid, p_excluir_fatura_id uuid)
 RETURNS TABLE(id uuid, obra_id uuid, obra_numero text, numero_doc text, valor numeric, data_fatura date, estado_aprovacao text, estado_pagamento text, tipo_correspondencia text, outra_obra boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_atual public.utilizadores; v_tolerancia numeric;
begin
  IF NOT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id()
    AND u.ativo IS TRUE AND u.funcao IN('gestao_plataforma','administrativo','gerencia','financeiro','diretor_obra','adjunto','preparador')) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: pesquisa financeira não autorizada.' USING ERRCODE='42501';
  END IF;
  select * into v_atual from public.utilizadores u
  where u.id=public.fn_utilizador_atual_id() and coalesce(u.ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.'; end if;
  if p_fornecedor_id is null or p_valor is null or p_valor<0 then
    raise exception 'Fornecedor e valor sÃ£o obrigatÃ³rios para verificar duplicados.';
  end if;
  v_tolerancia:=greatest(1.00,abs(p_valor)*0.005);
  return query
  select f.id,f.obra_id,o.numero::text,f.numero_doc,f.valor,f.data_fatura,
    f.estado_aprovacao,f.estado_pagamento,
    case when lower(btrim(f.numero_doc))=lower(btrim(coalesce(p_numero_doc,''))) then 'exata' else 'semelhante' end::text,
    (f.obra_id is distinct from p_obra_id)
  from public.faturas f join public.obras o on o.id=f.obra_id
  where (public.fn_e_administrativo() OR public.fn_e_financeiro() OR public.fn_pode_ver_obra(f.obra_id))
    AND o.empresa_id=v_atual.empresa_id and f.fornecedor_id=p_fornecedor_id
    and f.id is distinct from p_excluir_fatura_id
    and (lower(btrim(f.numero_doc))=lower(btrim(coalesce(p_numero_doc,''))) or abs(f.valor-p_valor)<=v_tolerancia)
  order by
    case when lower(btrim(f.numero_doc))=lower(btrim(coalesce(p_numero_doc,''))) then 0 else 1 end,
    (f.obra_id is distinct from p_obra_id) desc,abs(f.valor-p_valor),f.data_fatura desc
  limit 5;
end;$function$;

CREATE OR REPLACE FUNCTION public.fn_custo_real_ligado(p_obra_id uuid, p_tee_id uuid DEFAULT NULL::uuid, p_item_id uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_table text;
  v_total numeric := 0;
  v_part numeric;
begin
  IF NOT EXISTS(SELECT 1 FROM public.utilizadores u JOIN public.obras o ON o.empresa_id=u.empresa_id
    WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND o.id=p_obra_id
      AND (public.fn_e_administrativo() OR public.fn_e_financeiro() OR public.fn_pode_ver_obra(o.id))) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: custos fora do âmbito autorizado.' USING ERRCODE='42501';
  END IF;
  foreach v_table in array array[
    'lancamentos_materiais',
    'lancamentos_mao_obra',
    'despesas_estaleiro'
  ]
  loop
    if to_regclass('public.' || v_table) is null then
      continue;
    end if;

    execute format(
      'select coalesce(
         sum(public.fn_valor_lancamento_custo(to_jsonb(t))),
         0
       )
       from public.%I t
       where t.obra_id = $1
         and ($2 is null or t.tee_id = $2)
         and ($3 is null or t.item_orcamento_id = $3)',
      v_table
    )
    into v_part
    using p_obra_id, p_tee_id, p_item_id;

    v_total := v_total + coalesce(v_part, 0);
  end loop;

  return v_total;
end;
$function$;

-- Mesma regra de equipa atual já usada pela Medicina; sem nova temporalidade.
CREATE FUNCTION public.fn_ausencias_equipa_encarregado(p_inicio date,p_fim date)
RETURNS TABLE(id uuid,colaborador_id uuid,data date,tipo text,estado text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE u public.utilizadores;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE utilizadores.id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.funcao<>'encarregado' OR NOT EXISTS(
  SELECT 1 FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_minha_obra(o.id)
 ) THEN RAISE EXCEPTION 'PERMISSION_DENIED: equipa indisponível.' USING ERRCODE='42501'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>93 THEN
  RAISE EXCEPTION 'VALIDATION_ERROR: intervalo inválido.';
 END IF;
 RETURN QUERY SELECT a.id,a.colaborador_id,a.data,
  CASE WHEN a.tipo='ferias' THEN 'ferias'::text ELSE 'ausencia'::text END,a.estado
 FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id
 WHERE c.empresa_id=u.empresa_id AND c.data_saida IS NULL
 AND public.fn_colaborador_na_obra_atual_encarregado(c.id)
 AND a.data BETWEEN p_inicio AND p_fim ORDER BY a.data,a.id;
END $function$;
REVOKE ALL ON FUNCTION public.fn_ausencias_equipa_encarregado(date,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_ausencias_equipa_encarregado(date,date) TO authenticated;

-- Sessão derivada de auth.uid(); não utiliza empresa enviada pelo cliente.
CREATE FUNCTION public.fn_autorizacao_sessao_ativa()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.auth_user_id=auth.uid() AND u.ativo IS TRUE);
$function$;
ALTER FUNCTION public.fn_autorizacao_sessao_ativa() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_autorizacao_sessao_ativa() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_autorizacao_sessao_ativa() TO authenticated;

-- Helper interno. A obra provém do registo bloqueado pela RPC, nunca de prova do cliente.
CREATE FUNCTION public.fn_economico_ator_atual()
RETURNS public.utilizadores LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE u public.utilizadores;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE auth_user_id=auth.uid() AND ativo IS TRUE FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN
  RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
 END IF;
 RETURN u;
END $function$;
ALTER FUNCTION public.fn_economico_ator_atual() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_economico_ator_atual() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.fn_financeiro_autorizar_obra(p_obra_id uuid,p_pagamento boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE u public.utilizadores; empresa uuid;
BEGIN
 u:=public.fn_economico_ator_atual();
 IF u.id IS NULL OR u.empresa_id IS NULL THEN
  RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
 END IF;
 SELECT empresa_id INTO empresa FROM public.obras WHERE id=p_obra_id FOR SHARE;
 IF empresa IS NULL OR empresa IS DISTINCT FROM u.empresa_id THEN
  RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
 END IF;
 IF p_pagamento IS DISTINCT FROM false AND NOT public.fn_e_financeiro() THEN
  RAISE EXCEPTION 'FORBIDDEN: pagamento reservado ao papel autorizado.' USING ERRCODE='42501';
 END IF;
 RETURN u.id;
END $function$;
ALTER FUNCTION public.fn_financeiro_autorizar_obra(uuid,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_financeiro_autorizar_obra(uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE POLICY alertas_sessao_ativa ON public.alertas AS RESTRICTIVE FOR SELECT TO authenticated
USING(public.fn_autorizacao_sessao_ativa());
CREATE OR REPLACE FUNCTION public.fn_marcar_fatura_paga(p_fatura_id uuid, p_data_pagamento date DEFAULT CURRENT_DATE)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  if not public.fn_e_financeiro() then
    raise exception 'O pagamento está reservado ao papel Financeiro.' USING ERRCODE='42501';
  end if;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,true);


  if not found
     or v_fatura.estado_aprovacao <> 'aprovado'
     or v_fatura.estado_pagamento <> 'por_pagar' then
    raise exception 'A fatura não está disponível para pagamento.';
  end if;

  update public.faturas
  set estado_pagamento = 'pago',
      pago_por = public.fn_utilizador_atual_id(),
      data_pagamento = coalesce(p_data_pagamento, current_date)
  where id = p_fatura_id
  returning * into v_fatura;
  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_marcar_fatura_paga(uuid,date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_marcar_fatura_paga(uuid,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_marcar_fatura_paga(uuid,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_desmarcar_fatura_paga(p_fatura_id uuid)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  if not public.fn_e_financeiro() then
    raise exception
      'A reversão do pagamento está reservada ao papel Financeiro.' USING ERRCODE='42501';
  end if;

  select *
  into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,true);


  if not found
    or v_fatura.estado_aprovacao <> 'aprovado'
    or v_fatura.estado_pagamento <> 'pago' then

    raise exception 'Esta fatura não está marcada como paga.';
  end if;

  update public.faturas
  set
    estado_pagamento = 'por_pagar',
    data_pagamento = null,
    pago_por = null
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_desmarcar_fatura_paga(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_desmarcar_fatura_paga(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_desmarcar_fatura_paga(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_devolver_fatura_financeiro(p_fatura_id uuid, p_observacao text)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  if not public.fn_e_financeiro() then
    raise exception
      'A devolução está reservada ao papel Financeiro.' USING ERRCODE='42501';
  end if;

  if nullif(btrim(p_observacao), '') is null then
    raise exception
      'A observação é obrigatória para devolver a fatura.';
  end if;

  select *
  into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,true);


  if not found
    or v_fatura.estado_aprovacao <> 'aprovado'
    or v_fatura.estado_pagamento <> 'por_pagar' then

    raise exception
      'Só pode devolver uma fatura aprovada que ainda não foi paga.';
  end if;

  update public.faturas
  set
    estado_aprovacao = 'pendente',
    observacao_devolucao = btrim(p_observacao),
    devolvido_por = public.fn_utilizador_atual_id(),
    devolvido_em = now(),
    aprovado_por = null,
    data_aprovacao = null
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_devolver_fatura_financeiro(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_devolver_fatura_financeiro(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_devolver_fatura_financeiro(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_avancar_estado_fluxo_fatura(p_fatura_id uuid, p_novo_estado text, p_data_pagamento date DEFAULT NULL::date, p_observacao text DEFAULT NULL::text)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
  v_ordem constant text[] := array[
    'recebida',
    'em_validacao',
    'aprovada_tecnicamente',
    'enviada_financeiro',
    'paga'
  ];
  v_sem_guia boolean := false;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,p_novo_estado = 'paga');


  if not found then
    raise exception 'Fatura não encontrada.';
  end if;

  if array_position(v_ordem, p_novo_estado) is null
     or array_position(v_ordem, p_novo_estado)
        <> array_position(v_ordem, v_fatura.estado_fluxo) + 1 then
    raise exception 'A fatura deve seguir os cinco estados pela ordem definida.';
  end if;

  if p_novo_estado = 'paga' then
    if not public.fn_e_financeiro() then
      raise exception 'Só o Financeiro pode marcar a fatura como paga.'
        using errcode = '42501';
    end if;
  elsif not (
    public.fn_pode_editar_obra(v_fatura.obra_id)
    or public.fn_e_admin()
  ) then
    raise exception 'Sem permissão para avançar a validação desta fatura.'
      using errcode = '42501';
  end if;

  if p_novo_estado = 'aprovada_tecnicamente' then
    v_sem_guia := not exists (
      select 1
      from public.faturas_guias
      where fatura_id = p_fatura_id
    );
  end if;

  update public.faturas
  set
    estado_fluxo = p_novo_estado,

    estado_aprovacao = case
      when p_novo_estado in (
        'aprovada_tecnicamente',
        'enviada_financeiro',
        'paga'
      ) then 'aprovado'
      else 'pendente'
    end,

    estado_pagamento = case
      when p_novo_estado = 'paga' then 'pago'
      else 'por_pagar'
    end,

    data_aprovacao = case
      when p_novo_estado = 'aprovada_tecnicamente' then now()
      else data_aprovacao
    end,

    aprovado_por = case
      when p_novo_estado = 'aprovada_tecnicamente'
        then public.fn_utilizador_atual_id()
      else aprovado_por
    end,

    observacao = case
      when p_novo_estado = 'aprovada_tecnicamente'
           and p_observacao is not null
        then nullif(btrim(p_observacao), '')
      else observacao
    end,

    aprovada_sem_guia = case
      when p_novo_estado = 'aprovada_tecnicamente' then v_sem_guia
      else aprovada_sem_guia
    end,

    data_pagamento = case
      when p_novo_estado = 'paga'
        then coalesce(p_data_pagamento, data_pagamento, current_date)
      else data_pagamento
    end

  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_marcar_faturacao_auto_paga(p_faturacao_id uuid, p_data_pagamento date, p_valor_pago numeric)
 RETURNS faturacao
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_faturacao public.faturacao;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  if not public.fn_e_financeiro() then
    raise exception 'O pagamento está reservado ao papel Financeiro.' USING ERRCODE='42501';
  end if;

  select * into v_faturacao
  from public.faturacao
  where id = p_faturacao_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_faturacao.obra_id,true);


  if not found
     or v_faturacao.estado_aprovacao <> 'aprovado'
     or v_faturacao.estado_pagamento <> 'por_pagar' then
    raise exception 'A fatura não está aprovada ou já foi paga.';
  end if;

  if coalesce(p_valor_pago, 0) <= 0 then
    raise exception 'O valor pago tem de ser superior a zero.';
  end if;

  update public.faturacao
  set estado_pagamento = 'pago',
      pago_por = public.fn_utilizador_atual_id(),
      data_pagamento = coalesce(p_data_pagamento, current_date),
      data_recebimento = coalesce(p_data_pagamento, current_date),
      valor_recebido = p_valor_pago
  where id = p_faturacao_id
  returning * into v_faturacao;

  return v_faturacao;
end;
$function$;
ALTER FUNCTION public.fn_marcar_faturacao_auto_paga(uuid,date,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_marcar_faturacao_auto_paga(uuid,date,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_marcar_faturacao_auto_paga(uuid,date,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_registar_recebimento_parcial(p_version integer, p_faturacao_id uuid, p_data date, p_valor numeric, p_request_id text, p_valor_recebido_esperado numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_faturacao public.faturacao%rowtype;
  v_movimento public.faturacao_recebimentos%rowtype;
  v_utilizador uuid;
  v_obra_id uuid;
  v_recebido_atual numeric(14,2);
  v_novo_total numeric(14,2);
BEGIN
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  IF p_version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: versão de contrato inválida.';
  END IF;

  IF NOT public.fn_e_financeiro() THEN
    RAISE EXCEPTION
      'FORBIDDEN: operação reservada ao Financeiro.' USING ERRCODE='42501';
  END IF;

  IF p_faturacao_id IS NULL
     OR p_data IS NULL
     OR COALESCE(p_valor, 0) <= 0
     OR NULLIF(btrim(p_request_id), '') IS NULL THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: faturação, data, valor e request_id são obrigatórios.';
  END IF;

  v_utilizador := public.fn_utilizador_atual_id();

  SELECT obra_id INTO v_obra_id FROM public.faturacao WHERE id=p_faturacao_id FOR UPDATE;
  PERFORM public.fn_financeiro_autorizar_obra(v_obra_id,true);

  -- ----------------------------------------------------------
  -- Idempotência:
  -- se o mesmo request já foi aplicado com o mesmo conteúdo,
  -- devolver sucesso sem criar nova parcela.
  -- ----------------------------------------------------------
  SELECT *
  INTO v_movimento
  FROM public.faturacao_recebimentos
  WHERE request_id = p_request_id;

  IF FOUND THEN
    IF v_movimento.faturacao_id IS DISTINCT FROM p_faturacao_id
       OR v_movimento.data_recebimento IS DISTINCT FROM p_data
       OR v_movimento.valor IS DISTINCT FROM round(p_valor, 2) THEN
      RAISE EXCEPTION
        'IDEMPOTENCY_CONFLICT: request_id já utilizado com conteúdo diferente.';
    END IF;

    SELECT *
    INTO v_faturacao
    FROM public.faturacao
    WHERE id = p_faturacao_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: faturação não encontrada.';
    END IF;

    RETURN jsonb_build_object(
      'version', 1,
      'committed', true,
      'billing', to_jsonb(v_faturacao)
    );
  END IF;

  -- ----------------------------------------------------------
  -- Lock do documento
  -- ----------------------------------------------------------
  SELECT *
  INTO v_faturacao
  FROM public.faturacao
  WHERE id = p_faturacao_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: faturação não encontrada.';
  END IF;

  IF v_faturacao.estado_aprovacao <> 'aprovado' THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: faturação ainda não está aprovada.';
  END IF;

  v_recebido_atual := round(COALESCE(v_faturacao.valor_recebido, 0), 2);

  -- ----------------------------------------------------------
  -- Concorrência otimista
  -- ----------------------------------------------------------
  IF v_recebido_atual IS DISTINCT FROM
     round(COALESCE(p_valor_recebido_esperado, 0), 2) THEN
    RAISE EXCEPTION
      'STALE_REVISION: o valor já recebido foi alterado. Atualize a faturação.';
  END IF;

  v_novo_total :=
    round(v_recebido_atual + round(p_valor, 2), 2);

  IF v_novo_total > round(v_faturacao.valor, 2) THEN
    RAISE EXCEPTION
      'AMOUNT_EXCEEDS_BALANCE: a parcela excede o saldo por receber.';
  END IF;

  -- ----------------------------------------------------------
  -- Movimento imutável
  -- ----------------------------------------------------------
  INSERT INTO public.faturacao_recebimentos (
    faturacao_id,
    request_id,
    data_recebimento,
    valor,
    registado_por
  )
  VALUES (
    p_faturacao_id,
    p_request_id,
    p_data,
    round(p_valor, 2),
    v_utilizador
  )
  RETURNING *
  INTO v_movimento;

  -- ----------------------------------------------------------
  -- Mantém os campos agregados legados sincronizados,
  -- mas a nova origem rastreável é a tabela de movimentos.
  --
  -- Parcial continua "por_pagar" porque o check atual da
  -- faturacao só suporta por_pagar/pago.
  -- ----------------------------------------------------------
  UPDATE public.faturacao
  SET
    valor_recebido = v_novo_total,

    data_recebimento = p_data,

    estado_pagamento =
      CASE
        WHEN v_novo_total = round(valor, 2)
          THEN 'pago'
        ELSE 'por_pagar'
      END,

    estado =
      CASE
        WHEN v_novo_total = round(valor, 2)
          THEN 'pago'
        WHEN estado = 'pago'
          THEN 'emitida'
        ELSE estado
      END,

    data_pagamento =
      CASE
        WHEN v_novo_total = round(valor, 2)
          THEN p_data
        ELSE NULL
      END,

    pago_por =
      CASE
        WHEN v_novo_total = round(valor, 2)
          THEN v_utilizador
        ELSE NULL
      END

  WHERE id = p_faturacao_id
  RETURNING *
  INTO v_faturacao;

  RETURN jsonb_build_object(
    'version', 1,
    'committed', true,
    'billing', to_jsonb(v_faturacao)
  );
END;
$function$;
ALTER FUNCTION public.fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_resolver_alerta(p_alerta_id uuid)
 RETURNS alertas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_alerta public.alertas;
  v_utilizador_id uuid;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
    RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  v_utilizador_id := public.fn_utilizador_atual_id();

  if v_utilizador_id is null then
    raise exception 'Sessão autenticada sem utilizador associado.';
  end if;

  select *
  into v_alerta
  from public.alertas
  where id = p_alerta_id
  for update;

  if not found then
    raise exception 'Alerta não encontrado.';
  end if;

  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
    or (
      public.fn_e_financeiro()
      and v_alerta.destinatario_role in ('financeiro', 'tesouraria')
    )
    or (
      v_alerta.obra_id is not null
      and public.fn_pode_editar_obra(v_alerta.obra_id)
    )
  ) then
    raise exception 'Sem permissão para resolver este alerta.';
  end if;

  if v_alerta.estado <> 'resolvido' then
    update public.alertas
    set estado = 'resolvido',
        resolvido_por = v_utilizador_id,
        resolvido_em = now()
    where id = p_alerta_id
    returning * into v_alerta;
  end if;

  return v_alerta;
end;
$function$;
ALTER FUNCTION public.fn_resolver_alerta(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_resolver_alerta(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_resolver_alerta(uuid) TO authenticated;


CREATE OR REPLACE FUNCTION public.fn_decidir_fatura(p_fatura_id uuid, p_decisao text, p_observacao text DEFAULT NULL::text)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
  v_sem_guia boolean := false;
  v_bloquear_sem_guia constant boolean := false;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  if p_decisao not in ('aprovado', 'recusado') then
    raise exception 'Decisão inválida.';
  end if;

  select *
  into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,false);


  if not found
    or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente.';
  end if;

  if not public.fn_pode_editar_obra(v_fatura.obra_id) then
    raise exception 'Sem permissão para decidir esta fatura.';
  end if;

  if p_decisao = 'aprovado' then
    v_sem_guia := not exists (
      select 1
      from public.faturas_guias
      where fatura_id = p_fatura_id
    );
  end if;

  if v_bloquear_sem_guia
    and p_decisao = 'aprovado'
    and v_sem_guia then
    raise exception
      'É obrigatório anexar pelo menos uma guia antes da aprovação.';
  end if;

  update public.faturas
  set
    estado_aprovacao = p_decisao,
    aprovado_por = null,
    data_aprovacao = now(),
    observacao = case
      when p_observacao is null
        then v_fatura.observacao
      else nullif(btrim(p_observacao), '')
    end,
    aprovada_sem_guia = case
      when p_decisao = 'aprovado'
        then v_sem_guia
      else false
    end
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_decidir_fatura(uuid,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_decidir_fatura(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_decidir_fatura(uuid,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_decidir_faturacao_auto(p_faturacao_id uuid, p_decisao text)
 RETURNS faturacao
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_faturacao public.faturacao;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  if p_decisao not in ('aprovado', 'recusado') then
    raise exception 'Decisão inválida.';
  end if;

  select * into v_faturacao
  from public.faturacao
  where id = p_faturacao_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_faturacao.obra_id,false);


  if not found or v_faturacao.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente.';
  end if;

  if not public.fn_pode_editar_obra(v_faturacao.obra_id) then
    raise exception 'Sem permissão para decidir esta fatura.';
  end if;

  update public.faturacao
  set estado_aprovacao = p_decisao,
      estado = case
        when p_decisao = 'aprovado' then 'emitida'
        else 'rascunho'
      end,
      aprovado_por = public.fn_utilizador_atual_id(),
      data_aprovacao = now()
  where id = p_faturacao_id
  returning * into v_faturacao;

  return v_faturacao;
end;
$function$;
ALTER FUNCTION public.fn_decidir_faturacao_auto(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_decidir_faturacao_auto(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_decidir_faturacao_auto(uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_devolver_fatura_administrativo(p_fatura_id uuid, p_observacao text)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
  v_funcao text;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select funcao into v_funcao
  from public.utilizadores
  where id = public.fn_utilizador_atual_id()
    and coalesce(ativo, true);

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,false);


  if not found then
    raise exception 'Fatura nÃ£o encontrada.' using errcode = 'P0002';
  end if;
  if not (public.fn_e_admin() or v_funcao in ('diretor_obra', 'adjunto'))
     or not (public.fn_e_admin() or public.fn_pode_editar_obra(v_fatura.obra_id)) then
    raise exception 'A devoluÃ§Ã£o estÃ¡ reservada ao Diretor ou Adjunto responsÃ¡vel pela obra.' using errcode = '42501';
  end if;
  if nullif(btrim(p_observacao), '') is null then
    raise exception 'A nota Ã© obrigatÃ³ria para devolver a fatura.';
  end if;
  if v_fatura.estado_fluxo not in ('recebida', 'em_validacao', 'aprovada_tecnicamente')
     or v_fatura.estado_pagamento = 'pago' then
    raise exception 'Esta fatura jÃ¡ nÃ£o pode ser devolvida ao Administrativo.';
  end if;

  update public.faturas
  set estado_fluxo = 'devolvida_administrativo',
      estado_aprovacao = 'pendente',
      estado_pagamento = 'por_pagar',
      observacao_devolucao = btrim(p_observacao),
      devolvido_por = public.fn_utilizador_atual_id(),
      devolvido_em = now(),
      aprovado_por = null,
      data_aprovacao = null,
      aprovada_sem_guia = false
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_devolver_fatura_administrativo(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_devolver_fatura_administrativo(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_devolver_fatura_administrativo(uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_vincular_fatura_subempreitada(p_fatura_id uuid, p_subempreitada_id uuid)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,false);


  if not found then
    raise exception 'A fatura selecionada nÃ£o existe.';
  end if;
  if v_fatura.tipo_origem <> 'subempreitada' then
    raise exception 'SÃ³ as faturas de subempreitada podem ser vinculadas a um trabalho.';
  end if;
  if v_fatura.estado_fluxo not in ('recebida', 'em_validacao') then
    raise exception 'O vÃ­nculo sÃ³ pode ser alterado antes da aprovaÃ§Ã£o tÃ©cnica.';
  end if;
  if not (public.fn_pode_editar_obra(v_fatura.obra_id) or public.fn_e_admin()) then
    raise exception 'SÃ³ a equipa tÃ©cnica responsÃ¡vel pela obra pode confirmar este vÃ­nculo.' using errcode = '42501';
  end if;
  if p_subempreitada_id is not null and not exists (
    select 1
    from public.subempreitadas s
    where s.id = p_subempreitada_id
      and s.obra_id = v_fatura.obra_id
      and s.fornecedor_id = v_fatura.fornecedor_id
  ) then
    raise exception 'O trabalho selecionado nÃ£o pertence simultaneamente a esta obra e a este fornecedor.';
  end if;

  update public.faturas
  set subempreitada_id = p_subempreitada_id
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_vincular_fatura_subempreitada(uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_vincular_fatura_subempreitada(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_vincular_fatura_subempreitada(uuid,uuid) TO authenticated;

-- Fecha o mesmo efeito pelo REST direto; não altera SELECT financeiro legado.
CREATE FUNCTION public.fn_financeiro_obra_da_empresa(p_obra_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u JOIN public.obras o ON o.empresa_id=u.empresa_id
 WHERE u.auth_user_id=auth.uid() AND u.ativo IS TRUE AND o.id=p_obra_id);
$function$;
ALTER FUNCTION public.fn_financeiro_obra_da_empresa(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_financeiro_obra_da_empresa(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_financeiro_obra_da_empresa(uuid) TO authenticated;
CREATE POLICY financeiro_empresa_insert ON public.faturas AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(public.fn_financeiro_obra_da_empresa(obra_id));
CREATE POLICY financeiro_empresa_delete ON public.faturas AS RESTRICTIVE FOR DELETE TO authenticated
USING(public.fn_financeiro_obra_da_empresa(obra_id));
CREATE POLICY financeiro_empresa_insert ON public.faturacao AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(public.fn_financeiro_obra_da_empresa(obra_id));
CREATE POLICY financeiro_empresa_delete ON public.faturacao AS RESTRICTIVE FOR DELETE TO authenticated
USING(public.fn_financeiro_obra_da_empresa(obra_id));

CREATE OR REPLACE FUNCTION public.fn_editar_fatura_pendente(p_fatura_id uuid, p_obra_id uuid, p_tipo_origem text, p_fornecedor_id uuid, p_subempreitada_id uuid, p_numero_doc text, p_data_fatura date, p_valor numeric, p_condicao_pagamento text, p_data_vencimento date, p_itens jsonb DEFAULT '[]'::jsonb)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_item jsonb;
  v_quantidade numeric;
  v_valor_unitario numeric;
  v_valor_total numeric;
  v_desconto_percentual numeric;
  v_valor_desconto numeric;
  v_foi_devolvida boolean;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select * into v_fatura from public.faturas where id = p_fatura_id for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_fatura.obra_id,false);
  PERFORM public.fn_financeiro_autorizar_obra(p_obra_id,false);
  IF NOT EXISTS(SELECT 1 FROM public.fornecedores f JOIN public.obras o ON o.empresa_id=f.empresa_id WHERE f.id=p_fornecedor_id AND o.id=p_obra_id) THEN
   RAISE EXCEPTION 'FORBIDDEN: fornecedor indisponível.' USING ERRCODE='42501';
  END IF;

  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura jÃ¡ nÃ£o estÃ¡ pendente e nÃ£o pode ser editada.';
  end if;
  v_foi_devolvida := v_fatura.estado_fluxo = 'devolvida_administrativo';

  if not public.fn_e_admin()
     and not (public.fn_e_administrativo() and (
       v_foi_devolvida or (v_fatura.criado_por is not null and v_fatura.criado_por = v_utilizador_id)
     )) then
    raise exception 'SÃ³ o Administrativo responsÃ¡vel pela correÃ§Ã£o ou a GerÃªncia pode editar esta fatura.';
  end if;

  if p_obra_id is null or p_fornecedor_id is null
     or nullif(btrim(p_numero_doc), '') is null or p_data_fatura is null
     or p_valor is null or p_valor <= 0 then
    raise exception 'Preencha obra, fornecedor, nÃºmero, data e valor da fatura.';
  end if;
  if p_tipo_origem not in ('subempreitada', 'material', 'estaleiro') then
    raise exception 'Tipo de despesa invÃ¡lido.';
  end if;
  if p_condicao_pagamento not in ('imediato', '15_dias', '30_dias', 'outra_data') then
    raise exception 'CondiÃ§Ã£o de pagamento invÃ¡lida.';
  end if;
  if p_condicao_pagamento = 'outra_data' and p_data_vencimento is null then
    raise exception 'Indique a data de vencimento para a opÃ§Ã£o Outra data.';
  end if;
  if p_condicao_pagamento <> 'outra_data' and p_data_vencimento is not null then
    raise exception 'A data manual sÃ³ pode ser usada com a opÃ§Ã£o Outra data.';
  end if;
  if p_tipo_origem = 'subempreitada' and p_subempreitada_id is not null and not exists (
    select 1 from public.subempreitadas s
    where s.id = p_subempreitada_id and s.obra_id = p_obra_id
      and s.fornecedor_id = p_fornecedor_id
  ) then
    raise exception 'A subempreitada nÃ£o corresponde Ã  obra e ao fornecedor selecionados.';
  elsif p_tipo_origem <> 'subempreitada' and p_subempreitada_id is not null then
    raise exception 'Faturas de material ou estaleiro nÃ£o podem ter subempreitada associada.';
  end if;

  update public.faturas
  set obra_id = p_obra_id,
      tipo_origem = p_tipo_origem,
      fornecedor_id = p_fornecedor_id,
      subempreitada_id = p_subempreitada_id,
      numero_doc = btrim(p_numero_doc),
      data_fatura = p_data_fatura,
      valor = p_valor,
      condicao_pagamento = p_condicao_pagamento,
      data_vencimento = case when p_condicao_pagamento = 'outra_data' then p_data_vencimento else null end,
      estado_fluxo = case when v_foi_devolvida then 'recebida' else estado_fluxo end,
      observacao_devolucao = case when v_foi_devolvida then null else observacao_devolucao end,
      devolvido_por = case when v_foi_devolvida then null else devolvido_por end,
      devolvido_em = case when v_foi_devolvida then null else devolvido_em end
  where id = p_fatura_id
  returning * into v_fatura;

  delete from public.faturas_itens where fatura_id = p_fatura_id;
  if p_tipo_origem = 'material' then
    if jsonb_typeof(coalesce(p_itens, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) = 0 then
      raise exception 'Uma fatura de material exige pelo menos um artigo.';
    end if;
    for v_item in select value from jsonb_array_elements(p_itens)
    loop
      v_quantidade := nullif(v_item ->> 'quantidade', '')::numeric;
      v_valor_unitario := nullif(v_item ->> 'valor_unitario', '')::numeric;
      v_valor_total := nullif(v_item ->> 'valor_total', '')::numeric;
      v_desconto_percentual := nullif(v_item ->> 'desconto_percentual', '')::numeric;
      v_valor_desconto := nullif(v_item ->> 'valor_desconto', '')::numeric;
      if nullif(btrim(v_item ->> 'designacao'), '') is null
         or nullif(btrim(v_item ->> 'unidade'), '') is null
         or v_quantidade is null or v_quantidade <= 0
         or v_valor_unitario is null or v_valor_unitario < 0
         or v_valor_total is null or v_valor_total < 0
         or (v_desconto_percentual is not null and (v_desconto_percentual < 0 or v_desconto_percentual > 100))
         or (v_valor_desconto is not null and v_valor_desconto < 0) then
        raise exception 'Existe um artigo de material incompleto ou invÃ¡lido.';
      end if;
      insert into public.faturas_itens (
        fatura_id, designacao, unidade, quantidade, valor_unitario, valor_total,
        desconto_percentual, valor_desconto
      ) values (
        p_fatura_id, btrim(v_item ->> 'designacao'), btrim(v_item ->> 'unidade'),
        v_quantidade, v_valor_unitario, v_valor_total,
        v_desconto_percentual, v_valor_desconto
      );
    end loop;
  end if;
  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_editar_fatura_pendente(p_fatura_id uuid, p_obra_id uuid, p_tipo_origem text, p_fornecedor_id uuid, p_subempreitada_id uuid, p_numero_doc text, p_data_fatura date, p_valor numeric, p_condicao_pagamento text, p_data_vencimento date, p_observacao text, p_itens jsonb DEFAULT '[]'::jsonb)
 RETURNS faturas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fatura public.faturas;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  v_fatura := public.fn_editar_fatura_pendente(
    p_fatura_id,
    p_obra_id,
    p_tipo_origem,
    p_fornecedor_id,
    p_subempreitada_id,
    p_numero_doc,
    p_data_fatura,
    p_valor,
    p_condicao_pagamento,
    p_data_vencimento,
    p_itens
  );

  update public.faturas
  set observacao = nullif(btrim(p_observacao), '')
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;
ALTER FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_guia_fatura(p_guia_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_path text; v_obra uuid;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select g.arquivo_url,f.obra_id into v_path,v_obra from public.faturas_guias g join public.faturas f on f.id=g.fatura_id where g.id=p_guia_id FOR UPDATE OF f;
  PERFORM public.fn_financeiro_autorizar_obra(v_obra,false);

  if not found then raise exception 'Guia não encontrada.'; end if;
  if not (public.fn_pode_editar_obra(v_obra) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.faturas_guias where id=p_guia_id;
  return v_path;
end;
$function$;
ALTER FUNCTION public.fn_apagar_guia_fatura(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_guia_fatura(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_guia_fatura(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_fatura(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_path text; v_obra uuid;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select a.arquivo_url,f.obra_id into v_path,v_obra from public.faturas_anexos a join public.faturas f on f.id=a.fatura_id where a.id=p_anexo_id FOR UPDATE OF f;
  PERFORM public.fn_financeiro_autorizar_obra(v_obra,false);

  if not found then raise exception 'Anexo não encontrado.'; end if;
  if not (public.fn_pode_editar_obra(v_obra) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.faturas_anexos where id=p_anexo_id;
  return v_path;
end;
$function$;
ALTER FUNCTION public.fn_apagar_anexo_fatura(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_fatura(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_fatura(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_eliminar_mapa_comparativo(p_mapa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_obra_id uuid;
  v_item_ids uuid[];
  v_proposta_ids uuid[];
  v_itens_antes integer;
  v_propostas_antes integer;
  v_precos_antes integer;
  v_ajustes_antes integer;
  v_mapas_depois integer;
  v_itens_depois integer;
  v_propostas_depois integer;
  v_precos_depois integer;
  v_ajustes_depois integer;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select obra_id into v_obra_id
  from public.mapas_comparativos
  where id = p_mapa_id
  for update;
  PERFORM public.fn_financeiro_autorizar_obra(v_obra_id,false);


  if not found then
    raise exception 'Mapa comparativo não encontrado.'
      using errcode = 'P0002';
  end if;

  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para eliminar este mapa comparativo.'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.subempreitadas
    where mapa_comparativo_id = p_mapa_id
  ) then
    raise exception 'Este mapa já originou uma subempreitada e não pode ser eliminado. O histórico da adjudicação deve ser preservado.'
      using errcode = '23503';
  end if;

  select coalesce(array_agg(id), '{}'::uuid[]), count(*)
  into v_item_ids, v_itens_antes
  from public.comparativo_itens
  where mapa_id = p_mapa_id;

  select coalesce(array_agg(id), '{}'::uuid[]), count(*)
  into v_proposta_ids, v_propostas_antes
  from public.comparativo_propostas
  where mapa_id = p_mapa_id;

  select count(*) into v_precos_antes
  from public.comparativo_itens_precos
  where item_id = any(v_item_ids)
     or proposta_id = any(v_proposta_ids);

  select count(*) into v_ajustes_antes
  from public.comparativo_ajustes
  where mapa_id = p_mapa_id;

  delete from public.mapas_comparativos
  where id = p_mapa_id;

  select count(*) into v_mapas_depois
  from public.mapas_comparativos
  where id = p_mapa_id;

  select count(*) into v_itens_depois
  from public.comparativo_itens
  where id = any(v_item_ids);

  select count(*) into v_propostas_depois
  from public.comparativo_propostas
  where id = any(v_proposta_ids);

  select count(*) into v_precos_depois
  from public.comparativo_itens_precos
  where item_id = any(v_item_ids)
     or proposta_id = any(v_proposta_ids);

  select count(*) into v_ajustes_depois
  from public.comparativo_ajustes
  where mapa_id = p_mapa_id
     or proposta_id = any(v_proposta_ids);

  if v_mapas_depois <> 0
     or v_itens_depois <> 0
     or v_propostas_depois <> 0
     or v_precos_depois <> 0
     or v_ajustes_depois <> 0 then
    raise exception 'A eliminação foi cancelada: existem registos relacionados com o mapa.';
  end if;

  return jsonb_build_object(
    'mapa_id', p_mapa_id,
    'itens_eliminados', v_itens_antes,
    'propostas_eliminadas', v_propostas_antes,
    'precos_eliminados', v_precos_antes,
    'ajustes_eliminados', v_ajustes_antes,
    'mapas_restantes', v_mapas_depois,
    'itens_restantes', v_itens_depois,
    'propostas_restantes', v_propostas_depois,
    'precos_restantes', v_precos_depois,
    'ajustes_restantes', v_ajustes_depois
  );
end;
$function$;
ALTER FUNCTION public.fn_eliminar_mapa_comparativo(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_eliminar_mapa_comparativo(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_mapa_comparativo(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_eliminar_item_comparativo(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_mapa_id uuid;
  v_obra_id uuid;
  v_precos_antes integer;
  v_precos_depois integer;
begin
  IF NOT public.fn_autorizacao_sessao_ativa() THEN
   RAISE EXCEPTION 'FORBIDDEN: sessão ou entidade indisponível.' USING ERRCODE='42501';
  END IF;

  select i.mapa_id, m.obra_id
  into v_mapa_id, v_obra_id
  from public.comparativo_itens i
  join public.mapas_comparativos m on m.id = i.mapa_id
  where i.id = p_item_id
  for update of i;
  PERFORM public.fn_financeiro_autorizar_obra(v_obra_id,false);


  if not found then
    raise exception 'Item do mapa comparativo não encontrado.'
      using errcode = 'P0002';
  end if;

  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para eliminar itens desta obra.'
      using errcode = '42501';
  end if;

  select count(*)
  into v_precos_antes
  from public.comparativo_itens_precos
  where item_id = p_item_id;

  delete from public.comparativo_itens
  where id = p_item_id;

  select count(*)
  into v_precos_depois
  from public.comparativo_itens_precos
  where item_id = p_item_id;

  if v_precos_depois <> 0 then
    raise exception
      'A eliminação foi cancelada: existem preços órfãos para o item.';
  end if;

  perform public.fn_atualizar_melhor_preco_comparativo(v_mapa_id);

  return jsonb_build_object(
    'item_id', p_item_id,
    'precos_eliminados', v_precos_antes,
    'precos_restantes', v_precos_depois
  );
end;
$function$;
ALTER FUNCTION public.fn_eliminar_item_comparativo(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_eliminar_item_comparativo(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_item_comparativo(uuid) TO authenticated;
CREATE POLICY financeiro_empresa_insert ON public.faturas_itens AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.faturas f WHERE f.id=fatura_id AND public.fn_financeiro_obra_da_empresa(f.obra_id)));
CREATE POLICY financeiro_empresa_insert ON public.faturas_anexos AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.faturas f WHERE f.id=fatura_id AND public.fn_financeiro_obra_da_empresa(f.obra_id)));
CREATE POLICY financeiro_empresa_insert ON public.faturas_guias AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.faturas f WHERE f.id=fatura_id AND public.fn_financeiro_obra_da_empresa(f.obra_id)));
CREATE POLICY financeiro_empresa_update ON public.faturas_guias AS RESTRICTIVE FOR UPDATE TO authenticated
USING(EXISTS(SELECT 1 FROM public.faturas f WHERE f.id=fatura_id AND public.fn_financeiro_obra_da_empresa(f.obra_id)))
WITH CHECK(EXISTS(SELECT 1 FROM public.faturas f WHERE f.id=fatura_id AND public.fn_financeiro_obra_da_empresa(f.obra_id)));
CREATE POLICY financeiro_empresa_delete ON public.faturas_guias AS RESTRICTIVE FOR DELETE TO authenticated
USING(EXISTS(SELECT 1 FROM public.faturas f WHERE f.id=fatura_id AND public.fn_financeiro_obra_da_empresa(f.obra_id)));
CREATE POLICY financeiro_empresa_insert ON public.mapas_comparativos AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(public.fn_financeiro_obra_da_empresa(obra_id));
CREATE POLICY financeiro_empresa_update ON public.mapas_comparativos AS RESTRICTIVE FOR UPDATE TO authenticated
USING(public.fn_financeiro_obra_da_empresa(obra_id))
WITH CHECK(public.fn_financeiro_obra_da_empresa(obra_id));
CREATE POLICY financeiro_empresa_delete ON public.mapas_comparativos AS RESTRICTIVE FOR DELETE TO authenticated
USING(public.fn_financeiro_obra_da_empresa(obra_id));
CREATE POLICY financeiro_empresa_insert ON public.comparativo_itens AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_update ON public.comparativo_itens AS RESTRICTIVE FOR UPDATE TO authenticated
USING(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)))
WITH CHECK(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_delete ON public.comparativo_itens AS RESTRICTIVE FOR DELETE TO authenticated
USING(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_insert ON public.comparativo_propostas AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_update ON public.comparativo_propostas AS RESTRICTIVE FOR UPDATE TO authenticated
USING(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)))
WITH CHECK(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_delete ON public.comparativo_propostas AS RESTRICTIVE FOR DELETE TO authenticated
USING(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_insert ON public.comparativo_ajustes AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_update ON public.comparativo_ajustes AS RESTRICTIVE FOR UPDATE TO authenticated
USING(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)))
WITH CHECK(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_delete ON public.comparativo_ajustes AS RESTRICTIVE FOR DELETE TO authenticated
USING(EXISTS(SELECT 1 FROM public.mapas_comparativos m WHERE m.id=mapa_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_insert ON public.comparativo_itens_precos AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(EXISTS(SELECT 1 FROM public.comparativo_itens i JOIN public.mapas_comparativos m ON m.id=i.mapa_id WHERE i.id=item_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_update ON public.comparativo_itens_precos AS RESTRICTIVE FOR UPDATE TO authenticated
USING(EXISTS(SELECT 1 FROM public.comparativo_itens i JOIN public.mapas_comparativos m ON m.id=i.mapa_id WHERE i.id=item_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)))
WITH CHECK(EXISTS(SELECT 1 FROM public.comparativo_itens i JOIN public.mapas_comparativos m ON m.id=i.mapa_id WHERE i.id=item_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));
CREATE POLICY financeiro_empresa_delete ON public.comparativo_itens_precos AS RESTRICTIVE FOR DELETE TO authenticated
USING(EXISTS(SELECT 1 FROM public.comparativo_itens i JOIN public.mapas_comparativos m ON m.id=i.mapa_id WHERE i.id=item_id AND public.fn_financeiro_obra_da_empresa(m.obra_id)));

-- Writers económicos: tenant antes do papel, recursos relacionados bloqueados.
CREATE OR REPLACE FUNCTION public.fn_concluir_custo_pl(p_componente_id uuid, p_valor_real numeric DEFAULT NULL::numeric)
 RETURNS planeamento_custos_componentes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_obra_id uuid; v_row public.planeamento_custos_componentes%rowtype;
begin
  select f.obra_id into v_obra_id
  from public.planeamento_custos_componentes c
  join public.planeamento_itens pi on pi.id=c.planeamento_item_id
  join public.fases f on f.id=pi.fase_id
  where c.id=p_componente_id and c.tipo='PL' for update of c for share of pi,f;
  if not found then raise exception 'Componente PL não encontrado.'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_e_diretor_obra(v_obra_id) then
    raise exception 'A conclusão está reservada ao Diretor de Obra ou Gerência.' using errcode='42501';
  end if;
  update public.planeamento_custos_componentes
  set valor_real_pl=greatest(coalesce(p_valor_real,valor_orcamentado),0),
      estado_custo='concluido', concluido_confirmado_em=now(),
      concluido_confirmado_por=public.fn_utilizador_atual_id(), atualizado_em=now()
  where id=p_componente_id returning * into v_row;
  return v_row;
end;
$function$
;
ALTER FUNCTION public.fn_concluir_custo_pl(uuid,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_concluir_custo_pl(uuid,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_concluir_custo_pl(uuid,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_concluir_custo_pl_fase(p_orcamento_fase_id uuid, p_valor_real numeric DEFAULT NULL::numeric)
 RETURNS orcamento_fases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare row_out public.orcamento_fases;
begin
  select * into row_out from public.orcamento_fases where id=p_orcamento_fase_id for update;
  if not found then raise exception 'Orçamento de fase não encontrado.'; end if;
  perform public.fn_financeiro_autorizar_obra(row_out.obra_id,false);
  if not (public.fn_e_gestao_plataforma() or public.fn_e_diretor_obra(row_out.obra_id)) then raise exception 'Conclusão reservada à Gestão da Plataforma ou Diretor de Obra.' using errcode='42501'; end if;
  update public.orcamento_fases set valor_real_pl=greatest(coalesce(p_valor_real,custo_total_estimado),0),estado_custo='concluido',concluido_por=public.fn_utilizador_atual_id(),concluido_em=now()
  where id=p_orcamento_fase_id returning * into row_out; return row_out;
end $function$
;
ALTER FUNCTION public.fn_concluir_custo_pl_fase(uuid,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_concluir_custo_pl_fase(uuid,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_concluir_custo_pl_fase(uuid,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_concluir_custos_pl_tarefa(p_planeamento_item_id uuid)
 RETURNS SETOF planeamento_custos_componentes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_obra_id uuid;
begin
  select f.obra_id into v_obra_id from public.planeamento_itens pi join public.fases f on f.id=pi.fase_id where pi.id=p_planeamento_item_id for update of pi for share of f;
  if not found then raise exception 'Tarefa não encontrada.'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_obra(v_obra_id) then raise exception 'Sem permissão para concluir esta tarefa.' using errcode='42501'; end if;
  return query update public.planeamento_custos_componentes
    set valor_real_pl=coalesce(valor_real_pl,valor_orcamentado),estado_custo='concluido',
      concluido_confirmado_em=coalesce(concluido_confirmado_em,now()),
      concluido_confirmado_por=coalesce(concluido_confirmado_por,public.fn_utilizador_atual_id()),atualizado_em=now()
    where planeamento_item_id=p_planeamento_item_id and tipo='PL' and estado_custo<>'cancelado' returning *;
end;
$function$
;
ALTER FUNCTION public.fn_concluir_custos_pl_tarefa(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_concluir_custos_pl_tarefa(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_concluir_custos_pl_tarefa(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_confirmar_custo_real_pl(p_planeamento_item_id uuid, p_valor_real numeric DEFAULT NULL::numeric)
 RETURNS planeamento_itens
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_item public.planeamento_itens; v_obra_id uuid; v_utilizador_id uuid; v_valor numeric;
begin
  select pi.* into v_item from public.planeamento_itens pi
  where pi.id=p_planeamento_item_id for update;
  if not found then raise exception 'Tarefa/pacote PL não encontrado.'; end if;
  select f.obra_id into v_obra_id from public.fases f where f.id=v_item.fase_id for share;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Só a equipa técnica responsável pode confirmar o custo PL.' using errcode='42501';
  end if;
  if coalesce(v_item.executado_por,'PL') not in ('PL','misto') then
    raise exception 'Esta tarefa não possui uma componente executada pela Primeline.';
  end if;
  if v_item.estado<>'concluido' then
    raise exception 'A componente PL só pode passar a Custo Real quando a tarefa estiver concluída.';
  end if;
  v_valor:=coalesce(p_valor_real,v_item.valor_orca_pl,v_item.valor_estimado);
  if v_valor is null or v_valor<0 then raise exception 'Indique um Valor Real PL válido.'; end if;
  select id into v_utilizador_id from public.utilizadores where auth_user_id=auth.uid() limit 1;
  update public.planeamento_itens set valor_real_pl=v_valor,custo_pl_confirmado=true,
    custo_pl_confirmado_por=v_utilizador_id,custo_pl_confirmado_em=now(),custo_estado='concluido'
  where id=p_planeamento_item_id returning * into v_item;
  return v_item;
end;$function$
;
ALTER FUNCTION public.fn_confirmar_custo_real_pl(uuid,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_confirmar_custo_real_pl(uuid,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_confirmar_custo_real_pl(uuid,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_confirmar_remocao_custo_estimado_subempreitada(p_subempreitada_id uuid)
 RETURNS planeamento_custos_componentes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_obra_id uuid; v_row public.planeamento_custos_componentes%rowtype;
begin
  select obra_id into v_obra_id from public.subempreitadas where id=p_subempreitada_id for update;
  if not found then raise exception 'Subempreitada não encontrada.'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  perform 1 from public.planeamento_custos_componentes c where c.subempreitada_id=p_subempreitada_id and c.tipo='subempreitada' for update;
  perform 1 from public.planeamento_custos_componentes c
  join public.planeamento_itens pi on pi.id=c.planeamento_item_id join public.fases f on f.id=pi.fase_id
  where c.subempreitada_id=p_subempreitada_id and c.tipo='subempreitada' for share of pi,f;
  if exists(select 1 from public.planeamento_custos_componentes c
    left join public.planeamento_itens pi on pi.id=c.planeamento_item_id left join public.fases f on f.id=pi.fase_id
    where c.subempreitada_id=p_subempreitada_id and c.tipo='subempreitada' and f.obra_id is distinct from v_obra_id) then
    raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501';
  end if;
  if not public.fn_e_diretor_obra(v_obra_id) then raise exception 'A confirmação está reservada ao Diretor de Obra ou Gerência.' using errcode='42501'; end if;
  update public.planeamento_custos_componentes set remocao_estimado_confirmada_em=now(),remocao_estimado_confirmada_por=public.fn_utilizador_atual_id(),
    estado_custo=case when estado_custo='orcamentado_nao_comprometido' then 'adjudicado' else estado_custo end,atualizado_em=now()
  where subempreitada_id=p_subempreitada_id and tipo='subempreitada' returning * into v_row;
  if not found then raise exception 'Componente de custo da subempreitada não encontrado.'; end if; return v_row;
end; $function$
;
ALTER FUNCTION public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_guardar_componente_custo(p_planeamento_item_id uuid, p_tipo text, p_valor_orcamentado numeric, p_estado_custo text, p_valor_real_pl numeric, p_item_orcamento_id uuid)
 RETURNS planeamento_custos_componentes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_obra_id uuid; v_item public.planeamento_itens%rowtype; v_row public.planeamento_custos_componentes%rowtype;
begin
  select * into v_item from public.planeamento_itens where id=p_planeamento_item_id for update;
  if not found then raise exception 'Tarefa de planeamento não encontrada.'; end if;
  select obra_id into v_obra_id from public.fases where id=v_item.fase_id for share;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_e_diretor_obra(v_obra_id) then raise exception 'A composição do custo só pode ser alterada pelo Diretor de Obra ou Gerência.' using errcode='42501'; end if;
  if p_item_orcamento_id is not null then
    perform 1 from public.itens_orcamento i join public.fases f on f.id=i.fase_id
    where i.id=p_item_orcamento_id and f.obra_id=v_obra_id for share of i,f;
    if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  end if;
  if p_tipo='subempreitada' and v_item.subempreitada_id is not null then
    perform 1 from public.subempreitadas s where s.id=v_item.subempreitada_id and s.obra_id=v_obra_id for share;
    if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  end if;
  if p_tipo not in ('PL','subempreitada') then raise exception 'Tipo de componente inválido.'; end if;
  if p_estado_custo not in ('orcamentado_nao_comprometido','em_consulta','adjudicado','em_execucao','concluido','cancelado') then raise exception 'Estado de custo inválido.'; end if;

  if p_item_orcamento_id is null then
    insert into public.planeamento_custos_componentes(planeamento_item_id,especialidade_id,tipo,item_orcamento_id,subempreitada_id,valor_orcamentado,valor_real_pl,estado_custo)
    values(v_item.id,v_item.especialidade_id,p_tipo,null,case when p_tipo='subempreitada' then v_item.subempreitada_id end,greatest(coalesce(p_valor_orcamentado,0),0),case when p_tipo='PL' then p_valor_real_pl end,p_estado_custo)
    on conflict (planeamento_item_id,tipo) where item_orcamento_id is null
    do update set especialidade_id=excluded.especialidade_id,subempreitada_id=excluded.subempreitada_id,
      valor_orcamentado=excluded.valor_orcamentado,valor_real_pl=excluded.valor_real_pl,
      estado_custo=excluded.estado_custo,atualizado_em=now() returning * into v_row;
  else
    insert into public.planeamento_custos_componentes(planeamento_item_id,especialidade_id,tipo,item_orcamento_id,subempreitada_id,valor_orcamentado,valor_real_pl,estado_custo)
    values(v_item.id,v_item.especialidade_id,p_tipo,p_item_orcamento_id,case when p_tipo='subempreitada' then v_item.subempreitada_id end,greatest(coalesce(p_valor_orcamentado,0),0),case when p_tipo='PL' then p_valor_real_pl end,p_estado_custo)
    on conflict (planeamento_item_id,tipo,item_orcamento_id) where item_orcamento_id is not null
    do update set especialidade_id=excluded.especialidade_id,subempreitada_id=excluded.subempreitada_id,
      valor_orcamentado=excluded.valor_orcamentado,valor_real_pl=excluded.valor_real_pl,
      estado_custo=excluded.estado_custo,atualizado_em=now() returning * into v_row;
  end if;
  return v_row;
end;
$function$
;
ALTER FUNCTION public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_eliminar_proposta_comparativo(p_proposta_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_mapa_id uuid;
  v_obra_id uuid;
  v_precos_antes integer;
  v_ajustes_antes integer;
  v_precos_depois integer;
  v_ajustes_depois integer;
begin
  select p.mapa_id, m.obra_id
  into v_mapa_id, v_obra_id
  from public.comparativo_propostas p
  join public.mapas_comparativos m on m.id = p.mapa_id
  where p.id = p_proposta_id
  for update of p for share of m;

  if not found then
    raise exception 'Proposta do mapa comparativo não encontrada.'
      using errcode = 'P0002';
  end if;

  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para eliminar propostas desta obra.'
      using errcode = '42501';
  end if;

  select count(*)
  into v_precos_antes
  from public.comparativo_itens_precos
  where proposta_id = p_proposta_id;

  select count(*)
  into v_ajustes_antes
  from public.comparativo_ajustes
  where proposta_id = p_proposta_id;

  delete from public.comparativo_propostas
  where id = p_proposta_id;

  select count(*)
  into v_precos_depois
  from public.comparativo_itens_precos
  where proposta_id = p_proposta_id;

  select count(*)
  into v_ajustes_depois
  from public.comparativo_ajustes
  where proposta_id = p_proposta_id;

  if v_precos_depois <> 0 or v_ajustes_depois <> 0 then
    raise exception
      'A eliminação foi cancelada: existem preços ou ajustes órfãos para a proposta.';
  end if;

  perform public.fn_atualizar_melhor_preco_comparativo(v_mapa_id);

  return jsonb_build_object(
    'proposta_id', p_proposta_id,
    'precos_eliminados', v_precos_antes,
    'ajustes_eliminados', v_ajustes_antes,
    'precos_restantes', v_precos_depois,
    'ajustes_restantes', v_ajustes_depois
  );
end;
$function$
;
ALTER FUNCTION public.fn_eliminar_proposta_comparativo(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_eliminar_proposta_comparativo(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_proposta_comparativo(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_criar_fornecedor_comparativo(p_mapa_id uuid, p_nome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_obra_id uuid; v_empresa_id uuid; v_nome text; v_chave text; v_fornecedor public.fornecedores; v_ja_existia boolean := false;
begin
  v_nome := regexp_replace(btrim(coalesce(p_nome,'')), '\s+', ' ', 'g');
  if length(v_nome) < 2 then raise exception 'Indique o nome do fornecedor.' using errcode='23514'; end if;
  v_chave := lower(regexp_replace(regexp_replace(v_nome,'\y(unipessoal|unip|lda|sa|ltda)\y\.?','','gi'),'[^[:alnum:]]+','','g'));

  select m.obra_id,o.empresa_id into v_obra_id,v_empresa_id
  from public.mapas_comparativos m join public.obras o on o.id=m.obra_id where m.id=p_mapa_id for share of m,o;
  if v_obra_id is null then raise exception 'Mapa comparativo não encontrado.' using errcode='P0002'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para criar fornecedores nesta obra.' using errcode='42501';
  end if;

  select * into v_fornecedor from public.fornecedores
  where empresa_id=v_empresa_id
    and lower(regexp_replace(regexp_replace(nome,'\y(unipessoal|unip|lda|sa|ltda)\y\.?','','gi'),'[^[:alnum:]]+','','g'))=v_chave
  order by id limit 1;
  if found then
    v_ja_existia := true;
  else
    insert into public.fornecedores(empresa_id,nome,tipo_entidade,estado_confianca)
    values(v_empresa_id,v_nome,'subempreiteiro','nao_avaliado') returning * into v_fornecedor;
  end if;

  return jsonb_build_object('id',v_fornecedor.id,'nome',v_fornecedor.nome,
    'tipo_entidade',v_fornecedor.tipo_entidade,'estado_confianca',v_fornecedor.estado_confianca,
    'ja_existia',v_ja_existia);
end $function$
;
ALTER FUNCTION public.fn_criar_fornecedor_comparativo(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_criar_fornecedor_comparativo(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_criar_fornecedor_comparativo(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_importar_proposta_comparativo(p_mapa_id uuid, p_fornecedor_id uuid, p_dados jsonb, p_linhas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_obra_id uuid; v_empresa_id uuid; v_proposta_id uuid; v_linha jsonb; v_item_id uuid;
  v_numero text; v_quantidade numeric; v_unitario numeric; v_total_original numeric;
  v_criados integer := 0; v_existente integer;
begin
  select m.obra_id,o.empresa_id into v_obra_id,v_empresa_id
  from public.mapas_comparativos m join public.obras o on o.id=m.obra_id where m.id=p_mapa_id for share of m,o;
  if v_obra_id is null then raise exception 'Mapa comparativo não encontrado.' using errcode='P0002'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_obra(v_obra_id) then raise exception 'Sem permissão para importar nesta obra.' using errcode='42501'; end if;
  perform 1 from public.fornecedores where id=p_fornecedor_id and empresa_id=v_empresa_id for share;
  if not found then
    raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501';
  end if;
  if jsonb_typeof(coalesce(p_linhas,'[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_linhas,'[]'::jsonb))=0 then
    raise exception 'Selecione pelo menos uma linha da proposta.' using errcode='23514';
  end if;
  select count(*) into v_existente from public.comparativo_propostas where mapa_id=p_mapa_id and fornecedor_id=p_fornecedor_id;
  if v_existente>0 then raise exception 'Este fornecedor já tem uma proposta neste mapa. Edite a proposta existente.' using errcode='23505'; end if;

  insert into public.comparativo_propostas(
    mapa_id,fornecedor_id,data_proposta,prazo_validade,condicoes_pagamento,exclusoes_ambito,
    fornecedor_nome_extraido,referencia_proposta,total_original,documento_url,documento_nome,extracao_dados,
    estado_revisao,prazo_entrega,prazo_montagem,garantia,validade_dias,outras_informacoes
  ) values (
    p_mapa_id,p_fornecedor_id,nullif(p_dados->>'proposalDate','')::date,nullif(p_dados->>'validityDate','')::date,
    nullif(p_dados->>'paymentTerms',''),nullif(p_dados->>'exclusions',''),nullif(p_dados->>'supplierName',''),
    nullif(p_dados->>'reference',''),nullif(p_dados->>'officialTotal','')::numeric,nullif(p_dados->>'documentPath',''),nullif(p_dados->>'documentName',''),
    coalesce(p_dados,'{}'::jsonb) - 'fullText' - 'lines','revisto',nullif(p_dados->>'deliveryTerms',''),
    nullif(p_dados->>'assemblyTerms',''),nullif(p_dados->>'warranty',''),nullif(p_dados->>'validityDays','')::integer,
    nullif(p_dados->>'reviewNotes','')
  ) returning id into v_proposta_id;

  for v_linha in select value from jsonb_array_elements(p_linhas) loop
    v_item_id := nullif(v_linha->>'itemId','')::uuid;
    if v_item_id is not null then
      perform 1 from public.comparativo_itens where id=v_item_id and mapa_id=p_mapa_id for share;
      if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
    end if;
    v_quantidade := greatest(coalesce(nullif(v_linha->>'normalizedQuantity','')::numeric,1),0.0001);
    v_total_original := nullif(v_linha->>'originalTotal','')::numeric;
    v_unitario := nullif(v_linha->>'unitPrice','')::numeric;
    if v_unitario is null and v_total_original is not null then v_unitario := round(v_total_original/v_quantidade,4); end if;
    if v_unitario is null or v_unitario<0 then raise exception 'Todas as linhas selecionadas precisam de valor.' using errcode='23514'; end if;

    if v_item_id is null then
      v_numero := nullif(btrim(v_linha->>'number'),'');
      if v_numero is null then
        select 'PDF-'||(count(*)+1)::text into v_numero from public.comparativo_itens where mapa_id=p_mapa_id;
      end if;
      while exists(select 1 from public.comparativo_itens where mapa_id=p_mapa_id and numero=v_numero) loop
        v_numero := v_numero||'-'||(v_criados+1)::text;
      end loop;
      insert into public.comparativo_itens(mapa_id,numero,designacao,unidade,quantidade)
      values(p_mapa_id,v_numero,coalesce(nullif(btrim(v_linha->>'normalizedDescription'),''),'Item importado'),
        coalesce(nullif(btrim(v_linha->>'unit'),''),'un'),v_quantidade) returning id into v_item_id;
    end if;

    insert into public.comparativo_itens_precos(
      item_id,proposta_id,preco_unitario,observacoes,descricao_original,quantidade_original,
      unidade_original,preco_total_original,estado_ambito,comparavel,origem_pagina,confianca_extracao
    ) values (
      v_item_id,v_proposta_id,v_unitario,nullif(v_linha->>'notes',''),nullif(v_linha->>'originalDescription',''),
      nullif(v_linha->>'originalQuantity','')::numeric,nullif(v_linha->>'originalUnit',''),v_total_original,
      coalesce(nullif(v_linha->>'scopeStatus',''),'incluido'),coalesce((v_linha->>'comparable')::boolean,false),
      nullif(v_linha->>'sourcePage','')::integer,nullif(v_linha->>'confidence','')::numeric
    );
    v_criados := v_criados+1;
  end loop;

  return jsonb_build_object('proposta_id',v_proposta_id,'linhas_criadas',v_criados);
end $function$
;
ALTER FUNCTION public.fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_criar_subempreitada_do_comparativo(p_mapa_id uuid, p_proposta_id uuid, p_fase_id uuid, p_data_inicio_prevista date, p_data_fim_prevista date, p_condicao_pagamento text DEFAULT NULL::text)
 RETURNS subempreitadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_mapa public.mapas_comparativos;
  v_proposta public.comparativo_propostas;
  v_sub public.subempreitadas;
begin
  select *
  into v_mapa
  from public.mapas_comparativos
  where id = p_mapa_id
  for update;

  if not found then
    raise exception 'Mapa comparativo não encontrado.';
  end if;

  perform public.fn_financeiro_autorizar_obra(v_mapa.obra_id,false);
  if not public.fn_pode_editar_obra(v_mapa.obra_id) then
    raise exception 'Sem permissão para adjudicar nesta obra.'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.subempreitadas
    where mapa_comparativo_id = p_mapa_id
  ) then
    raise exception 'Este mapa já originou uma subempreitada.'
      using errcode = '23505';
  end if;

  if v_mapa.valor_adjudicado_real is null then
    raise exception
      'Preencha o Valor Adjudicado Real antes de criar a subempreitada.'
      using errcode = '23514';
  end if;

  select *
  into v_proposta
  from public.comparativo_propostas
  where id = p_proposta_id
    and mapa_id = p_mapa_id for share;

  if not found then
    raise exception 'A proposta não pertence a este mapa.'
      using errcode = '23514';
  end if;

  perform 1 from public.fornecedores s join public.obras o on o.id=v_mapa.obra_id
  where s.id=v_proposta.fornecedor_id and s.empresa_id=o.empresa_id for share of s;
  if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;

  perform 1 from public.fases where id=p_fase_id and obra_id=v_mapa.obra_id for share;
  if not found then
    raise exception 'A fase não pertence a esta obra.'
      using errcode = '23514';
  end if;

  insert into public.subempreitadas (
    obra_id,
    fase_id,
    fornecedor_id,
    especialidade,
    valor_adjudicado,
    estado,
    data_inicio_prevista,
    data_fim_prevista,
    condicao_pagamento,
    mapa_comparativo_id
  )
  values (
    v_mapa.obra_id,
    p_fase_id,
    v_proposta.fornecedor_id,
    v_mapa.especialidade,
    v_mapa.valor_adjudicado_real,
    'em_execucao',
    p_data_inicio_prevista,
    p_data_fim_prevista,
    p_condicao_pagamento,
    p_mapa_id
  )
  returning * into v_sub;

  return v_sub;
end;
$function$
;
ALTER FUNCTION public.fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_guardar_lancamento_gestao_obras(p_id uuid, p_obra_id uuid, p_categoria text, p_data_lancamento date, p_entidade_nome text, p_descricao text, p_documento text, p_unidade_medida text, p_quantidade numeric, p_valor_unitario numeric, p_data_pagamento date, p_valor numeric)
 RETURNS gestao_obras_lancamentos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  row_out public.gestao_obras_lancamentos;
begin
  if p_id is not null then
    select * into row_out from public.gestao_obras_lancamentos where id=p_id for update;
    if not found then raise exception 'Lançamento não encontrado.' using errcode='P0002'; end if;
  perform public.fn_financeiro_autorizar_obra(row_out.obra_id,false);
  end if;
  perform public.fn_financeiro_autorizar_obra(p_obra_id,false);
  if not public.fn_pode_editar_mapa_gestao_obras() then
    raise exception
      'Só o Administrativo e a Gestão da Plataforma podem alterar lançamentos.'
      using errcode='42501';
  end if;

  if p_categoria not in ('materiais','mao_obra','estaleiro') then
    raise exception 'Categoria não editável neste ecrã.';
  end if;

  if not exists(select 1 from public.obras where id=p_obra_id) then
    raise exception 'Obra não encontrada.';
  end if;

  if p_quantidade is not null and p_quantidade<0 then
    raise exception 'A quantidade não pode ser negativa.';
  end if;

  if p_valor_unitario is not null and p_valor_unitario<0 then
    raise exception 'O valor unitário não pode ser negativo.';
  end if;

  if p_id is null then
    insert into public.gestao_obras_lancamentos(
      obra_id,
      categoria,
      data_lancamento,
      entidade_nome,
      descricao,
      documento,
      unidade_medida,
      quantidade,
      valor_unitario,
      data_pagamento,
      valor
    )
    values(
      p_obra_id,
      p_categoria,
      p_data_lancamento,
      btrim(p_entidade_nome),
      btrim(p_descricao),
      nullif(btrim(p_documento),''),
      nullif(btrim(p_unidade_medida),''),
      p_quantidade,
      p_valor_unitario,
      p_data_pagamento,
      greatest(coalesce(p_valor,0),0)
    )
    returning * into row_out;
  else
    update public.gestao_obras_lancamentos
    set
      obra_id=p_obra_id,
      categoria=p_categoria,
      data_lancamento=p_data_lancamento,
      entidade_nome=btrim(p_entidade_nome),
      descricao=btrim(p_descricao),
      documento=nullif(btrim(p_documento),''),
      unidade_medida=nullif(btrim(p_unidade_medida),''),
      quantidade=p_quantidade,
      valor_unitario=p_valor_unitario,
      data_pagamento=p_data_pagamento,
      valor=greatest(coalesce(p_valor,0),0),
      atualizado_por=public.fn_utilizador_atual_id(),
      atualizado_em=now()
    where id=p_id
    returning * into row_out;

    if not found then
      raise exception 'Lançamento não encontrado.';
    end if;
  end if;

  return row_out;
end $function$
;
ALTER FUNCTION public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_apagar_lancamento_gestao_obras(p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare deleted_id uuid; v_obra_id uuid;
begin
  select obra_id into v_obra_id from public.gestao_obras_lancamentos where id=p_id for update;
  if not found then raise exception 'Lançamento não encontrado.' using errcode='P0002'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_mapa_gestao_obras() then raise exception 'Sem permissão para apagar este lançamento.' using errcode='42501'; end if;
  delete from public.gestao_obras_lancamentos where id=p_id returning id into deleted_id;
  if deleted_id is null then raise exception 'Lançamento não encontrado.'; end if;
  return deleted_id;
end $function$
;
ALTER FUNCTION public.fn_apagar_lancamento_gestao_obras(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_lancamento_gestao_obras(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_lancamento_gestao_obras(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_confirmar_compromisso_subempreitada(p_planeamento_item_id uuid)
 RETURNS planeamento_itens
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_item public.planeamento_itens;
  v_obra_id uuid;
  v_sub public.subempreitadas;
  v_utilizador_id uuid;
begin
  select pi.*
  into v_item
  from public.planeamento_itens pi
  where pi.id = p_planeamento_item_id
  for update;

  if not found then
    raise exception
      'Tarefa/pacote de subempreitada não encontrado.';
  end if;

  select fase.obra_id
  into v_obra_id
  from public.fases fase
  where fase.id = v_item.fase_id for share;

  if not found then
    raise exception
      'A fase associada à tarefa não foi encontrada.';
  end if;

  select s.*
  into v_sub
  from public.subempreitadas s
  where s.id = v_item.subempreitada_id for share;

  if not found then
    raise exception
      'A tarefa não está associada a uma subempreitada.';
  end if;

  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if v_sub.obra_id is distinct from v_obra_id then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception
      'Só a equipa técnica responsável pode confirmar este compromisso.' using errcode='42501';
  end if;

  if lower(coalesce(v_sub.estado,'')) not in (
    'adjudicada',
    'adjudicado',
    'em_execucao',
    'concluida',
    'concluido'
  ) then
    raise exception
      'A subempreitada ainda não está adjudicada.';
  end if;

  select id
  into v_utilizador_id
  from public.utilizadores
  where auth_user_id = auth.uid()
  limit 1;

  update public.planeamento_itens
  set
    compromisso_confirmado = true,
    compromisso_confirmado_por = v_utilizador_id,
    compromisso_confirmado_em = now(),
    custo_estado = 'adjudicado'
  where id = p_planeamento_item_id
  returning * into v_item;

  return v_item;
end;
$function$
;
ALTER FUNCTION public.fn_confirmar_compromisso_subempreitada(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_confirmar_compromisso_subempreitada(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_confirmar_compromisso_subempreitada(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_importar_orcamento_fases(p_obra_id uuid, p_linhas jsonb, p_nome_ficheiro text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare linha jsonb; total integer:=0; fase_obra uuid;
begin
  perform public.fn_financeiro_autorizar_obra(p_obra_id,false);
  if not (public.fn_e_gestao_plataforma() or public.fn_e_diretor_obra(p_obra_id)) then raise exception 'Importação reservada à Gestão da Plataforma ou Diretor de Obra.' using errcode='42501'; end if;
  for linha in select * from jsonb_array_elements(coalesce(p_linhas,'[]'::jsonb)) loop
    select obra_id into fase_obra from public.fases where id=(linha->>'fase_id')::uuid for share;
    if fase_obra is distinct from p_obra_id then raise exception 'A fase indicada não pertence à obra.'; end if;
    insert into public.orcamento_fases(obra_id,fase_id,descricao,venda_prevista,custo_total_estimado,margem_prevista,deslocacoes,mao_obra,maquinas,materiais,mao_obra_sub,subempreitada,nome_ficheiro_origem,importado_por,importado_em)
    values(p_obra_id,(linha->>'fase_id')::uuid,linha->>'descricao',coalesce((linha->>'venda_prevista')::numeric,0),coalesce((linha->>'custo_total_estimado')::numeric,0),coalesce((linha->>'margem_prevista')::numeric,0),coalesce((linha->>'deslocacoes')::numeric,0),coalesce((linha->>'mao_obra')::numeric,0),coalesce((linha->>'maquinas')::numeric,0),coalesce((linha->>'materiais')::numeric,0),coalesce((linha->>'mao_obra_sub')::numeric,0),coalesce((linha->>'subempreitada')::numeric,0),p_nome_ficheiro,public.fn_utilizador_atual_id(),now())
    on conflict(fase_id) do update set descricao=excluded.descricao,venda_prevista=excluded.venda_prevista,custo_total_estimado=excluded.custo_total_estimado,margem_prevista=excluded.margem_prevista,deslocacoes=excluded.deslocacoes,mao_obra=excluded.mao_obra,maquinas=excluded.maquinas,materiais=excluded.materiais,mao_obra_sub=excluded.mao_obra_sub,subempreitada=excluded.subempreitada,nome_ficheiro_origem=excluded.nome_ficheiro_origem,importado_por=excluded.importado_por,importado_em=now();
    total:=total+1;
  end loop;
  return jsonb_build_object('importadas',total);
end $function$
;
ALTER FUNCTION public.fn_importar_orcamento_fases(uuid,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_importar_orcamento_fases(uuid,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_importar_orcamento_fases(uuid,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_guardar_precos_candidato_subempreitada(p_candidato_id uuid, p_precos jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_obra_id uuid;
  v_total numeric;
begin
  select consulta.obra_id
  into v_obra_id
  from public.consultas_subempreitada_candidatos candidato
  join public.consultas_subempreitada consulta
    on consulta.id = candidato.consulta_subempreitada_id
  where candidato.id = p_candidato_id for update of candidato for share of consulta;

  if not found then
    raise exception using errcode = 'P0002',
      message = 'Candidato não encontrado.';
  end if;

  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception using errcode = '42501',
      message = 'Sem permissão para editar esta consulta.';
  end if;

  if p_precos is null or jsonb_typeof(p_precos) <> 'array' then
    raise exception using errcode = '23514',
      message = 'A lista de preços é inválida.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_precos)
      as preco(item_orcamento_id uuid, preco_unitario numeric)
    group by preco.item_orcamento_id
    having count(*) > 1
  ) then
    raise exception using errcode = '23514',
      message = 'A lista contém o mesmo artigo mais de uma vez.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_precos)
      as preco(item_orcamento_id uuid, preco_unitario numeric)
    left join public.consultas_subempreitada_candidatos candidato
      on candidato.id = p_candidato_id
    left join public.consultas_subempreitada_itens consulta_item
      on consulta_item.consulta_subempreitada_id =
         candidato.consulta_subempreitada_id
     and consulta_item.item_orcamento_id = preco.item_orcamento_id
    left join public.itens_orcamento item
      on item.id = preco.item_orcamento_id
    where consulta_item.id is null
       or item.quantidade is null
       or item.quantidade <= 0
       or (
         preco.preco_unitario is not null
         and preco.preco_unitario < 0
       )
  ) then
    raise exception using errcode = '23514',
      message = 'Existe um preço inválido ou um artigo que não pertence à consulta.';
  end if;

  perform 1 from public.consultas_subempreitada_candidatos c join public.fornecedores s on s.id=c.fornecedor_id
  join public.obras o on o.id=v_obra_id where c.id=p_candidato_id and s.empresa_id=o.empresa_id for share of s;
  if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  perform 1 from public.consultas_subempreitada_itens ci join public.itens_orcamento i on i.id=ci.item_orcamento_id
  join public.fases f on f.id=i.fase_id join public.consultas_subempreitada_candidatos c on c.consulta_subempreitada_id=ci.consulta_subempreitada_id
  where c.id=p_candidato_id for share of ci,i,f;
  if exists(select 1 from jsonb_to_recordset(p_precos) as p(item_orcamento_id uuid,preco_unitario numeric)
   join public.itens_orcamento i on i.id=p.item_orcamento_id left join public.fases f on f.id=i.fase_id
   where f.obra_id is distinct from v_obra_id) then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  delete from public.consultas_subempreitada_candidatos_itens
  where candidato_id = p_candidato_id;

  insert into public.consultas_subempreitada_candidatos_itens (
    candidato_id,
    item_orcamento_id,
    preco_unitario,
    preco_total
  )
  select
    p_candidato_id,
    preco.item_orcamento_id,
    preco.preco_unitario,
    preco.preco_unitario * item.quantidade
  from jsonb_to_recordset(p_precos)
    as preco(item_orcamento_id uuid, preco_unitario numeric)
  join public.itens_orcamento item
    on item.id = preco.item_orcamento_id
  where preco.preco_unitario is not null;

  select coalesce(sum(preco_total), 0)
  into v_total
  from public.consultas_subempreitada_candidatos_itens
  where candidato_id = p_candidato_id;

  update public.consultas_subempreitada_candidatos
  set valor_total = v_total
  where id = p_candidato_id;

  return v_total;
end;
$function$
;
ALTER FUNCTION public.fn_guardar_precos_candidato_subempreitada(uuid,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_guardar_precos_candidato_subempreitada(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_guardar_precos_candidato_subempreitada(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_criar_consulta_subempreitada(p_obra_id uuid, p_fase_id uuid, p_trabalho text, p_item_ids uuid[])
 RETURNS consultas_subempreitada
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_consulta public.consultas_subempreitada%rowtype;
  v_total_pedido integer;
  v_total_valido integer;
begin
  perform public.fn_financeiro_autorizar_obra(p_obra_id,false);
  if not public.fn_pode_editar_obra(p_obra_id) then
    raise exception using errcode = '42501',
      message = 'Sem permissão para criar consultas nesta obra.';
  end if;

  if nullif(btrim(p_trabalho), '') is null then
    raise exception using errcode = '23514',
      message = 'A especialidade é obrigatória.';
  end if;

  if p_item_ids is null or cardinality(p_item_ids) = 0 then
    raise exception using errcode = '23514',
      message = 'Selecione pelo menos um item do orçamento.';
  end if;

  if not exists (
    select 1
    from public.fases f
    where f.id = p_fase_id
      and f.obra_id = p_obra_id
  ) then
    raise exception using errcode = '23514',
      message = 'A fase selecionada não pertence a esta obra.';
  end if;

  perform 1 from public.fases f where f.id=p_fase_id and f.obra_id=p_obra_id for share;
  if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  perform 1 from public.itens_orcamento i where i.id=any(p_item_ids) for share;
  select count(distinct requested.item_id)
  into v_total_pedido
  from unnest(p_item_ids) as requested(item_id);

  select count(distinct i.id)
  into v_total_valido
  from public.itens_orcamento i
  where i.id = any(p_item_ids)
    and i.fase_id = p_fase_id
    and i.quantidade > 0;

  if v_total_valido <> v_total_pedido then
    raise exception using
      errcode = '23514',
      message = 'Um ou mais itens não pertencem à fase/obra indicada ou não têm quantidade válida.';
  end if;

  insert into public.consultas_subempreitada (
    obra_id,
    fase_id,
    trabalho,
    data_pedido,
    estado
  )
  values (
    p_obra_id,
    p_fase_id,
    btrim(p_trabalho),
    current_date,
    'em_consulta'
  )
  returning * into v_consulta;

  insert into public.consultas_subempreitada_itens (
    consulta_subempreitada_id,
    item_orcamento_id
  )
  select
    v_consulta.id,
    requested.item_id
  from (
    select distinct unnest(p_item_ids) as item_id
  ) requested;

  return v_consulta;
end;
$function$
;
ALTER FUNCTION public.fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_adjudicar_candidato_subempreitada(p_candidato_id uuid, p_data_inicio_prevista date, p_data_fim_prevista date, p_condicao_pagamento text)
 RETURNS subempreitadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_candidato public.consultas_subempreitada_candidatos%rowtype;
  v_consulta public.consultas_subempreitada%rowtype;
  v_subempreitada public.subempreitadas%rowtype;
begin
  if p_data_inicio_prevista is null or p_data_fim_prevista is null then
    raise exception using
      errcode = '23514',
      message = 'As datas previstas de início e fim são obrigatórias.';
  end if;

  if p_data_fim_prevista < p_data_inicio_prevista then
    raise exception using
      errcode = '23514',
      message = 'A data prevista de fim não pode ser anterior ao início.';
  end if;

  if p_condicao_pagamento is null
     or p_condicao_pagamento not in ('imediato', '15_dias', '30_dias') then
    raise exception using
      errcode = '23514',
      message = 'Condição de pagamento inválida.';
  end if;

  select * into v_candidato
  from public.consultas_subempreitada_candidatos
  where id = p_candidato_id for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidato não encontrado.';
  end if;

  select * into v_consulta
  from public.consultas_subempreitada
  where id = v_candidato.consulta_subempreitada_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Consulta não encontrada.';
  end if;

  perform public.fn_financeiro_autorizar_obra(v_consulta.obra_id,false);
  if not public.fn_pode_editar_obra(v_consulta.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para adjudicar nesta obra.';
  end if;

  if v_consulta.fase_id is null then
    raise exception using
      errcode = '23514',
      message = 'A consulta precisa de estar associada a uma fase antes da adjudicação.';
  end if;

  if v_candidato.valor_total is null or v_candidato.valor_total < 0 then
    raise exception using
      errcode = '23514',
      message = 'O candidato precisa de ter um valor total válido.';
  end if;

  perform 1 from public.fases f where f.id=v_consulta.fase_id and f.obra_id=v_consulta.obra_id for share;
  if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  perform 1 from public.fornecedores s join public.obras o on o.id=v_consulta.obra_id
  where s.id=v_candidato.fornecedor_id and s.empresa_id=o.empresa_id for share of s;
  if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  perform 1 from public.consultas_subempreitada_itens ci join public.itens_orcamento i on i.id=ci.item_orcamento_id
  join public.fases f on f.id=i.fase_id where ci.consulta_subempreitada_id=v_consulta.id for share of ci,i,f;
  if exists(select 1 from public.consultas_subempreitada_itens ci left join public.itens_orcamento i on i.id=ci.item_orcamento_id
   left join public.fases f on f.id=i.fase_id where ci.consulta_subempreitada_id=v_consulta.id
   and (f.obra_id is distinct from v_consulta.obra_id or i.fase_id is distinct from v_consulta.fase_id)) then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  update public.consultas_subempreitada_candidatos
  set escolhido = (id = p_candidato_id)
  where consulta_subempreitada_id = v_consulta.id;

  select * into v_subempreitada
  from public.subempreitadas
  where consulta_id = v_consulta.id
  order by criado_em
  limit 1
  for update;

  if found then
  perform public.fn_financeiro_autorizar_obra(v_subempreitada.obra_id,false);
    if v_subempreitada.obra_id is distinct from v_consulta.obra_id then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
    update public.subempreitadas
    set
      obra_id = v_consulta.obra_id,
      fase_id = v_consulta.fase_id,
      fornecedor_id = v_candidato.fornecedor_id,
      especialidade = v_consulta.trabalho,
      valor_adjudicado = v_candidato.valor_total,
      estado = 'em_execucao',
      data_inicio_prevista = p_data_inicio_prevista,
      data_fim_prevista = p_data_fim_prevista,
      condicao_pagamento = p_condicao_pagamento
    where id = v_subempreitada.id
    returning * into v_subempreitada;
  else
    insert into public.subempreitadas (
      obra_id,
      fase_id,
      consulta_id,
      fornecedor_id,
      especialidade,
      valor_adjudicado,
      estado,
      data_inicio_prevista,
      data_fim_prevista,
      condicao_pagamento
    )
    values (
      v_consulta.obra_id,
      v_consulta.fase_id,
      v_consulta.id,
      v_candidato.fornecedor_id,
      v_consulta.trabalho,
      v_candidato.valor_total,
      'em_execucao',
      p_data_inicio_prevista,
      p_data_fim_prevista,
      p_condicao_pagamento
    )
    returning * into v_subempreitada;
  end if;

  update public.consultas_subempreitada
  set
    fornecedor_id = v_candidato.fornecedor_id,
    estado = 'adjudicado',
    data_contrato = coalesce(data_contrato, current_date)
  where id = v_consulta.id;

  return v_subempreitada;
end;
$function$
;
ALTER FUNCTION public.fn_adjudicar_candidato_subempreitada(uuid,date,date,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_adjudicar_candidato_subempreitada(uuid,date,date,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_adjudicar_candidato_subempreitada(uuid,date,date,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_registar_aditamento_subempreitada(p_subempreitada_id uuid, p_descricao text, p_valor numeric, p_alteracao_tee_id uuid DEFAULT NULL::uuid)
 RETURNS subempreitada_aditamentos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_sub public.subempreitadas;
  v_result public.subempreitada_aditamentos;
begin
  select * into v_sub from public.subempreitadas where id=p_subempreitada_id for update;
  if not found then raise exception 'Subempreitada nÃ£o encontrada.' using errcode='P0002'; end if;
  perform public.fn_financeiro_autorizar_obra(v_sub.obra_id,false);
  if not (public.fn_pode_editar_obra(v_sub.obra_id) or public.fn_e_administrativo() or public.fn_e_admin()) then
    raise exception 'Sem permissÃ£o para registar aditamentos nesta obra.' using errcode='42501';
  end if;
  if nullif(btrim(p_descricao),'') is null or p_valor is null or p_valor<=0 then
    raise exception 'DescriÃ§Ã£o e valor positivo sÃ£o obrigatÃ³rios.';
  end if;
  if p_alteracao_tee_id is not null then
    perform 1 from public.alteracoes_tee t where t.id=p_alteracao_tee_id and t.obra_id=v_sub.obra_id for share;
    if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  end if;
  insert into public.subempreitada_aditamentos(
    subempreitada_id,obra_id,alteracao_tee_id,descricao,valor,criado_por
  ) values (
    v_sub.id,v_sub.obra_id,p_alteracao_tee_id,btrim(p_descricao),p_valor,public.fn_utilizador_atual_id()
  ) returning * into v_result;
  return v_result;
end;$function$
;
ALTER FUNCTION public.fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_decidir_aditamento_subempreitada(p_aditamento_id uuid, p_estado text, p_observacao text DEFAULT NULL::text)
 RETURNS subempreitada_aditamentos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_result public.subempreitada_aditamentos; v_obra_id uuid;
begin
  select a.* into v_result from public.subempreitada_aditamentos a where a.id=p_aditamento_id for update;
  if not found then raise exception 'Aditamento indisponível.' using errcode='P0002'; end if;
  select s.obra_id into v_obra_id from public.subempreitadas s where s.id=v_result.subempreitada_id for share;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if v_result.obra_id is distinct from v_obra_id then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  if v_result.alteracao_tee_id is not null then
    perform 1 from public.alteracoes_tee t where t.id=v_result.alteracao_tee_id and t.obra_id=v_obra_id for share;
    if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  end if;
  if not (public.fn_e_admin() or exists (
    select 1 from public.utilizadores u where u.id=public.fn_utilizador_atual_id()
      and u.funcao in ('gerencia','gestao_plataforma') and coalesce(u.ativo,true)
  )) then
    raise exception 'A aprovaÃ§Ã£o de aditamentos estÃ¡ reservada Ã  GerÃªncia/GestÃ£o da Plataforma.' using errcode='42501';
  end if;
  if p_estado not in ('aprovado','rejeitado') then raise exception 'DecisÃ£o invÃ¡lida.'; end if;
  update public.subempreitada_aditamentos
  set estado=p_estado,observacao_decisao=nullif(btrim(p_observacao),''),
      decidido_por=public.fn_utilizador_atual_id(),decidido_em=now()
  where id=p_aditamento_id and estado='pendente'
  returning * into v_result;
  if not found then raise exception 'Aditamento pendente nÃ£o encontrado.' using errcode='P0002'; end if;
  return v_result;
end;$function$
;
ALTER FUNCTION public.fn_decidir_aditamento_subempreitada(uuid,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_decidir_aditamento_subempreitada(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_decidir_aditamento_subempreitada(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_concluir_subempreitada_com_avaliacao(p_subempreitada_id uuid, p_qualidade integer, p_cumprimento_prazo integer, p_seguranca integer, p_comunicacao integer, p_observacoes text DEFAULT NULL::text)
 RETURNS subempreitadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_subempreitada public.subempreitadas%rowtype;
  v_utilizador_id uuid;
begin
  select * into v_subempreitada
  from public.subempreitadas
  where id = p_subempreitada_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Subempreitada não encontrada.';
  end if;

  perform public.fn_financeiro_autorizar_obra(v_subempreitada.obra_id,false);
  if not public.fn_pode_editar_obra(v_subempreitada.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para concluir nesta obra.';
  end if;

  if p_qualidade is null
     or p_cumprimento_prazo is null
     or p_seguranca is null
     or p_comunicacao is null
     or p_qualidade not between 1 and 5
     or p_cumprimento_prazo not between 1 and 5
     or p_seguranca not between 1 and 5
     or p_comunicacao not between 1 and 5 then
    raise exception using
      errcode = '23514',
      message = 'Todos os critérios da avaliação devem estar entre 1 e 5.';
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();

  delete from public.avaliacoes_subempreiteiro
  where subempreitada_id = v_subempreitada.id;

  insert into public.avaliacoes_subempreiteiro (
    obra_id,
    subempreitada_id,
    fornecedor_id,
    qualidade,
    cumprimento_prazo,
    seguranca,
    comunicacao,
    observacoes,
    avaliado_por
  )
  values (
    v_subempreitada.obra_id,
    v_subempreitada.id,
    v_subempreitada.fornecedor_id,
    p_qualidade,
    p_cumprimento_prazo,
    p_seguranca,
    p_comunicacao,
    nullif(trim(p_observacoes), ''),
    v_utilizador_id
  );

  update public.subempreitadas
  set estado = 'concluido'
  where id = v_subempreitada.id
  returning * into v_subempreitada;

  return v_subempreitada;
end;
$function$
;
ALTER FUNCTION public.fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_importar_tees_xlsx(p_linhas jsonb, p_nome_ficheiro text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_linha jsonb;
  v_item jsonb;
  v_tee public.alteracoes_tee%rowtype;
  v_importadas integer := 0;
  v_itens integer := 0;
  v_obra_id uuid;
  v_fase_id uuid;
begin
  perform public.fn_economico_ator_atual();
  if jsonb_typeof(p_linhas) <> 'array' then
    raise exception using
      errcode = '22023',
      message = 'As linhas da importação são inválidas.';
  end if;

  for v_linha in
    select value
    from jsonb_array_elements(p_linhas)
  loop
    v_obra_id := nullif(v_linha ->> 'obra_id', '')::uuid;
    v_fase_id := nullif(v_linha ->> 'fase_id', '')::uuid;

    perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
    if not public.fn_pode_editar_obra(v_obra_id) then
      raise exception using
        errcode = '42501',
        message = 'Sem permissão para importar TEEs nesta obra.';
    end if;

    if nullif(btrim(v_linha ->> 'numero'), '') is null then
      raise exception using
        errcode = '23514',
        message = 'O Nº TEE é obrigatório.';
    end if;

    if nullif(btrim(v_linha ->> 'descricao'), '') is null then
      raise exception using
        errcode = '23514',
        message = 'A descrição do TEE é obrigatória.';
    end if;

    if not exists (
      select 1
      from public.fases f
      where f.id = v_fase_id
        and f.obra_id = v_obra_id
    ) then
      raise exception using
        errcode = '23514',
        message = 'A fase do TEE não pertence à obra.';
    end if;

    if v_fase_id is not null then
      perform 1 from public.fases f where f.id=v_fase_id and f.obra_id=v_obra_id for share;
      if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
    end if;
    insert into public.alteracoes_tee (
      obra_id,
      fase_id,
      numero,
      descricao,
      especialidade,
      valor,
      preco_custo,
      dias_prorrogacao,
      data_envio,
      data_resposta,
      estado_aprovacao_cliente,
      revisao,
      data_inicio_execucao,
      data_fim_execucao
    )
    values (
      v_obra_id,
      v_fase_id,
      btrim(v_linha ->> 'numero'),
      nullif(v_linha ->> 'descricao', ''),
      nullif(v_linha ->> 'especialidade', ''),
      nullif(v_linha ->> 'valor', '')::numeric,
      nullif(v_linha ->> 'preco_custo', '')::numeric,
      coalesce(
        nullif(v_linha ->> 'dias_prorrogacao', '')::numeric,
        0
      ),
      nullif(v_linha ->> 'data_envio', '')::date,
      nullif(v_linha ->> 'data_resposta', '')::date,
      coalesce(
        nullif(v_linha ->> 'estado_aprovacao_cliente', ''),
        'pendente'
      ),
      coalesce(
        nullif(v_linha ->> 'revisao', ''),
        'REV00'
      ),
      nullif(v_linha ->> 'data_inicio_execucao', '')::date,
      nullif(v_linha ->> 'data_fim_execucao', '')::date
    )
    returning * into v_tee;

    if jsonb_typeof(v_linha -> 'itens') = 'array' then
      for v_item in
        select value
        from jsonb_array_elements(v_linha -> 'itens')
      loop
        insert into public.alteracoes_tee_itens (
          tee_id,
          numero_artigo,
          descricao,
          unidade,
          quantidade,
          preco_unitario,
          valor_total
        )
        values (
          v_tee.id,
          btrim(v_item ->> 'numero_artigo'),
          btrim(v_item ->> 'descricao'),
          nullif(v_item ->> 'unidade', ''),
          nullif(v_item ->> 'quantidade', '')::numeric,
          nullif(v_item ->> 'preco_unitario', '')::numeric,
          coalesce(
            nullif(v_item ->> 'valor_total', '')::numeric,
            nullif(v_item ->> 'quantidade', '')::numeric
              * nullif(v_item ->> 'preco_unitario', '')::numeric
          )
        );

        v_itens := v_itens + 1;
      end loop;
    end if;

    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx(
    'tees',
    p_nome_ficheiro,
    v_importadas,
    jsonb_build_object('itens_importados', v_itens)
  );

  return jsonb_build_object(
    'importadas', v_importadas,
    'itens_importados', v_itens
  );
end;
$function$
;
ALTER FUNCTION public.fn_importar_tees_xlsx(jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_importar_tees_xlsx(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_importar_tees_xlsx(jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_importar_tees_revisoes(p_version integer, p_obra_id uuid, p_linhas jsonb, p_nome_ficheiro text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_hash text;

  v_importacao_id uuid;
  v_importacao public.tee_importacoes_revisoes%rowtype;

  v_row jsonb;
  v_expected jsonb;
  v_current public.alteracoes_tee%rowtype;

  v_tee_id uuid;

  v_numero text;
  v_numero_normalizado text;

  v_client_state text;
  v_operational_state text;

  v_items jsonb;
  v_items_snapshot jsonb;

  v_field text;

  v_changed boolean;
  v_items_changed boolean;

  v_importadas integer := 0;

  v_result jsonb;
BEGIN

  -- ----------------------------------------------------------
  -- Validação geral
  -- ----------------------------------------------------------

  IF p_version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: versão de contrato inválida.';
  END IF;

  IF p_obra_id IS NULL
     OR p_linhas IS NULL
     OR jsonb_typeof(p_linhas) <> 'array'
  THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: obra e linhas são obrigatórias.';
  END IF;

  perform public.fn_financeiro_autorizar_obra(p_obra_id,false);
  IF NOT COALESCE(
    public.fn_pode_editar_obra(p_obra_id),
    false
  ) THEN
    RAISE EXCEPTION
      'FORBIDDEN: sem permissão para editar esta obra.'
      USING ERRCODE = '42501';
  END IF;

  -- Validate every referenced entity before import/replay/write.
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_linhas) LOOP
    IF NULLIF(v_row->>'obra_id','') IS NOT NULL THEN
      PERFORM public.fn_financeiro_autorizar_obra((v_row->>'obra_id')::uuid,false);
      IF (v_row->>'obra_id')::uuid IS DISTINCT FROM p_obra_id THEN raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; END IF;
    END IF;
    IF NULLIF(v_row->>'id','') IS NOT NULL THEN
      SELECT * INTO v_current FROM public.alteracoes_tee WHERE id=(v_row->>'id')::uuid FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'TEE indisponível.' USING ERRCODE='P0002'; END IF;
      PERFORM public.fn_financeiro_autorizar_obra(v_current.obra_id,false);
      IF v_current.obra_id IS DISTINCT FROM p_obra_id THEN raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; END IF;
      IF v_current.fase_id IS NOT NULL THEN
        PERFORM 1 FROM public.fases WHERE id=v_current.fase_id AND obra_id=p_obra_id FOR SHARE;
        IF NOT FOUND THEN raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; END IF;
      END IF;
    END IF;
    IF NULLIF(v_row->>'fase_id','') IS NOT NULL THEN
      PERFORM 1 FROM public.fases WHERE id=(v_row->>'fase_id')::uuid AND obra_id=p_obra_id FOR SHARE;
      IF NOT FOUND THEN raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; END IF;
    END IF;
  END LOOP;
  v_user := public.fn_utilizador_atual_id();

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'primeline-tee-revisoes:' || p_obra_id::text,
      0
    )
  );

  v_hash := md5(
    jsonb_build_object(
      'version', p_version,
      'obra_id', p_obra_id,
      'nome_ficheiro', p_nome_ficheiro,
      'linhas', p_linhas
    )::text
  );


  -- ----------------------------------------------------------
  -- Idempotência da importação inteira
  -- ----------------------------------------------------------

  SELECT *
  INTO v_importacao
  FROM public.tee_importacoes_revisoes
  WHERE obra_id = p_obra_id
    AND payload_hash = v_hash;

  IF FOUND
     AND v_importacao.resultado IS NOT NULL
  THEN
    RETURN v_importacao.resultado;
  END IF;


  INSERT INTO public.tee_importacoes_revisoes (
    obra_id,
    payload_hash,
    nome_ficheiro,
    payload,
    criado_por
  )
  VALUES (
    p_obra_id,
    v_hash,
    p_nome_ficheiro,
    p_linhas,
    v_user
  )
  ON CONFLICT (obra_id, payload_hash)
  DO UPDATE SET
    nome_ficheiro = EXCLUDED.nome_ficheiro
  RETURNING id
  INTO v_importacao_id;


  -- Não alimentar venda contratual nem previsão mensal legada
  -- durante esta importação.
  PERFORM set_config(
    'primeline.tee_revision_import',
    'on',
    true
  );


  -- ==========================================================
  -- PROCESSAR LINHAS
  -- ==========================================================

  FOR v_row IN
    SELECT value
    FROM jsonb_array_elements(p_linhas)
  LOOP

    v_expected := v_row->'expected';

    -- --------------------------------------------------------
    -- Obra
    -- --------------------------------------------------------

    IF v_row ? 'obra_id'
       AND NULLIF(v_row->>'obra_id', '') IS NOT NULL
       AND (v_row->>'obra_id')::uuid IS DISTINCT FROM p_obra_id
    THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: TEE de outra obra.';
    END IF;


    -- ========================================================
    -- TEE EXISTENTE
    -- ========================================================

    IF NULLIF(v_row->>'id', '') IS NOT NULL THEN

      v_tee_id := (v_row->>'id')::uuid;

      SELECT *
      INTO v_current
      FROM public.alteracoes_tee
      WHERE id = v_tee_id
      FOR UPDATE;

      IF NOT FOUND
         OR v_current.obra_id IS DISTINCT FROM p_obra_id
      THEN
        RAISE EXCEPTION
          'AMBIGUOUS_TEE: TEE não encontrado nesta obra.';
      END IF;

      IF v_expected IS NULL
         OR jsonb_typeof(v_expected) <> 'object'
      THEN
        RAISE EXCEPTION
          'STALE_REVISION: snapshot esperado em falta.';
      END IF;


      -- ------------------------------------------------------
      -- Concorrência otimista
      -- ------------------------------------------------------

      FOREACH v_field IN ARRAY ARRAY[
        'id',
        'obra_id',
        'fase_id',
        'numero',
        'descricao',
        'especialidade',
        'valor',
        'preco_custo',
        'dias_prorrogacao',
        'data_envio',
        'data_resposta',
        'revisao',
        'data_inicio_execucao',
        'data_fim_execucao',
        'estado_aprovacao_cliente',
        'estado_operacional'
      ]
      LOOP
        IF v_expected ? v_field
           AND (
             to_jsonb(v_current)->v_field
             IS DISTINCT FROM
             v_expected->v_field
           )
        THEN
          RAISE EXCEPTION
            'STALE_REVISION: o TEE % foi alterado. Atualize antes de importar.',
            v_current.numero;
        END IF;
      END LOOP;

      v_numero :=
        CASE
          WHEN v_row ? 'numero'
            THEN NULLIF(btrim(v_row->>'numero'), '')
          ELSE v_current.numero
        END;

      IF v_numero IS NULL THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: número TEE obrigatório.';
      END IF;

      v_numero_normalizado :=
        public.fn_normalizar_numero_tee(v_numero);


      IF EXISTS (
        SELECT 1
        FROM public.alteracoes_tee t
        WHERE t.obra_id = p_obra_id
          AND t.id <> v_current.id
          AND public.fn_normalizar_numero_tee(t.numero)
              = v_numero_normalizado
      ) THEN
        RAISE EXCEPTION
          'AMBIGUOUS_TEE: já existe outro TEE com o número %.',
          v_numero;
      END IF;


      -- ------------------------------------------------------
      -- Estados
      -- ------------------------------------------------------

      v_client_state :=
        CASE
          WHEN v_row ? 'estado_aprovacao_cliente'
            THEN NULLIF(v_row->>'estado_aprovacao_cliente', '')
          ELSE v_current.estado_aprovacao_cliente
        END;

      v_operational_state :=
        CASE
          WHEN v_row ? 'estado_operacional'
            THEN NULLIF(v_row->>'estado_operacional', '')
          ELSE v_current.estado_operacional
        END;

      IF v_operational_state IS NULL THEN
        v_operational_state :=
          CASE
            WHEN v_client_state = 'aprovado'
              THEN 'aprovado'

            WHEN v_client_state = 'recusado'
              THEN 'rejeitado'

            WHEN COALESCE(
              NULLIF(v_row->>'data_envio', '')::date,
              v_current.data_envio
            ) IS NOT NULL
              THEN 'aguarda_resposta'

            ELSE 'em_elaboracao'
          END;
      END IF;

      IF v_client_state NOT IN (
        'pendente',
        'aprovado',
        'recusado'
      )
      OR v_operational_state NOT IN (
        'em_elaboracao',
        'aguarda_resposta',
        'aprovado',
        'rejeitado'
      )
      OR (
        v_operational_state IN (
          'em_elaboracao',
          'aguarda_resposta'
        )
        AND v_client_state <> 'pendente'
      )
      OR (
        v_operational_state = 'aprovado'
        AND v_client_state <> 'aprovado'
      )
      OR (
        v_operational_state = 'rejeitado'
        AND v_client_state <> 'recusado'
      )
      THEN
        RAISE EXCEPTION
          'INVALID_STATE: estado operacional e aprovação do cliente são incompatíveis.';
      END IF;


      -- ------------------------------------------------------
      -- Ver se cabeçalho mudou
      -- ------------------------------------------------------

      v_changed := false;

      FOREACH v_field IN ARRAY ARRAY[
        'fase_id',
        'numero',
        'descricao',
        'especialidade',
        'valor',
        'preco_custo',
        'dias_prorrogacao',
        'data_envio',
        'data_resposta',
        'revisao',
        'data_inicio_execucao',
        'data_fim_execucao',
        'estado_aprovacao_cliente',
        'estado_operacional'
      ]
      LOOP
        IF v_row ? v_field
           AND (
             to_jsonb(v_current)->v_field
             IS DISTINCT FROM
             v_row->v_field
           )
        THEN
          v_changed := true;
        END IF;
      END LOOP;

      IF v_current.estado_operacional
         IS DISTINCT FROM v_operational_state
      THEN
        v_changed := true;
      END IF;

      IF v_current.estado_aprovacao_cliente
         IS DISTINCT FROM v_client_state
      THEN
        v_changed := true;
      END IF;


      -- ------------------------------------------------------
      -- Itens
      -- ------------------------------------------------------

      v_items_changed := false;

      IF v_row ? 'itens' THEN

        v_items := COALESCE(
          v_row->'itens',
          '[]'::jsonb
        );

        IF jsonb_typeof(v_items) <> 'array' THEN
          RAISE EXCEPTION
            'VALIDATION_FAILED: itens do TEE inválidos.';
        END IF;


        IF EXISTS (
          SELECT 1
          FROM jsonb_array_elements(v_items) i(value)
          WHERE NULLIF(
            btrim(i.value->>'numero_artigo'),
            ''
          ) IS NULL
          OR NULLIF(
            btrim(i.value->>'descricao'),
            ''
          ) IS NULL
        ) THEN
          RAISE EXCEPTION
            'VALIDATION_FAILED: item TEE sem Nº Artigo ou Descrição.';
        END IF;


        IF EXISTS (
          SELECT 1
          FROM (
            SELECT
              lower(
                regexp_replace(
                  btrim(i.value->>'numero_artigo'),
                  '\s+',
                  ' ',
                  'g'
                )
              ) AS numero_artigo_normalizado,
              count(*) AS quantidade
            FROM jsonb_array_elements(v_items) i(value)
            GROUP BY 1
            HAVING count(*) > 1
          ) x
        ) THEN
          RAISE EXCEPTION
            'VALIDATION_FAILED: existem artigos TEE duplicados no ficheiro.';
        END IF;


        SELECT COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'numero_artigo', numero_artigo,
              'descricao', descricao,
              'unidade', unidade,
              'quantidade', quantidade,
              'preco_unitario', preco_unitario,
              'valor_total', valor_total
            )
            ORDER BY
              numero_artigo,
              descricao
          ),
          '[]'::jsonb
        )
        INTO v_items_snapshot
        FROM (
          SELECT
            i.numero_artigo,
            i.descricao,
            i.unidade,
            i.quantidade,
            i.preco_unitario,
            i.valor_total
          FROM public.alteracoes_tee_itens i
          WHERE i.tee_id = v_current.id
        ) atual;


        IF v_items_snapshot
           IS DISTINCT FROM
           (
             SELECT COALESCE(
               jsonb_agg(
                 jsonb_build_object(
                   'numero_artigo',
                     btrim(x.value->>'numero_artigo'),

                   'descricao',
                     btrim(x.value->>'descricao'),

                   'unidade',
                     NULLIF(
                       btrim(x.value->>'unidade'),
                       ''
                     ),

                   'quantidade',
                     NULLIF(
                       x.value->>'quantidade',
                       ''
                     )::numeric,

                   'preco_unitario',
                     NULLIF(
                       x.value->>'preco_unitario',
                       ''
                     )::numeric,

                   'valor_total',
                     COALESCE(
                       NULLIF(
                         x.value->>'valor_total',
                         ''
                       )::numeric,
                       NULLIF(
                         x.value->>'quantidade',
                         ''
                       )::numeric
                       *
                       NULLIF(
                         x.value->>'preco_unitario',
                         ''
                       )::numeric
                     )
                 )
                 ORDER BY
                   btrim(x.value->>'numero_artigo'),
                   btrim(x.value->>'descricao')
               ),
               '[]'::jsonb
             )
             FROM jsonb_array_elements(v_items) x(value)
           )
        THEN
          v_items_changed := true;
        END IF;

      END IF;


      -- ------------------------------------------------------
      -- Sem alteração
      -- ------------------------------------------------------

      IF NOT v_changed
         AND NOT v_items_changed
      THEN
        CONTINUE;
      END IF;


      -- ------------------------------------------------------
      -- Snapshot imutável ANTES da alteração
      -- ------------------------------------------------------

      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(i)
          ORDER BY i.numero_artigo, i.id
        ),
        '[]'::jsonb
      )
      INTO v_items_snapshot
      FROM public.alteracoes_tee_itens i
      WHERE i.tee_id = v_current.id;


      INSERT INTO public.alteracoes_tee_revisoes (
        tee_id,
        obra_id,
        importacao_id,
        tipo_snapshot,

        numero,
        numero_normalizado,
        revisao,

        descricao,
        especialidade,
        fase_id,

        valor,
        preco_custo,
        dias_prorrogacao,

        estado_aprovacao_cliente,
        estado_operacional,

        data_envio,
        data_resposta,
        data_inicio_execucao,
        data_fim_execucao,

        snapshot,
        itens_snapshot,

        nome_ficheiro,
        criado_por
      )
      VALUES (
        v_current.id,
        v_current.obra_id,
        v_importacao_id,
        'anterior',

        v_current.numero,
        public.fn_normalizar_numero_tee(
          v_current.numero
        ),
        v_current.revisao,

        v_current.descricao,
        v_current.especialidade,
        v_current.fase_id,

        v_current.valor,
        v_current.preco_custo,
        v_current.dias_prorrogacao,

        v_current.estado_aprovacao_cliente,
        v_current.estado_operacional,

        v_current.data_envio,
        v_current.data_resposta,
        v_current.data_inicio_execucao,
        v_current.data_fim_execucao,

        to_jsonb(v_current),
        v_items_snapshot,

        p_nome_ficheiro,
        v_user
      );


      -- ------------------------------------------------------
      -- Atualizar cabeçalho
      -- Campos omitidos permanecem intactos.
      -- JSON null funciona como limpeza explícita.
      -- ------------------------------------------------------

      UPDATE public.alteracoes_tee
      SET
        fase_id =
          CASE
            WHEN v_row ? 'fase_id'
              THEN NULLIF(
                v_row->>'fase_id',
                ''
              )::uuid
            ELSE fase_id
          END,

        numero = v_numero,

        descricao =
          CASE
            WHEN v_row ? 'descricao'
              THEN NULLIF(
                btrim(v_row->>'descricao'),
                ''
              )
            ELSE descricao
          END,

        especialidade =
          CASE
            WHEN v_row ? 'especialidade'
              THEN NULLIF(
                btrim(v_row->>'especialidade'),
                ''
              )
            ELSE especialidade
          END,

        valor =
          CASE
            WHEN v_row ? 'valor'
              THEN NULLIF(
                v_row->>'valor',
                ''
              )::numeric
            ELSE valor
          END,

        preco_custo =
          CASE
            WHEN v_row ? 'preco_custo'
              THEN NULLIF(
                v_row->>'preco_custo',
                ''
              )::numeric
            ELSE preco_custo
          END,

        dias_prorrogacao =
          CASE
            WHEN v_row ? 'dias_prorrogacao'
              THEN COALESCE(
                NULLIF(
                  v_row->>'dias_prorrogacao',
                  ''
                )::integer,
                0
              )
            ELSE dias_prorrogacao
          END,

        data_envio =
          CASE
            WHEN v_row ? 'data_envio'
              THEN NULLIF(
                v_row->>'data_envio',
                ''
              )::date
            ELSE data_envio
          END,

        data_resposta =
          CASE
            WHEN v_row ? 'data_resposta'
              THEN NULLIF(
                v_row->>'data_resposta',
                ''
              )::date
            ELSE data_resposta
          END,

        revisao =
          CASE
            WHEN v_row ? 'revisao'
              THEN NULLIF(
                btrim(v_row->>'revisao'),
                ''
              )
            ELSE revisao
          END,

        data_inicio_execucao =
          CASE
            WHEN v_row ? 'data_inicio_execucao'
              THEN NULLIF(
                v_row->>'data_inicio_execucao',
                ''
              )::date
            ELSE data_inicio_execucao
          END,

        data_fim_execucao =
          CASE
            WHEN v_row ? 'data_fim_execucao'
              THEN NULLIF(
                v_row->>'data_fim_execucao',
                ''
              )::date
            ELSE data_fim_execucao
          END,

        estado_aprovacao_cliente =
          v_client_state,

        estado_operacional =
          v_operational_state

      WHERE id = v_current.id;


      -- ------------------------------------------------------
      -- Substituir itens SOMENTE se vieram no payload
      -- ------------------------------------------------------

      IF v_row ? 'itens'
         AND v_items_changed
      THEN
        DELETE FROM public.alteracoes_tee_itens
        WHERE tee_id = v_current.id;

        INSERT INTO public.alteracoes_tee_itens (
          tee_id,
          numero_artigo,
          descricao,
          unidade,
          quantidade,
          preco_unitario,
          valor_total
        )
        SELECT
          v_current.id,

          btrim(x.value->>'numero_artigo'),

          btrim(x.value->>'descricao'),

          NULLIF(
            btrim(x.value->>'unidade'),
            ''
          ),

          NULLIF(
            x.value->>'quantidade',
            ''
          )::numeric,

          NULLIF(
            x.value->>'preco_unitario',
            ''
          )::numeric,

          COALESCE(
            NULLIF(
              x.value->>'valor_total',
              ''
            )::numeric,

            NULLIF(
              x.value->>'quantidade',
              ''
            )::numeric
            *
            NULLIF(
              x.value->>'preco_unitario',
              ''
            )::numeric
          )

        FROM jsonb_array_elements(
          COALESCE(v_items, '[]'::jsonb)
        ) x(value);
      END IF;

      v_importadas := v_importadas + 1;


    -- ========================================================
    -- NOVO TEE
    -- ========================================================

    ELSE

      IF v_expected IS NOT NULL
         AND v_expected <> 'null'::jsonb
      THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: TEE novo não deve possuir snapshot anterior.';
      END IF;

      v_numero :=
        NULLIF(
          btrim(v_row->>'numero'),
          ''
        );

      IF v_numero IS NULL THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: número TEE obrigatório.';
      END IF;

      IF NULLIF(
        btrim(v_row->>'descricao'),
        ''
      ) IS NULL THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: descrição TEE obrigatória.';
      END IF;

      v_numero_normalizado :=
        public.fn_normalizar_numero_tee(
          v_numero
        );


      IF EXISTS (
        SELECT 1
        FROM public.alteracoes_tee t
        WHERE t.obra_id = p_obra_id
          AND public.fn_normalizar_numero_tee(t.numero)
              = v_numero_normalizado
      ) THEN
        RAISE EXCEPTION
          'AMBIGUOUS_TEE: já existe um TEE com o número %.',
          v_numero;
      END IF;


      v_client_state :=
        COALESCE(
          NULLIF(
            v_row->>'estado_aprovacao_cliente',
            ''
          ),
          'pendente'
        );

      v_operational_state :=
        NULLIF(
          v_row->>'estado_operacional',
          ''
        );

      IF v_operational_state IS NULL THEN
        v_operational_state :=
          CASE
            WHEN v_client_state = 'aprovado'
              THEN 'aprovado'

            WHEN v_client_state = 'recusado'
              THEN 'rejeitado'

            WHEN NULLIF(
              v_row->>'data_envio',
              ''
            ) IS NOT NULL
              THEN 'aguarda_resposta'

            ELSE 'em_elaboracao'
          END;
      END IF;


      IF (
        v_operational_state IN (
          'em_elaboracao',
          'aguarda_resposta'
        )
        AND v_client_state <> 'pendente'
      )
      OR (
        v_operational_state = 'aprovado'
        AND v_client_state <> 'aprovado'
      )
      OR (
        v_operational_state = 'rejeitado'
        AND v_client_state <> 'recusado'
      )
      THEN
        RAISE EXCEPTION
          'INVALID_STATE: estado operacional e aprovação do cliente são incompatíveis.';
      END IF;


      IF NULLIF(
        v_row->>'data_inicio_execucao',
        ''
      ) IS NOT NULL
      AND NULLIF(
        v_row->>'data_fim_execucao',
        ''
      ) IS NOT NULL
      AND (
        v_row->>'data_fim_execucao'
      )::date
      <
      (
        v_row->>'data_inicio_execucao'
      )::date
      THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: fim de execução anterior ao início.';
      END IF;


      INSERT INTO public.alteracoes_tee (
        obra_id,
        fase_id,
        numero,
        descricao,
        especialidade,
        valor,
        preco_custo,
        dias_prorrogacao,
        data_envio,
        data_resposta,
        revisao,
        data_inicio_execucao,
        data_fim_execucao,
        estado_aprovacao_cliente,
        estado_operacional
      )
      VALUES (
        p_obra_id,

        NULLIF(
          v_row->>'fase_id',
          ''
        )::uuid,

        v_numero,

        btrim(
          v_row->>'descricao'
        ),

        NULLIF(
          btrim(v_row->>'especialidade'),
          ''
        ),

        NULLIF(
          v_row->>'valor',
          ''
        )::numeric,

        NULLIF(
          v_row->>'preco_custo',
          ''
        )::numeric,

        COALESCE(
          NULLIF(
            v_row->>'dias_prorrogacao',
            ''
          )::integer,
          0
        ),

        NULLIF(
          v_row->>'data_envio',
          ''
        )::date,

        NULLIF(
          v_row->>'data_resposta',
          ''
        )::date,

        COALESCE(
          NULLIF(
            btrim(v_row->>'revisao'),
            ''
          ),
          'REV00'
        ),

        NULLIF(
          v_row->>'data_inicio_execucao',
          ''
        )::date,

        NULLIF(
          v_row->>'data_fim_execucao',
          ''
        )::date,

        v_client_state,
        v_operational_state
      )
      RETURNING id
      INTO v_tee_id;


      IF v_row ? 'itens' THEN

        v_items :=
          COALESCE(
            v_row->'itens',
            '[]'::jsonb
          );

        IF jsonb_typeof(v_items) <> 'array' THEN
          RAISE EXCEPTION
            'VALIDATION_FAILED: itens do TEE inválidos.';
        END IF;

        INSERT INTO public.alteracoes_tee_itens (
          tee_id,
          numero_artigo,
          descricao,
          unidade,
          quantidade,
          preco_unitario,
          valor_total
        )
        SELECT
          v_tee_id,

          btrim(x.value->>'numero_artigo'),

          btrim(x.value->>'descricao'),

          NULLIF(
            btrim(x.value->>'unidade'),
            ''
          ),

          NULLIF(
            x.value->>'quantidade',
            ''
          )::numeric,

          NULLIF(
            x.value->>'preco_unitario',
            ''
          )::numeric,

          COALESCE(
            NULLIF(
              x.value->>'valor_total',
              ''
            )::numeric,

            NULLIF(
              x.value->>'quantidade',
              ''
            )::numeric
            *
            NULLIF(
              x.value->>'preco_unitario',
              ''
            )::numeric
          )

        FROM jsonb_array_elements(v_items) x(value);

      END IF;


      SELECT *
      INTO v_current
      FROM public.alteracoes_tee
      WHERE id = v_tee_id;


      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(i)
          ORDER BY i.numero_artigo, i.id
        ),
        '[]'::jsonb
      )
      INTO v_items_snapshot
      FROM public.alteracoes_tee_itens i
      WHERE i.tee_id = v_tee_id;


      INSERT INTO public.alteracoes_tee_revisoes (
        tee_id,
        obra_id,
        importacao_id,
        tipo_snapshot,

        numero,
        numero_normalizado,
        revisao,

        descricao,
        especialidade,
        fase_id,

        valor,
        preco_custo,
        dias_prorrogacao,

        estado_aprovacao_cliente,
        estado_operacional,

        data_envio,
        data_resposta,
        data_inicio_execucao,
        data_fim_execucao,

        snapshot,
        itens_snapshot,

        nome_ficheiro,
        criado_por
      )
      VALUES (
        v_current.id,
        v_current.obra_id,
        v_importacao_id,
        'criacao',

        v_current.numero,
        public.fn_normalizar_numero_tee(
          v_current.numero
        ),
        v_current.revisao,

        v_current.descricao,
        v_current.especialidade,
        v_current.fase_id,

        v_current.valor,
        v_current.preco_custo,
        v_current.dias_prorrogacao,

        v_current.estado_aprovacao_cliente,
        v_current.estado_operacional,

        v_current.data_envio,
        v_current.data_resposta,
        v_current.data_inicio_execucao,
        v_current.data_fim_execucao,

        to_jsonb(v_current),
        v_items_snapshot,

        p_nome_ficheiro,
        v_user
      );

      v_importadas := v_importadas + 1;

    END IF;

  END LOOP;


  -- ==========================================================
  -- RESULTADO
  -- ==========================================================

  v_result :=
    jsonb_build_object(
      'version', 1,
      'committed', true,
      'importadas', v_importadas
    );

  UPDATE public.tee_importacoes_revisoes
  SET
    importadas = v_importadas,
    resultado = v_result
  WHERE id = v_importacao_id;

  RETURN v_result;

EXCEPTION

  WHEN unique_violation THEN
    RAISE EXCEPTION
      'AMBIGUOUS_TEE: número TEE duplicado nesta obra.';

END;
$function$
;
ALTER FUNCTION public.fn_importar_tees_revisoes(integer,uuid,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_importar_tees_revisoes(integer,uuid,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_importar_tees_revisoes(integer,uuid,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_importar_subempreitadas_xlsx(p_linhas jsonb, p_nome_ficheiro text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_linha jsonb;
  v_consulta public.consultas_subempreitada%rowtype;
  v_candidato public.consultas_subempreitada_candidatos%rowtype;
  v_subempreitada public.subempreitadas%rowtype;
  v_importadas integer := 0;
  v_estado text;
  v_obra_id uuid;
  v_fase_id uuid;
  v_fornecedor_id uuid;
begin
  perform public.fn_economico_ator_atual();
  if jsonb_typeof(p_linhas) <> 'array' then
    raise exception using
      errcode = '22023',
      message = 'As linhas da importação são inválidas.';
  end if;

  for v_linha in
    select value
    from jsonb_array_elements(p_linhas)
  loop
    v_obra_id := nullif(v_linha ->> 'obra_id', '')::uuid;
    v_fase_id := nullif(v_linha ->> 'fase_id', '')::uuid;
    v_fornecedor_id :=
      nullif(v_linha ->> 'fornecedor_id', '')::uuid;
    v_estado := v_linha ->> 'estado';

    perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
    if not public.fn_pode_editar_obra(v_obra_id) then
      raise exception using
        errcode = '42501',
        message =
          'Sem permissão para importar subempreitadas nesta obra.';
    end if;

    if nullif(btrim(v_linha ->> 'trabalho'), '') is null
       or v_estado not in (
         'em_consulta',
         'recusado',
         'adjudicado',
         'em_execucao',
         'concluido'
       )
    then
      raise exception using
        errcode = '23514',
        message = 'Linha de subempreitada inválida.';
    end if;

    if v_fase_id is not null
       and not exists (
         select 1
         from public.fases f
         where f.id = v_fase_id
           and f.obra_id = v_obra_id
       )
    then
      raise exception using
        errcode = '23514',
        message = 'A fase não pertence à obra indicada.';
    end if;

    if v_fornecedor_id is not null
       and not exists (
         select 1
         from public.fornecedores f
         where f.id = v_fornecedor_id
       )
    then
      raise exception using
        errcode = '23503',
        message =
          'Fornecedor inexistente. Nenhum fornecedor foi criado automaticamente.';
    end if;

    if v_estado in (
         'adjudicado',
         'em_execucao',
         'concluido'
       )
       and (
         v_fase_id is null
         or v_fornecedor_id is null
         or nullif(
           v_linha ->> 'valor_adjudicado',
           ''
         ) is null
       )
    then
      raise exception using
        errcode = '23514',
        message =
          'Uma subempreitada adjudicada exige fase, fornecedor e valor.';
    end if;

    if v_fase_id is not null then
      perform 1 from public.fases f where f.id=v_fase_id and f.obra_id=v_obra_id for share;
      if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
    end if;
    if v_fornecedor_id is not null then
      perform 1 from public.fornecedores s join public.obras o on o.id=v_obra_id
      where s.id=v_fornecedor_id and s.empresa_id=o.empresa_id for share of s;
      if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
    end if;
    insert into public.consultas_subempreitada (
      obra_id,
      fase_id,
      trabalho,
      data_pedido,
      data_proposta,
      custo_direto,
      preco_venda,
      margem_prevista,
      fornecedor_id,
      data_contrato,
      estado
    )
    values (
      v_obra_id,
      v_fase_id,
      btrim(v_linha ->> 'trabalho'),
      coalesce(
        nullif(v_linha ->> 'data_pedido', '')::date,
        current_date
      ),
      nullif(v_linha ->> 'data_proposta', '')::date,
      nullif(v_linha ->> 'custo_direto', '')::numeric,
      nullif(v_linha ->> 'preco_venda', '')::numeric,
      nullif(v_linha ->> 'margem_prevista', '')::numeric,
      v_fornecedor_id,
      nullif(v_linha ->> 'data_contrato', '')::date,
      case
        when v_estado in (
          'adjudicado',
          'em_execucao',
          'concluido'
        )
        then 'adjudicado'
        else v_estado
      end
    )
    returning * into v_consulta;

    if v_fornecedor_id is not null then
      insert into public.consultas_subempreitada_candidatos (
        consulta_subempreitada_id,
        fornecedor_id,
        valor_total,
        escolhido
      )
      values (
        v_consulta.id,
        v_fornecedor_id,
        nullif(
          v_linha ->> 'valor_adjudicado',
          ''
        )::numeric,
        v_estado in (
          'adjudicado',
          'em_execucao',
          'concluido'
        )
      )
      returning * into v_candidato;
    end if;

    if v_estado in (
      'adjudicado',
      'em_execucao',
      'concluido'
    )
    then
      insert into public.subempreitadas (
        obra_id,
        fase_id,
        consulta_id,
        fornecedor_id,
        especialidade,
        valor_adjudicado,
        estado,
        tipo_pagamento,
        condicao_pagamento,
        data_inicio_prevista,
        data_fim_prevista
      )
      values (
        v_obra_id,
        v_fase_id,
        v_consulta.id,
        v_fornecedor_id,
        btrim(v_linha ->> 'trabalho'),
        nullif(
          v_linha ->> 'valor_adjudicado',
          ''
        )::numeric,
        v_estado,
        nullif(v_linha ->> 'tipo_pagamento', ''),
        nullif(v_linha ->> 'condicao_pagamento', ''),
        nullif(
          v_linha ->> 'data_inicio_prevista',
          ''
        )::date,
        nullif(
          v_linha ->> 'data_fim_prevista',
          ''
        )::date
      )
      returning * into v_subempreitada;
    end if;

    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx(
    'subempreitadas',
    p_nome_ficheiro,
    v_importadas,
    jsonb_build_object(
      'linhas_recebidas',
      jsonb_array_length(p_linhas)
    )
  );

  return jsonb_build_object(
    'importadas',
    v_importadas
  );
end;
$function$
;
ALTER FUNCTION public.fn_importar_subempreitadas_xlsx(jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_importar_subempreitadas_xlsx(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_importar_subempreitadas_xlsx(jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_atualizar_venda_contrato_via_tee(p_tee_id uuid)
 RETURNS contratos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_obra_id uuid; v_row public.contratos%rowtype;
begin
  select obra_id into v_obra_id from public.alteracoes_tee where id=p_tee_id and estado_aprovacao_cliente='aprovado' for share;
  if not found then raise exception 'TEE formal aprovado não encontrado.'; end if;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  if not public.fn_e_diretor_obra(v_obra_id) then raise exception 'Operação reservada ao Diretor de Obra ou Gerência.' using errcode='42501'; end if;
  perform set_config('primeline.alteracao_via_tee','on',true);
  update public.contratos c set venda_contratual_efetiva=coalesce(c.venda_contratual_inicial,0)+
    coalesce((select sum(t.valor) from public.alteracoes_tee t where t.obra_id=v_obra_id and t.estado_aprovacao_cliente='aprovado'),0),atualizado_em=now()
  where c.obra_id=v_obra_id returning * into v_row;
  return v_row;
end;
$function$
;
ALTER FUNCTION public.fn_atualizar_venda_contrato_via_tee(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_atualizar_venda_contrato_via_tee(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_definir_estado_mensal_v1(p_obra_id uuid, p_mes text, p_estado text, p_revisao_esperada text, p_request_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_mes date;
  v_estado public.financeiro_estados_mensais%rowtype;
  v_hist public.financeiro_estados_mensais_historico%rowtype;
  v_user uuid;
  v_nova_revisao uuid;
BEGIN
  IF p_obra_id IS NULL
     OR NULLIF(btrim(p_mes), '') IS NULL
     OR NULLIF(btrim(p_estado), '') IS NULL
     OR NULLIF(btrim(p_request_id), '') IS NULL
  THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: obra, mês, estado e request_id são obrigatórios.';
  END IF;

  IF p_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: competência deve usar YYYY-MM.';
  END IF;

  v_mes := (p_mes || '-01')::date;

  IF p_estado NOT IN (
    'real',
    'fechado',
    'em_fecho',
    'aberto',
    'previsao'
  ) THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: estado mensal inválido.';
  END IF;

  perform public.fn_financeiro_autorizar_obra(p_obra_id,false);
  IF NOT (
    public.fn_e_admin()
    OR public.fn_e_financeiro()
  ) THEN
    RAISE EXCEPTION
      'FORBIDDEN: alteração de estado mensal reservada à Administração/Financeiro.'
      USING ERRCODE = '42501';
  END IF;

  v_user := public.fn_utilizador_atual_id();

  -- ----------------------------------------------------------
  -- Idempotência
  -- ----------------------------------------------------------

  SELECT *
  INTO v_hist
  FROM public.financeiro_estados_mensais_historico
  WHERE request_id = p_request_id;

  IF FOUND THEN
  perform public.fn_financeiro_autorizar_obra(v_hist.obra_id,false);
    IF v_hist.obra_id IS DISTINCT FROM p_obra_id
       OR v_hist.mes IS DISTINCT FROM v_mes
       OR v_hist.estado_novo IS DISTINCT FROM p_estado
    THEN
      RAISE EXCEPTION
        'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
    END IF;

    RETURN jsonb_build_object(
      'version', 1,
      'committed', true,
      'month', to_char(v_hist.mes, 'YYYY-MM'),
      'state', v_hist.estado_novo,
      'revision', v_hist.revisao_nova::text
    );
  END IF;


  -- ----------------------------------------------------------
  -- Estado atual
  -- ----------------------------------------------------------

  SELECT *
  INTO v_estado
  FROM public.financeiro_estados_mensais
  WHERE obra_id = p_obra_id
    AND mes = v_mes
  FOR UPDATE;


  -- ----------------------------------------------------------
  -- Primeira definição explícita
  -- ----------------------------------------------------------

  IF NOT FOUND THEN

    IF NULLIF(btrim(COALESCE(p_revisao_esperada, '')), '') IS NOT NULL THEN
      RAISE EXCEPTION
        'STALE_REVISION: o mês ainda não possui estado configurado.';
    END IF;

    v_nova_revisao := gen_random_uuid();

    INSERT INTO public.financeiro_estados_mensais (
      obra_id,
      mes,
      estado,
      revisao,
      alterado_por,
      alterado_em
    )
    VALUES (
      p_obra_id,
      v_mes,
      p_estado,
      v_nova_revisao,
      v_user,
      now()
    )
    RETURNING *
    INTO v_estado;

    INSERT INTO public.financeiro_estados_mensais_historico (
      estado_mensal_id,
      obra_id,
      mes,
      estado_anterior,
      estado_novo,
      revisao_anterior,
      revisao_nova,
      alterado_por,
      request_id
    )
    VALUES (
      v_estado.id,
      p_obra_id,
      v_mes,
      NULL,
      p_estado,
      NULL,
      v_nova_revisao,
      v_user,
      p_request_id
    );

    RETURN jsonb_build_object(
      'version', 1,
      'committed', true,
      'month', p_mes,
      'state', p_estado,
      'revision', v_nova_revisao::text
    );
  END IF;


  -- ----------------------------------------------------------
  -- Concorrência
  -- ----------------------------------------------------------

  IF NULLIF(btrim(COALESCE(p_revisao_esperada, '')), '') IS NULL
     OR v_estado.revisao::text IS DISTINCT FROM p_revisao_esperada
  THEN
    RAISE EXCEPTION
      'STALE_REVISION: o estado mensal foi alterado. Atualize antes de repetir.';
  END IF;


  -- ----------------------------------------------------------
  -- Meses protegidos não podem ser reabertos neste fluxo
  -- ----------------------------------------------------------

  IF v_estado.estado IN ('real', 'fechado')
     AND p_estado IS DISTINCT FROM v_estado.estado
  THEN
    RAISE EXCEPTION
      'PROTECTED_PERIOD: competência real/fechada exige processo auditado de reabertura.';
  END IF;


  IF p_estado = v_estado.estado THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: o mês já está nesse estado.';
  END IF;


  -- ----------------------------------------------------------
  -- Fecho económico:
  -- não marca faturas como pagas nem recebidas.
  --
  -- Neste estágio não tentamos validar uma "completude financeira"
  -- ainda não rastreável. Essa validação será adicionada junto
  -- do motor mensal.
  -- ----------------------------------------------------------

  v_nova_revisao := gen_random_uuid();

  INSERT INTO public.financeiro_estados_mensais_historico (
    estado_mensal_id,
    obra_id,
    mes,
    estado_anterior,
    estado_novo,
    revisao_anterior,
    revisao_nova,
    alterado_por,
    request_id
  )
  VALUES (
    v_estado.id,
    p_obra_id,
    v_mes,
    v_estado.estado,
    p_estado,
    v_estado.revisao,
    v_nova_revisao,
    v_user,
    p_request_id
  );

  UPDATE public.financeiro_estados_mensais
  SET
    estado = p_estado,
    revisao = v_nova_revisao,
    alterado_por = v_user,
    alterado_em = now()
  WHERE id = v_estado.id;

  RETURN jsonb_build_object(
    'version', 1,
    'committed', true,
    'month', p_mes,
    'state', p_estado,
    'revision', v_nova_revisao::text
  );
END;
$function$
;
ALTER FUNCTION public.fn_definir_estado_mensal_v1(uuid,text,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_definir_estado_mensal_v1(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_definir_estado_mensal_v1(uuid,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_guardar_planeamento_lote(p_lote jsonb, p_confirmacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_obra_id uuid;
  v_user_id uuid;
  v_payload_hash text;

  v_preview jsonb;
  v_conflicts jsonb;
  v_server_cascade jsonb;
  v_client_cascade jsonb;
  v_server_canonical jsonb;
  v_client_canonical jsonb;

  v_token_id uuid;
  v_token public.planeamento_lote_tokens%rowtype;

  v_change jsonb;
  v_dep record;
  v_item record;
  v_map_id uuid;

  v_result jsonb;
  v_operational_end date;
BEGIN
  IF p_lote IS NULL
     OR p_lote->>'version' IS DISTINCT FROM '1'
     OR NULLIF(p_lote->>'obra_id', '') IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: lote inválido.';
  END IF;

  v_obra_id := (p_lote->>'obra_id')::uuid;
  perform public.fn_financeiro_autorizar_obra(v_obra_id,false);
  v_user_id := public.fn_utilizador_atual_id();

  IF v_user_id IS NULL
     OR NOT COALESCE(public.fn_pode_editar_obra(v_obra_id), false)
  THEN
    RAISE EXCEPTION 'FORBIDDEN: sem permissão para editar esta obra.'
      USING ERRCODE = '42501';
  END IF;

  v_payload_hash := md5(p_lote::text);
  v_client_cascade := COALESCE(p_lote->'approved_cascade', '[]'::jsonb);


  -- ==========================================================
  -- PREVIEW
  -- ==========================================================

  IF p_confirmacao IS NULL THEN

    v_preview := public.fn_planeamento_lote_preview_v1(p_lote);

    v_conflicts := COALESCE(v_preview->'conflicts', '[]'::jsonb);
    v_server_cascade := COALESCE(v_preview->'approved_cascade', '[]'::jsonb);

    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'id'), '[]'::jsonb)
    INTO v_server_canonical
    FROM jsonb_array_elements(v_server_cascade) x;

    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'id'), '[]'::jsonb)
    INTO v_client_canonical
    FROM jsonb_array_elements(v_client_cascade) x;

    IF jsonb_array_length(v_conflicts) = 0
       AND v_server_canonical IS DISTINCT FROM v_client_canonical
    THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object(
          'type', 'cascade_mismatch'
        )
      );
    END IF;

    DELETE FROM public.planeamento_lote_tokens
    WHERE expira_em < now()
      AND utilizador_id = v_user_id;

    INSERT INTO public.planeamento_lote_tokens (
      obra_id,
      utilizador_id,
      payload_hash,
      approved_cascade,
      conflicts
    )
    VALUES (
      v_obra_id,
      v_user_id,
      v_payload_hash,
      CASE
        WHEN jsonb_array_length(v_conflicts) = 0
          THEN v_client_cascade
        ELSE v_server_cascade
      END,
      v_conflicts
    )
    RETURNING token
    INTO v_token_id;

    RETURN jsonb_build_object(
      'version', 1,
      'confirmation_token', v_token_id::text,
      'conflicts', v_conflicts,
      'approved_cascade',
        CASE
          WHEN jsonb_array_length(v_conflicts) = 0
            THEN v_client_cascade
          ELSE v_server_cascade
        END
    );
  END IF;


  -- ==========================================================
  -- CONFIRMAÇÃO
  -- ==========================================================

  BEGIN
    v_token_id := p_confirmacao::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'TOKEN_EXPIRED: token de confirmação inválido.';
  END;

  SELECT *
  INTO v_token
  FROM public.planeamento_lote_tokens
  WHERE token = v_token_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_token.utilizador_id IS DISTINCT FROM v_user_id
     OR v_token.obra_id IS DISTINCT FROM v_obra_id
     OR v_token.payload_hash IS DISTINCT FROM v_payload_hash
  THEN
    RAISE EXCEPTION 'TOKEN_EXPIRED: preview inválido ou não pertence a este lote.';
  END IF;

  IF v_token.consumido_em IS NOT NULL THEN
    IF v_token.resultado_final IS NOT NULL THEN
      RETURN v_token.resultado_final;
    END IF;

    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: token já consumido.';
  END IF;

  IF v_token.expira_em < now() THEN
    RAISE EXCEPTION 'TOKEN_EXPIRED: preview expirado.';
  END IF;


  -- Serializa lotes da mesma obra.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'primeline-planeamento-lote:' || v_obra_id::text,
      0
    )
  );

  -- Lock do estado persistente usado pelo snapshot.
  PERFORM pi.id
  FROM public.planeamento_itens pi
  JOIN public.fases f ON f.id = pi.fase_id
  WHERE f.obra_id = v_obra_id
  FOR UPDATE OF pi;

  PERFORM d.id
  FROM public.planeamento_itens_dependencias d
  JOIN public.planeamento_itens pi ON pi.id = d.item_id
  JOIN public.fases f ON f.id = pi.fase_id
  WHERE f.obra_id = v_obra_id
  FOR UPDATE OF d;

  PERFORM f.id
  FROM public.fases f
  WHERE f.obra_id = v_obra_id
  FOR SHARE;


  -- Revalidação completa após os locks.
  v_preview := public.fn_planeamento_lote_preview_v1(p_lote);

  v_conflicts := COALESCE(v_preview->'conflicts', '[]'::jsonb);
  v_server_cascade := COALESCE(v_preview->'approved_cascade', '[]'::jsonb);

  IF jsonb_array_length(v_conflicts) > 0 THEN
    RAISE EXCEPTION 'STALE_REVISION: o planeamento foi alterado ou contém conflitos. Atualize antes de repetir.';
  END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'id'), '[]'::jsonb)
  INTO v_server_canonical
  FROM jsonb_array_elements(v_server_cascade) x;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'id'), '[]'::jsonb)
  INTO v_client_canonical
  FROM jsonb_array_elements(v_client_cascade) x;

  IF v_server_canonical IS DISTINCT FROM v_client_canonical
     OR v_token.approved_cascade IS DISTINCT FROM v_client_cascade
  THEN
    RAISE EXCEPTION 'MANUAL_DATE_COLLISION: a cascata mudou desde o preview.';
  END IF;


  -- Desativa a cascata antiga durante esta transação.
  PERFORM set_config(
    'primeline.recalculo_cascata',
    'ativo',
    true
  );


  -- ----------------------------------------------------------
  -- Mapeamento ID cliente -> UUID persistente
  -- ----------------------------------------------------------

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.pl_lote_map (
    client_id text PRIMARY KEY,
    server_id uuid NOT NULL
  ) ON COMMIT DROP;

  TRUNCATE pg_temp.pl_lote_map;

  INSERT INTO pg_temp.pl_lote_map(client_id, server_id)
  SELECT id, persist_id
  FROM pg_temp.pl_lote_items
  WHERE persist_id IS NOT NULL;


  -- ----------------------------------------------------------
  -- Novas tarefas
  -- ----------------------------------------------------------

  FOR v_item IN
    SELECT *
    FROM pg_temp.pl_lote_items
    WHERE is_new
    ORDER BY id
  LOOP
    v_map_id := gen_random_uuid();

    INSERT INTO public.planeamento_itens (
      id,
      fase_id,
      codigo,
      descricao,
      responsavel,
      duracao_dias,
      data_inicio_prevista,
      data_fim_prevista,
      data_fim_real,
      peso_percentual,
      percentual_executado,
      percentual_ponderado,
      estado,
      causa_atraso,
      impacto,
      impedido,
      observacao_impedimento,
      data_inicio_real,
      especialidade_id,
      executado_por,
      item_orcamento_id,
      custo_estado,
      valor_estimado,
      valor_orca_pl
    )
    VALUES (
      v_map_id,
      v_item.fase_id,
      v_item.codigo,
      v_item.descricao,
      v_item.responsavel,
      CASE
        WHEN v_item.data_inicio_prevista IS NOT NULL
         AND v_item.data_fim_prevista IS NOT NULL
          THEN v_item.data_fim_prevista - v_item.data_inicio_prevista
        ELSE v_item.duracao_dias
      END,
      v_item.direct_start,
      v_item.direct_end,
      v_item.data_fim_real,
      v_item.peso_percentual,
      v_item.percentual_executado,
      CASE
        WHEN v_item.peso_percentual IS NULL THEN NULL
        ELSE v_item.peso_percentual
             * v_item.percentual_executado / 100
      END,
      v_item.estado,
      v_item.causa_atraso,
      v_item.impacto,
      COALESCE(v_item.impedido, false),
      v_item.observacao_impedimento,
      v_item.data_inicio_real,
      v_item.especialidade_id,
      v_item.executado_por,
      v_item.item_orcamento_id,
      COALESCE(v_item.custo_estado, 'orcamentado'),
      v_item.valor_estimado,
      v_item.valor_orca_pl
    );

    INSERT INTO pg_temp.pl_lote_map(client_id, server_id)
    VALUES (v_item.id, v_map_id);
  END LOOP;


  -- ----------------------------------------------------------
  -- Alterações das tarefas existentes
  -- ----------------------------------------------------------

  FOR v_change IN
    SELECT value
    FROM jsonb_array_elements(
      COALESCE(p_lote->'changes', '[]'::jsonb)
    )
  LOOP
    IF COALESCE((v_change->>'_new')::boolean, false) THEN
      CONTINUE;
    END IF;

    SELECT *
    INTO v_item
    FROM pg_temp.pl_lote_items
    WHERE id = v_change->>'id';

    SELECT server_id
    INTO v_map_id
    FROM pg_temp.pl_lote_map
    WHERE client_id = v_change->>'id';

    IF v_change ? 'fase_id' THEN
      UPDATE public.planeamento_itens
      SET fase_id = v_item.fase_id
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'codigo' THEN
      UPDATE public.planeamento_itens
      SET codigo = v_item.codigo
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'descricao' THEN
      UPDATE public.planeamento_itens
      SET descricao = v_item.descricao
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'responsavel' THEN
      UPDATE public.planeamento_itens
      SET responsavel = v_item.responsavel
      WHERE id = v_map_id;
    END IF;

    IF v_change ?| ARRAY[
      'data_inicio_prevista',
      'data_fim_prevista',
      'data_inicio_real',
      'data_fim_real',
      'duracao_dias'
    ] THEN
      UPDATE public.planeamento_itens
      SET
        data_inicio_prevista = v_item.direct_start,
        data_fim_prevista = v_item.direct_end,
        data_inicio_real = v_item.data_inicio_real,
        data_fim_real = v_item.data_fim_real,
        duracao_dias =
          CASE
            WHEN v_item.direct_start IS NOT NULL
             AND v_item.direct_end IS NOT NULL
              THEN v_item.direct_end - v_item.direct_start
            ELSE v_item.duracao_dias
          END,
        recalculado_automaticamente = false,
        recalculado_em = NULL,
        recalculado_por_item_id = NULL
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'peso_percentual'
       OR v_change ? 'percentual_executado'
       OR v_change ? 'estado'
       OR v_change ? 'percentual_ponderado'
    THEN
      UPDATE public.planeamento_itens
      SET
        peso_percentual = v_item.peso_percentual,
        percentual_executado = v_item.percentual_executado,
        percentual_ponderado =
          CASE
            WHEN v_item.peso_percentual IS NULL THEN NULL
            ELSE v_item.peso_percentual
                 * v_item.percentual_executado / 100
          END,
        estado = v_item.estado
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'causa_atraso' THEN
      UPDATE public.planeamento_itens
      SET causa_atraso = v_item.causa_atraso
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'impacto' THEN
      UPDATE public.planeamento_itens
      SET impacto = v_item.impacto
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'impedido'
       OR v_change ? 'observacao_impedimento'
    THEN
      UPDATE public.planeamento_itens
      SET
        impedido = COALESCE(v_item.impedido, false),
        observacao_impedimento = v_item.observacao_impedimento
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'especialidade_id' THEN
      UPDATE public.planeamento_itens
      SET especialidade_id = v_item.especialidade_id
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'executado_por' THEN
      UPDATE public.planeamento_itens
      SET executado_por = v_item.executado_por
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'item_orcamento_id' THEN
      UPDATE public.planeamento_itens
      SET item_orcamento_id = v_item.item_orcamento_id
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'custo_estado' THEN
      UPDATE public.planeamento_itens
      SET custo_estado = v_item.custo_estado
      WHERE id = v_map_id;
    END IF;

    IF v_change ? 'valor_estimado'
       OR v_change ? 'valor_orca_pl'
    THEN
      UPDATE public.planeamento_itens
      SET
        valor_estimado = v_item.valor_estimado,
        valor_orca_pl = v_item.valor_orca_pl
      WHERE id = v_map_id;
    END IF;

    IF COALESCE((v_change->>'_archive')::boolean, false) THEN
      UPDATE public.planeamento_itens
      SET
        arquivado_em = now(),
        arquivado_por = v_user_id,
        motivo_arquivo = btrim(p_lote->>'archive_reason')
      WHERE id = v_map_id
        AND arquivado_em IS NULL;
    END IF;
  END LOOP;


  -- ----------------------------------------------------------
  -- Cascata previamente aprovada
  -- ----------------------------------------------------------

  FOR v_item IN
    SELECT *
    FROM pg_temp.pl_lote_items
    WHERE arquivado_em IS NULL
      AND NOT archive_requested
      AND (
        calc_start IS DISTINCT FROM direct_start
        OR calc_end IS DISTINCT FROM direct_end
      )
  LOOP
    SELECT server_id
    INTO v_map_id
    FROM pg_temp.pl_lote_map
    WHERE client_id = v_item.id;

    UPDATE public.planeamento_itens
    SET
      data_inicio_prevista = v_item.calc_start,
      data_fim_prevista = v_item.calc_end,
      duracao_dias =
        CASE
          WHEN v_item.calc_start IS NOT NULL
           AND v_item.calc_end IS NOT NULL
            THEN v_item.calc_end - v_item.calc_start
          ELSE duracao_dias
        END,
      recalculado_automaticamente = true,
      recalculado_em = now(),
      recalculado_por_item_id = NULL
    WHERE id = v_map_id;
  END LOOP;


  -- ----------------------------------------------------------
  -- Dependências: substituição atómica do conjunto da obra
  -- ----------------------------------------------------------

  DELETE FROM public.planeamento_itens_dependencias d
  USING public.planeamento_itens pi,
        public.fases f
  WHERE d.item_id = pi.id
    AND pi.fase_id = f.id
    AND f.obra_id = v_obra_id;

  FOR v_dep IN
    SELECT *
    FROM pg_temp.pl_lote_deps
    ORDER BY id
  LOOP
    INSERT INTO public.planeamento_itens_dependencias (
      id,
      item_id,
      depende_de_item_id,
      tipo,
      atraso_dias
    )
    VALUES (
      v_dep.id::uuid,
      (
        SELECT server_id
        FROM pg_temp.pl_lote_map
        WHERE client_id = v_dep.item_id
      ),
      (
        SELECT server_id
        FROM pg_temp.pl_lote_map
        WHERE client_id = v_dep.depende_de_item_id
      ),
      v_dep.tipo,
      v_dep.atraso_dias
    );
  END LOOP;


  -- ----------------------------------------------------------
  -- Resumo físico das fases
  -- ----------------------------------------------------------

  INSERT INTO public.planeamento_fases_resumo (
    fase_id,
    data_inicio_prevista,
    data_fim_prevista,
    data_fim_real,
    percentual_executado,
    estado,
    atualizado_por,
    atualizado_em
  )
  SELECT
    f.id,

    min(pi.data_inicio_prevista)
      FILTER (WHERE pi.arquivado_em IS NULL),

    max(pi.data_fim_prevista)
      FILTER (WHERE pi.arquivado_em IS NULL),

    CASE
      WHEN count(pi.id)
        FILTER (WHERE pi.arquivado_em IS NULL) > 0
       AND bool_and(
         pi.percentual_executado >= 100
       ) FILTER (WHERE pi.arquivado_em IS NULL)
      THEN max(pi.data_fim_real)
        FILTER (WHERE pi.arquivado_em IS NULL)
      ELSE NULL
    END,

    round(
      COALESCE(
        sum(
          pi.peso_percentual
          * pi.percentual_executado / 100
        ) FILTER (WHERE pi.arquivado_em IS NULL),
        0
      ),
      2
    ),

    CASE
      WHEN COALESCE(
        sum(
          pi.peso_percentual
          * pi.percentual_executado / 100
        ) FILTER (WHERE pi.arquivado_em IS NULL),
        0
      ) >= 99.995
        THEN 'concluido'

      WHEN COALESCE(
        sum(
          pi.peso_percentual
          * pi.percentual_executado / 100
        ) FILTER (WHERE pi.arquivado_em IS NULL),
        0
      ) > 0
        THEN 'em_execucao'

      ELSE 'por_iniciar'
    END,

    v_user_id,
    now()

  FROM public.fases f
  LEFT JOIN public.planeamento_itens pi
    ON pi.fase_id = f.id
  WHERE f.obra_id = v_obra_id
  GROUP BY f.id

  ON CONFLICT (fase_id)
  DO UPDATE SET
    data_inicio_prevista = EXCLUDED.data_inicio_prevista,
    data_fim_prevista = EXCLUDED.data_fim_prevista,
    data_fim_real = EXCLUDED.data_fim_real,
    percentual_executado = EXCLUDED.percentual_executado,
    estado = EXCLUDED.estado,
    atualizado_por = EXCLUDED.atualizado_por,
    atualizado_em = EXCLUDED.atualizado_em;


  -- ----------------------------------------------------------
  -- Fim operacional da obra
  -- ----------------------------------------------------------

  SELECT max(pi.data_fim_prevista)
  INTO v_operational_end
  FROM public.planeamento_itens pi
  JOIN public.fases f ON f.id = pi.fase_id
  WHERE f.obra_id = v_obra_id
    AND pi.arquivado_em IS NULL;

  IF v_operational_end IS NOT NULL THEN
    UPDATE public.obras
    SET data_fim_prevista = v_operational_end
    WHERE id = v_obra_id
      AND data_fim_prevista IS DISTINCT FROM v_operational_end;
  END IF;


  -- ----------------------------------------------------------
  -- Resultado
  -- O motor financeiro mensal ainda será instalado depois.
  -- Por isso não fingimos um Summary oficial.
  -- ----------------------------------------------------------

  v_result := jsonb_build_object(
    'version', 1,
    'committed', true,
    'preserved', jsonb_build_object(
      'closed_months', true,
      'historical_measurements', true,
      'actual_movements', true
    ),
    'financial_summary', NULL,
    'financial_recalculation', 'pending'
  );

  UPDATE public.planeamento_lote_tokens
  SET
    consumido_em = now(),
    resultado_final = v_result
  WHERE token = v_token_id;

  RETURN v_result;
END;
$function$
;
ALTER FUNCTION public.fn_guardar_planeamento_lote(jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_guardar_planeamento_lote(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_guardar_planeamento_lote(jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_criar_obra_de_modelo(p_modelo_obra_id uuid, p_numero text, p_nome text, p_cliente text DEFAULT NULL::text, p_morada text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text, p_modalidade text DEFAULT NULL::text, p_diretor_obra_id uuid DEFAULT NULL::uuid, p_situacao text DEFAULT 'planeamento'::text, p_data_inicio date DEFAULT NULL::date, p_data_fim_prevista date DEFAULT NULL::date, p_copiar_orcamento boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_obra public.obras%rowtype;
  v_fase record;
  v_fase_nova_id uuid;
  v_total_fases integer := 0;
  v_total_itens integer := 0;
  v_itens_inseridos integer := 0;
  v_colunas_itens text;
  v_empresa_id uuid;
begin
  perform public.fn_financeiro_autorizar_obra(p_modelo_obra_id,false);
  select empresa_id into v_empresa_id from public.obras where id=p_modelo_obra_id for share;
  if p_diretor_obra_id is not null then
    perform 1 from public.colaboradores where id=p_diretor_obra_id and empresa_id=v_empresa_id for share;
    if not found then raise exception 'FORBIDDEN: recurso relacionado indisponível.' using errcode='42501'; end if;
  end if;
  if not public.fn_e_admin() then
    raise exception 'A criação de obras por modelo está reservada à Gerência.' using errcode='42501';
  end if;

  if p_modelo_obra_id is null or not exists (
    select 1 from public.obras where id = p_modelo_obra_id
  ) then
    raise exception 'A obra-modelo selecionada não existe.';
  end if;

  if nullif(btrim(p_numero), '') is null or nullif(btrim(p_nome), '') is null then
    raise exception 'Número e designação da nova obra são obrigatórios.';
  end if;

  if p_data_inicio is not null and p_data_fim_prevista is not null
     and p_data_fim_prevista < p_data_inicio then
    raise exception 'A data de fim prevista não pode ser anterior à data de início.';
  end if;

  if exists (
    select 1 from public.obras
    where empresa_id = v_empresa_id
      and lower(btrim(numero::text)) = lower(btrim(p_numero))
  ) then
    raise exception 'Já existe uma obra com este número.';
  end if;

  insert into public.obras (
    empresa_id, numero, nome, cliente, morada, tipo, modalidade,
    diretor_obra_id, situacao, data_inicio, data_fim_prevista
  ) values (
    v_empresa_id,
    btrim(p_numero)::integer, btrim(p_nome), nullif(btrim(p_cliente), ''),
    nullif(btrim(p_morada), ''), nullif(btrim(p_tipo), ''),
    nullif(btrim(p_modalidade), ''), p_diretor_obra_id,
    coalesce(nullif(btrim(p_situacao), ''), 'planeamento'),
    p_data_inicio, p_data_fim_prevista
  ) returning * into v_obra;

  -- Apenas campos descritivos são elegíveis para copiar do orçamento.
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_colunas_itens
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'itens_orcamento'
    and c.column_name = any(array[
      'codigo', 'descricao', 'designacao', 'unidade', 'categoria',
      'especialidade', 'capitulo', 'subcapitulo', 'ordem'
    ]);

  for v_fase in
    select id, codigo, descricao
    from public.fases
    where obra_id = p_modelo_obra_id
    order by codigo, descricao for share
  loop
    v_fase_nova_id := gen_random_uuid();
    insert into public.fases (id, obra_id, codigo, descricao)
    values (v_fase_nova_id, v_obra.id, v_fase.codigo, v_fase.descricao);
    v_total_fases := v_total_fases + 1;

    if to_regclass('public.planeamento_fases_resumo') is not null
       and exists (select 1 from public.planeamento_fases_resumo where fase_id = v_fase.id) then
      insert into public.planeamento_fases_resumo (fase_id)
      values (v_fase_nova_id);
    end if;

    if coalesce(p_copiar_orcamento, true) and v_colunas_itens is not null then
      execute format(
        'insert into public.itens_orcamento (id, fase_id, %1$s) '
        'select gen_random_uuid(), $1, %1$s from public.itens_orcamento where fase_id = $2',
        v_colunas_itens
      ) using v_fase_nova_id, v_fase.id;
      get diagnostics v_itens_inseridos = row_count;
      v_total_itens := v_total_itens + v_itens_inseridos;
    end if;
  end loop;

  return jsonb_build_object(
    'obra', to_jsonb(v_obra),
    'fases_copiadas', v_total_fases,
    'itens_orcamento_copiados', v_total_itens
  );
end;
$function$
;
ALTER FUNCTION public.fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_importar_mapa_financeiro_xlsx(p_ano integer, p_linhas jsonb, p_nome_ficheiro text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
declare
  v_linha jsonb;
  v_valor jsonb;
  v_mes integer;
  v_importadas integer := 0;
  v_obra_id uuid;
begin
  -- Validate the entire payload before any import write, including the import log.
  perform public.fn_economico_ator_atual();
  if p_ano is null or p_ano not between 2000 and 2200
     or jsonb_typeof(p_linhas) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Ano ou linhas de importação inválidos.';
  end if;
  for v_linha in select value from jsonb_array_elements(p_linhas) loop
    if v_linha ->> 'tipo' = 'despesa_fixa' then
      raise exception using errcode = '0A000',
        message = 'DESPESAS_GERAIS_BLOQUEADAS: importação temporariamente indisponível até existir atribuição segura de empresa. Importe somente linhas de obra.';
    elsif v_linha ->> 'tipo' = 'obra' then
      v_obra_id := nullif(v_linha ->> 'obra_id', '')::uuid;
      perform public.fn_financeiro_autorizar_obra(v_obra_id, false);
    else
      raise exception using errcode = '22023', message = 'Tipo de linha inválido no Mapa Financeiro; apenas linhas de obra são aceites.';
    end if;
  end loop;
  if not (
    public.fn_e_admin()
    or public.fn_e_financeiro()
  )
  then
    raise exception using
      errcode = '42501',
      message =
        'Sem permissão para importar o Mapa Financeiro.';
  end if;

  if p_ano not between 2000 and 2200
     or jsonb_typeof(p_linhas) <> 'array'
  then
    raise exception using
      errcode = '22023',
      message = 'Ano ou linhas de importação inválidos.';
  end if;

  for v_linha in
    select value
    from jsonb_array_elements(p_linhas)
  loop
    if v_linha ->> 'tipo' = 'obra' then
      v_obra_id :=
        nullif(v_linha ->> 'obra_id', '')::uuid;

      if not exists (
        select 1
        from public.obras o
        where o.id = v_obra_id
      )
      then
        raise exception using
          errcode = '23503',
          message = 'Obra inexistente no Mapa Financeiro.';
      end if;

      v_mes := 0;

      for v_valor in
        select value
        from jsonb_array_elements(v_linha -> 'meses')
      loop
        v_mes := v_mes + 1;

        if jsonb_typeof(v_valor) = 'number' then
          insert into public.mapa_financeiro_ajustes (
            obra_id,
            ano,
            mes,
            valor_calculado_referencia,
            valor_ajustado,
            motivo,
            atualizado_por,
            atualizado_em
          )
          values (
            v_obra_id,
            p_ano,
            v_mes,
            null,
            (v_valor #>> '{}')::numeric,
            'Importação Excel: ' || p_nome_ficheiro,
            public.fn_utilizador_atual_id(),
            now()
          )
          on conflict (obra_id, ano, mes)
          do update set
            valor_ajustado = excluded.valor_ajustado,
            motivo = excluded.motivo,
            atualizado_por = excluded.atualizado_por,
            atualizado_em = excluded.atualizado_em;
        end if;
      end loop;

    end if;

    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx(
    'mapa_financeiro',
    p_nome_ficheiro,
    v_importadas,
    jsonb_build_object('ano', p_ano)
  );

  return jsonb_build_object(
    'importadas',
    v_importadas
  );
end;
$function$;
ALTER FUNCTION public.fn_importar_mapa_financeiro_xlsx(integer,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_importar_mapa_financeiro_xlsx(integer,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_importar_mapa_financeiro_xlsx(integer,jsonb,text) TO authenticated;

CREATE TABLE primeline_encarregado_20261004.instalacao(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), catalogo jsonb NOT NULL);
ALTER TABLE primeline_encarregado_20261004.instalacao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE primeline_encarregado_20261004.instalacao FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO primeline_encarregado_20261004.instalacao(catalogo) SELECT jsonb_build_object(
 'tables', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END ORDER BY CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END) FROM unnest(p.polroles) roleid),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
 'view_definition',CASE WHEN c.relkind IN('v','m') THEN pg_get_viewdef(c.oid,true) END) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p','v','m')),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',(SELECT array_agg(acl_item::text ORDER BY acl_item::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) acl_item),'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
);
COMMIT;
