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
CREATE FUNCTION public.fn_financeiro_autorizar_obra(p_obra_id uuid,p_pagamento boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE u public.utilizadores; empresa uuid;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE auth_user_id=auth.uid() AND ativo IS TRUE FOR SHARE;
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
