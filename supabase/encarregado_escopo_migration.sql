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
