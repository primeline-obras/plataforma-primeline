-- Rollback apenas antes de qualquer uso do novo contrato; caso contrário PARAR e reconciliar.
BEGIN;
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM public.quadro_operacoes) OR EXISTS(SELECT 1 FROM public.quadro_dias_revisoes WHERE revisao>0) THEN RAISE EXCEPTION 'ROLLBACK_REFUSED: pacote já utilizado; preservar histórico e reconciliar.'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  u public.utilizadores;
  c public.colaboradores;
  q public.quadro_pessoal_alocacao;
BEGIN
  IF TG_OP = 'DELETE' THEN
    q := OLD;
  ELSE
    q := NEW;
  END IF;

  SELECT *
  INTO c
  FROM public.colaboradores
  WHERE id = q.colaborador_id;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(q.colaborador_id::text, 0)
  );

  IF TG_OP = 'UPDATE'
     AND (
       NEW.id IS DISTINCT FROM OLD.id
       OR NEW.colaborador_id IS DISTINCT FROM OLD.colaborador_id
     )
  THEN
    RAISE EXCEPTION 'Não é permitido alterar a identidade da alocação.';
  END IF;

  SELECT *
  INTO u
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id()
    AND ativo IS TRUE;

  IF u.id IS NULL THEN

    IF session_user NOT IN ('postgres', 'supabase_admin')
       OR auth.uid() IS NOT NULL
    THEN
      RAISE EXCEPTION 'Sem utilizador autorizado.'
      USING ERRCODE = '42501';
    END IF;

  ELSE

    IF c.empresa_id IS DISTINCT FROM u.empresa_id THEN
      RAISE EXCEPTION 'Colaborador de outra empresa.'
      USING ERRCODE = '42501';
    END IF;

    IF NOT public.fn_pode_gerir_quadro(NULL) THEN

      IF TG_OP = 'DELETE'
         OR NOT EXISTS (
           SELECT 1
           FROM public.quadro_pessoal_rpc_permit p
           WHERE p.transacao = txid_current()
             AND p.utilizador_id = u.id
             AND p.colaborador_id = NEW.colaborador_id
             AND p.destino_id = NEW.obra_id
             AND p.data = NEW.data
             AND p.periodo = NEW.periodo
             AND NEW.tipo_alocacao = 'obra'
             AND NEW.descricao_livre IS NULL
             AND (
               (
                 TG_OP = 'INSERT'
                 AND p.origem_id IS NULL
               )
               OR (
                 TG_OP = 'UPDATE'
                 AND p.origem_id = OLD.id
                 AND NEW.data = OLD.data
                 AND NEW.periodo = OLD.periodo
               )
             )
             AND public.fn_quadro_minha_obra(p.destino_id)
         )
      THEN
        RAISE EXCEPTION 'Sem autorização para editar o Quadro Geral.'
        USING ERRCODE = '42501';
      END IF;

    END IF;
  END IF;

  IF q.obra_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.obras o
       WHERE o.id = q.obra_id
         AND o.empresa_id = c.empresa_id
     )
  THEN
    RAISE EXCEPTION 'Obra de outra empresa.'
    USING ERRCODE = '42501';
  END IF;

  IF TG_OP <> 'DELETE' THEN

    IF c.id IS NULL
       OR (
         c.data_saida IS NOT NULL
         AND c.data_saida <= NEW.data
       )
       OR c.data_admissao > NEW.data
    THEN
      RAISE EXCEPTION 'Colaborador indisponível nesta data.';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.ausencias a
      WHERE a.colaborador_id = NEW.colaborador_id
        AND a.data = NEW.data
    )
    THEN
      RAISE EXCEPTION
        'Este colaborador está de férias/ausente nesta data.';
    END IF;

    IF u.id IS NOT NULL
       AND TG_OP = 'INSERT'
    THEN
      NEW.criado_por := u.id;
    END IF;

    IF TG_OP = 'UPDATE' THEN
      NEW.criado_por := OLD.criado_por;
    END IF;

  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END
$function$;

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

CREATE OR REPLACE FUNCTION public.fn_registar_movimento_quadro()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c public.colaboradores;
  u public.utilizadores;
  q public.quadro_pessoal_alocacao;
  b jsonb;
  a jsonb;
  action text;
BEGIN

  IF TG_OP = 'UPDATE'
     AND OLD IS NOT DISTINCT FROM NEW
  THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    q := OLD;
  ELSE
    q := NEW;
  END IF;

  SELECT *
  INTO c
  FROM public.colaboradores
  WHERE id = q.colaborador_id;

  SELECT *
  INTO u
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id();

  IF TG_OP <> 'INSERT' THEN
    b := to_jsonb(OLD);
  END IF;

  IF TG_OP <> 'DELETE' THEN
    a := to_jsonb(NEW);
  END IF;

  action :=
    CASE
      WHEN TG_OP = 'INSERT'
        THEN 'adicionar'
      WHEN TG_OP = 'DELETE'
        THEN 'remover'
      WHEN OLD.obra_id IS DISTINCT FROM NEW.obra_id
        OR OLD.data IS DISTINCT FROM NEW.data
        OR OLD.periodo IS DISTINCT FROM NEW.periodo
        OR OLD.tipo_alocacao IS DISTINCT FROM NEW.tipo_alocacao
        THEN 'mover'
      ELSE 'corrigir'
    END;

  INSERT INTO public.quadro_pessoal_movimentos (
    empresa_id,
    alocacao_id,
    colaborador_id,
    data,
    periodo,
    acao,
    obra_origem_id,
    obra_destino_id,
    tipo_origem,
    tipo_destino,
    descricao_origem,
    descricao_destino,
    alterado_por,
    perfil_autor,
    nome_autor,
    nome_colaborador,
    tipo_acao,
    alocacao_origem_id,
    alocacao_destino_id,
    antes,
    depois
  )
  VALUES (
    c.empresa_id,
    q.id,
    c.id,
    q.data,
    q.periodo,
    CASE TG_OP
      WHEN 'INSERT' THEN 'adicionada'
      WHEN 'DELETE' THEN 'retirada'
      ELSE 'alterada'
    END,
    (b->>'obra_id')::uuid,
    (a->>'obra_id')::uuid,
    b->>'tipo_alocacao',
    a->>'tipo_alocacao',
    b->>'descricao_livre',
    a->>'descricao_livre',
    u.id,
    coalesce(u.funcao, 'sql_administrativo'),
    coalesce(u.nome, session_user),
    c.nome,
    action,
    (b->>'id')::uuid,
    (a->>'id')::uuid,
    b,
    a
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION public.fn_rh_guardar_interno(p_dados jsonb, p_simular boolean, p_importacao boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_empresa uuid:=public.fn_rh_empresa(p_importacao); v_id uuid:=nullif(p_dados->>'id','')::uuid;
  v_antes jsonb; v_patch jsonb:=coalesce(p_dados->'campos','{}'); v_result jsonb;
  v_c public.colaboradores%rowtype; v_ct public.colaboradores_contratos%rowtype;
  v_cp jsonb:=p_dados->'contrato'; v_niss text; v_count integer; v_alterado boolean;
  v_novo boolean:=v_id is null; v_original_ct jsonb;
  v_avisos jsonb:='[]'; v_pendencia text;
begin
  perform pg_advisory_xact_lock(hashtextextended('rh:'||v_empresa::text,0));
  if p_importacao and v_novo then raise exception 'A importação exige ID existente.'; end if;
  if jsonb_typeof(v_patch) is distinct from 'object' then raise exception 'Campos inválidos.'; end if;
  if exists(select 1 from jsonb_object_keys(v_patch) k where k not in
    ('nome','funcao','nivel','valor_hora','nif','email','contacto','morada','data_admissao',
     'data_nascimento','data_saida','codigo_rh','observacoes','seguranca_social_ok','seguro_ok','registo_trabalhador_ok')) then
    raise exception 'Campos de RH desconhecidos.';
  end if;
  if not v_novo then
    perform 1 from public.colaboradores where id=v_id and empresa_id=v_empresa for update;
    if not found then raise exception 'Colaborador não encontrado nesta empresa.'; end if;
    perform 1 from public.colaboradores_contratos where colaborador_id=v_id for update;
    v_antes:=public.fn_rh_consultar(v_id)->0;
  end if;
  v_c:=jsonb_populate_record(null::public.colaboradores,coalesce(v_antes->'colaborador','{}')||v_patch);
  if nullif(btrim(v_c.nome),'') is null or nullif(btrim(v_c.funcao),'') is null or v_c.data_admissao is null then
    raise exception 'Nome, função e admissão são obrigatórios.';
  end if;
  if v_c.valor_hora<0 then raise exception 'Valor/hora não pode ser negativo.'; end if;
  if v_c.data_saida<v_c.data_admissao or v_c.data_nascimento>v_c.data_admissao then raise exception 'Datas incompatíveis.'; end if;
  if nullif(v_c.nif,'') is not null and v_c.nif !~ '^[0-9]{9}$' then raise exception 'NIF deve ter 9 algarismos.'; end if;
  if nullif(v_c.email,'') is not null and v_c.email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Email inválido.'; end if;
  if exists(select 1 from public.colaboradores c where c.empresa_id=v_empresa and c.id is distinct from v_id
    and ((nullif(v_c.nif,'') is not null and c.nif=v_c.nif) or
      (nullif(v_c.codigo_rh,'') is not null and c.codigo_rh=v_c.codigo_rh))) then
    raise exception 'NIF ou código RH já pertence a outro colaborador.';
  end if;
  v_niss:=case when p_dados ? 'niss' then nullif(p_dados->>'niss','') else v_antes->>'niss' end;
  if v_niss is not null and v_niss !~ '^[0-9]{11}$' then raise exception 'NISS deve ter 11 algarismos.'; end if;
  if v_cp is not null and v_cp<>'null'::jsonb then
    if jsonb_typeof(v_cp)<>'object' then raise exception 'Contrato inválido.'; end if;
    if exists(select 1 from jsonb_object_keys(v_cp) k where k not in ('tipo_contrato','data_inicio','data_fim_prevista')) then
      raise exception 'Campos de contrato desconhecidos.';
    end if;
    select count(*) into v_count from public.colaboradores_contratos where colaborador_id=v_id and estado='ativo';
    if v_count>1 then raise exception 'Existem vários contratos ativos; rever antes de editar.'; end if;
    select * into v_ct from public.colaboradores_contratos where colaborador_id=v_id and estado='ativo';
    v_original_ct:=to_jsonb(v_ct);
    v_ct:=jsonb_populate_record(v_ct,v_cp);
    if not p_importacao and (v_ct.tipo_contrato is null or v_ct.tipo_contrato not in ('a_prazo','tempo_indeterminado') or v_ct.data_inicio is null) then
      raise exception 'Tipo e início do contrato são obrigatórios.';
    end if;
    if v_ct.tipo_contrato is not null and v_ct.tipo_contrato not in ('a_prazo','tempo_indeterminado') then
      raise exception 'Tipo de contrato inválido.';
    end if;
    if v_ct.data_inicio is null then v_pendencia:='Início do contrato em falta.';
    elsif v_ct.tipo_contrato='a_prazo' and v_ct.data_fim_prevista is null then v_pendencia:='Indique o fim previsto.';
    elsif v_ct.data_fim_prevista<v_ct.data_inicio then v_pendencia:='Fim contratual anterior ao início.';
    end if;
    if v_pendencia is not null then
      if not p_importacao then raise exception '%',v_pendencia; end if;
      v_avisos:=v_avisos||jsonb_build_array('Contrato não alterado: '||v_pendencia||' Os restantes campos podem ser atualizados.');
      v_cp:=null;
    elsif v_ct.tipo_contrato='tempo_indeterminado' and v_ct.data_fim_prevista is not null then
      if not p_importacao then raise exception 'Tempo indeterminado não tem fim previsto.'; end if;
      -- Na importação parcial, vazio não autoriza apagar uma data anterior.
      if v_cp ? 'data_fim_prevista' then
        v_avisos:=v_avisos||jsonb_build_array('Contrato não alterado: tempo indeterminado com fim fornecido. Rever no cadastro individual.');
        v_cp:=null;
      else
        v_avisos:=v_avisos||jsonb_build_array('Fim previsto existente preservado. Rever no cadastro individual o contrato sem termo.');
      end if;
    elsif v_ct.tipo_contrato is null then
      v_avisos:=v_avisos||jsonb_build_array('Data contratual aceite; tipo de contrato por confirmar pelo RH.');
    end if;
  end if;
  v_alterado:=v_novo or to_jsonb(v_c) is distinct from v_antes->'colaborador'
    or v_niss is distinct from v_antes->>'niss'
    or (v_cp is not null and v_cp<>'null'::jsonb and to_jsonb(v_ct) is distinct from v_original_ct);
  -- Reimportar o mesmo conteúdo é um no-op, mesmo com a versão antiga do Excel.
  if not v_novo and v_alterado and p_dados->>'versao' is distinct from v_antes->>'versao' then
    raise exception 'Cadastro alterado entretanto. Reabra ou exporte novamente o modelo.';
  end if;
  if v_novo then
    if coalesce(p_dados->>'alocacao_tipo','') not in ('obra','escritorio') then raise exception 'Indique a alocação inicial.'; end if;
    if p_dados->>'alocacao_tipo'='obra' and not exists(select 1 from public.obras
      where id=nullif(p_dados->>'obra_id','')::uuid and empresa_id=v_empresa and situacao in ('preparacao','em_curso')) then
      raise exception 'Selecione uma obra ativa da empresa.';
    end if;
    if p_dados->>'alocacao_tipo'='escritorio' and nullif(p_dados->>'obra_id','') is not null then raise exception 'Escritório não tem obra.'; end if;
    perform nullif(p_dados->>'epi_data','')::date;
    perform nullif(p_dados->>'medicina_data','')::date;
  end if;
  if p_simular or not v_alterado then return jsonb_build_object('alterado',v_alterado,'id',v_id,'avisos',v_avisos); end if;
  if v_novo then
    v_id:=(public.fn_criar_colaborador_com_alocacao(v_c.nome,v_c.funcao,v_c.data_admissao,v_c.data_nascimento,
      p_dados->>'alocacao_tipo',nullif(p_dados->>'obra_id','')::uuid,v_c.nivel,v_c.valor_hora,v_c.nif,v_c.email,v_c.contacto,v_c.morada)
      ->'colaborador'->>'id')::uuid;
  end if;
  update public.colaboradores set nome=v_c.nome,funcao=v_c.funcao,nivel=v_c.nivel,valor_hora=v_c.valor_hora,
    nif=v_c.nif,email=v_c.email,contacto=v_c.contacto,morada=v_c.morada,data_admissao=v_c.data_admissao,
    data_nascimento=v_c.data_nascimento,data_saida=v_c.data_saida,codigo_rh=v_c.codigo_rh,observacoes=v_c.observacoes,
    seguranca_social_ok=v_c.seguranca_social_ok,seguro_ok=v_c.seguro_ok,registo_trabalhador_ok=v_c.registo_trabalhador_ok
    where id=v_id and empresa_id=v_empresa;
  if v_novo then
    if nullif(p_dados->>'epi_data','') is not null then
      insert into public.epis(colaborador_id,tipo_epi,data_entrega,data_validade)
      values(v_id,'Entrega inicial',(p_dados->>'epi_data')::date,null);
    end if;
    if nullif(p_dados->>'medicina_data','') is not null then
      insert into public.medicina_trabalho(colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta)
      values(v_id,(p_dados->>'medicina_data')::date,'Consulta inicial registada na admissão',null);
    end if;
  elsif (v_antes->'colaborador'->>'data_saida') is distinct from v_c.data_saida::text then
    perform public.fn_atualizar_colaborador_ciclo_vida(v_id,v_c.nome,v_c.funcao,v_c.data_admissao,
      v_c.data_nascimento,v_c.data_saida,v_c.nivel,v_c.valor_hora,v_c.nif,v_c.email,v_c.contacto,v_c.morada);
  end if;
  insert into public.colaboradores_rh_privado(colaborador_id,niss) values(v_id,v_niss)
    on conflict(colaborador_id) do update set niss=excluded.niss;
  if v_cp is not null and v_cp<>'null'::jsonb then
    if v_ct.id is null then
      insert into public.colaboradores_contratos(colaborador_id,tipo_contrato,data_inicio,data_fim_prevista,estado)
      values(v_id,v_ct.tipo_contrato,v_ct.data_inicio,v_ct.data_fim_prevista,'ativo');
    else
      update public.colaboradores_contratos set tipo_contrato=v_ct.tipo_contrato,data_inicio=v_ct.data_inicio,
        data_fim_prevista=v_ct.data_fim_prevista where id=v_ct.id;
    end if;
  end if;
  v_result:=public.fn_rh_consultar(v_id)->0;
  insert into public.rh_cadastro_auditoria(empresa_id,colaborador_id,utilizador_id,origem,antes,depois)
    values(v_empresa,v_id,public.fn_utilizador_atual_id(),case when p_importacao then 'importacao_excel' else 'cadastro' end,v_antes,v_result);
  return jsonb_build_object('alterado',true,'id',v_id,'avisos',v_avisos);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_criar_colaborador_com_alocacao(p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date DEFAULT NULL::date, p_alocacao_tipo text DEFAULT 'obra'::text, p_obra_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_empresa_id uuid;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_colaborador public.colaboradores%rowtype;
  v_alocacao public.quadro_pessoal_alocacao%rowtype;
  v_semana_inicio date;
begin
  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
  ) then
    raise exception
      'A criação de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_alocacao_tipo not in ('obra', 'escritorio') then
    raise exception
      'A alocação inicial deve ser uma obra ativa ou o Escritório.';
  end if;

  select u.empresa_id
  into v_empresa_id
  from public.utilizadores u
  where u.id = v_utilizador_id;

  if v_empresa_id is null and public.fn_e_admin() then
    select e.id
    into v_empresa_id
    from public.empresas e
    limit 1;
  end if;

  if v_empresa_id is null then
    raise exception
      'Não foi possível identificar a empresa do utilizador atual.';
  end if;

  if p_alocacao_tipo = 'obra' then
    if p_obra_id is null or not exists (
      select 1
      from public.obras o
      where o.id = p_obra_id
        and coalesce(lower(o.situacao), '') not in (
          'concluida',
          'concluído',
          'concluido',
          'cancelada'
        )
    ) then
      raise exception
        'Selecione uma obra ativa válida para a alocação inicial.';
    end if;
  elsif p_obra_id is not null then
    raise exception
      'A alocação de Escritório não pode ficar ligada a uma obra.';
  end if;

  insert into public.colaboradores (
    empresa_id,
    nome,
    funcao,
    data_admissao,
    data_nascimento,
    data_saida
  )
  values (
    v_empresa_id,
    btrim(p_nome),
    btrim(p_funcao),
    p_data_admissao,
    p_data_nascimento,
    null
  )
  returning * into v_colaborador;

  v_semana_inicio :=
    p_data_admissao
    - (extract(isodow from p_data_admissao)::integer - 1);

  insert into public.quadro_pessoal_alocacao (
    colaborador_id,
    obra_id,
    tipo_alocacao,
    descricao_livre,
    semana_inicio,
    data,
    periodo,
    criado_por
  )
  values (
    v_colaborador.id,
    case
      when p_alocacao_tipo = 'obra' then p_obra_id
      else null
    end,
    p_alocacao_tipo,
    case
      when p_alocacao_tipo = 'escritorio' then 'Escritório'
      else null
    end,
    v_semana_inicio,
    p_data_admissao,
    'dia_inteiro',
    v_utilizador_id
  )
  returning * into v_alocacao;

  return jsonb_build_object(
    'colaborador', to_jsonb(v_colaborador),
    'alocacao', to_jsonb(v_alocacao)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_criar_colaborador_com_alocacao(p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date, p_alocacao_tipo text, p_obra_id uuid, p_nivel text, p_valor_hora numeric, p_nif text, p_email text, p_contacto text, p_morada text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_empresa_id uuid;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_colaborador public.colaboradores%rowtype;
  v_alocacao public.quadro_pessoal_alocacao%rowtype;
  v_semana_inicio date;
begin
  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
  ) then
    raise exception
      'A criação de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_valor_hora is not null and p_valor_hora < 0 then
    raise exception 'O valor/hora não pode ser negativo.';
  end if;

  if p_alocacao_tipo not in ('obra', 'escritorio') then
    raise exception
      'A alocação inicial deve ser uma obra ativa ou o Escritório.';
  end if;

  select u.empresa_id
  into v_empresa_id
  from public.utilizadores u
  where u.id = v_utilizador_id;

  if v_empresa_id is null and public.fn_e_admin() then
    select e.id
    into v_empresa_id
    from public.empresas e
    limit 1;
  end if;

  if v_empresa_id is null then
    raise exception
      'Não foi possível identificar a empresa do utilizador atual.';
  end if;

  if p_alocacao_tipo = 'obra' then
    if p_obra_id is null or not exists (
      select 1
      from public.obras o
      where o.id = p_obra_id
        and coalesce(lower(o.situacao), '') not in (
          'concluida',
          'concluído',
          'concluido',
          'cancelada'
        )
    ) then
      raise exception
        'Selecione uma obra ativa válida para a alocação inicial.';
    end if;
  elsif p_obra_id is not null then
    raise exception
      'A alocação de Escritório não pode ficar ligada a uma obra.';
  end if;

  insert into public.colaboradores (
    empresa_id,
    nome,
    funcao,
    nivel,
    valor_hora,
    nif,
    email,
    contacto,
    morada,
    data_admissao,
    data_nascimento,
    data_saida
  )
  values (
    v_empresa_id,
    btrim(p_nome),
    btrim(p_funcao),
    nullif(btrim(p_nivel), ''),
    p_valor_hora,
    nullif(btrim(p_nif), ''),
    nullif(btrim(p_email), ''),
    nullif(btrim(p_contacto), ''),
    nullif(btrim(p_morada), ''),
    p_data_admissao,
    p_data_nascimento,
    null
  )
  returning *
  into v_colaborador;

  v_semana_inicio :=
    p_data_admissao
    - (extract(isodow from p_data_admissao)::integer - 1);

  insert into public.quadro_pessoal_alocacao (
    colaborador_id,
    obra_id,
    tipo_alocacao,
    descricao_livre,
    semana_inicio,
    data,
    periodo,
    criado_por
  )
  values (
    v_colaborador.id,
    case
      when p_alocacao_tipo = 'obra' then p_obra_id
      else null
    end,
    p_alocacao_tipo,
    case
      when p_alocacao_tipo = 'escritorio' then 'Escritório'
      else null
    end,
    v_semana_inicio,
    p_data_admissao,
    'dia_inteiro',
    v_utilizador_id
  )
  returning *
  into v_alocacao;

  return jsonb_build_object(
    'colaborador', to_jsonb(v_colaborador),
    'alocacao', to_jsonb(v_alocacao)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_pode_gerir_quadro(p_obra_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.utilizadores u
    WHERE u.id = public.fn_utilizador_atual_id()
      AND u.ativo IS TRUE
      AND u.funcao IN ('gestao_plataforma', 'administrativo')
      AND (
        p_obra_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.obras o
          WHERE o.id = p_obra_id
            AND o.empresa_id = u.empresa_id
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_quadro_minha_obra(p_obra_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.utilizadores u
    JOIN public.obra_responsaveis r
      ON r.utilizador_id = u.id
     AND r.papel = 'encarregado'
    JOIN public.obras o
      ON o.id = r.obra_id
     AND o.empresa_id = u.empresa_id
    WHERE u.id = public.fn_utilizador_atual_id()
      AND u.ativo IS TRUE
      AND u.funcao = 'encarregado'
      AND o.id = p_obra_id
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_pode_consultar_quadro()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.fn_e_administrativo()
    or exists (
      select 1 from public.utilizadores u
      where u.id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'encarregado')
        and coalesce(u.ativo, true)
    );
$function$;
DO $$ DECLARE r record; BEGIN FOR r IN SELECT policyname,tablename FROM pg_policies WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') LOOP EXECUTE format('DROP POLICY %I ON public.%I',r.policyname,r.tablename); END LOOP; END $$;
CREATE POLICY "quadro_pessoal_operacional_select" ON public.quadro_pessoal_alocacao AS PERMISSIVE FOR SELECT TO "authenticated" USING (fn_pode_consultar_quadro());
CREATE POLICY "quadro_v3_delete" ON public.quadro_pessoal_alocacao AS PERMISSIVE FOR DELETE TO "authenticated" USING (fn_pode_gerir_quadro(obra_id));
CREATE POLICY "quadro_v3_insert" ON public.quadro_pessoal_alocacao AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((fn_pode_gerir_quadro(obra_id) AND (criado_por = fn_utilizador_atual_id())));
CREATE POLICY "quadro_v3_update" ON public.quadro_pessoal_alocacao AS PERMISSIVE FOR UPDATE TO "authenticated" USING (fn_pode_gerir_quadro(obra_id)) WITH CHECK (fn_pode_gerir_quadro(obra_id));
REVOKE ALL ON public.quadro_pessoal_alocacao FROM PUBLIC,anon,authenticated,service_role;
GRANT INSERT,SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN ON public.quadro_pessoal_alocacao TO "service_role";
GRANT INSERT,SELECT,UPDATE,DELETE ON public.quadro_pessoal_alocacao TO "authenticated";
CREATE POLICY "quadro_v3_historico" ON public.quadro_pessoal_movimentos AS PERMISSIVE FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM utilizadores u
  WHERE ((u.id = fn_utilizador_atual_id()) AND (u.ativo IS TRUE) AND (u.empresa_id = quadro_pessoal_movimentos.empresa_id)))) AND (fn_pode_gerir_quadro(NULL::uuid) OR fn_quadro_minha_obra(obra_origem_id) OR fn_quadro_minha_obra(obra_destino_id))));
REVOKE ALL ON public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
GRANT INSERT,SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN ON public.quadro_pessoal_movimentos TO "service_role";
GRANT SELECT ON public.quadro_pessoal_movimentos TO "authenticated";
CREATE OR REPLACE FUNCTION public.fn_listar_ponto_obra(p_data date DEFAULT CURRENT_DATE, p_obra_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_atual public.utilizadores;
  v_empresa_id uuid;
  v_pode_gerir boolean;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  v_empresa_id := v_atual.empresa_id;
  v_pode_gerir := public.fn_e_admin() or public.fn_e_administrativo();
  if not v_pode_gerir and v_atual.funcao <> 'encarregado' then
    raise exception 'O ponto estÃ¡ disponÃ­vel apenas para o Administrativo, GestÃ£o e Encarregados.' using errcode = '42501';
  end if;
  if p_obra_id is not null and not exists (
    select 1 from public.obras o where o.id = p_obra_id and o.empresa_id = v_empresa_id
      and (v_pode_gerir or public.fn_e_encarregado_da_obra(o.id))
  ) then raise exception 'Sem permissÃ£o para consultar o ponto desta obra.' using errcode = '42501'; end if;

  return jsonb_build_object(
    'data', p_data,
    'pode_validar', v_pode_gerir,
    'obras', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'numero', o.numero, 'nome', o.nome) order by o.numero, o.nome)
      from public.obras o
      where o.empresa_id = v_empresa_id
        and o.situacao in ('preparacao','em_curso','receb_provisoria')
        and (v_pode_gerir or public.fn_e_encarregado_da_obra(o.id))
    ), '[]'::jsonb),
    'linhas', case when p_obra_id is null then '[]'::jsonb else coalesce((
      with eventos as (
        select q.*, slot.periodo_efetivo
        from public.quadro_pessoal_alocacao q
        join public.colaboradores c on c.id = q.colaborador_id and c.empresa_id = v_empresa_id
        cross join lateral unnest(case when q.periodo = 'dia_inteiro'
          then array['manha','tarde']::text[] else array[q.periodo]::text[] end) slot(periodo_efetivo)
        where q.data <= p_data and c.data_saida is null
      ), efetivos as (
        select distinct on (colaborador_id, periodo_efetivo)
          colaborador_id, obra_id, tipo_alocacao, periodo_efetivo, data, criado_em
        from eventos
        order by colaborador_id, periodo_efetivo, data desc, criado_em desc, id desc
      ), equipa as (
        select e.colaborador_id, e.obra_id,
          array_agg(e.periodo_efetivo order by e.periodo_efetivo) as periodos
        from efetivos e
        where e.obra_id = p_obra_id and e.tipo_alocacao = 'obra'
        group by e.colaborador_id, e.obra_id
      )
      select jsonb_agg(jsonb_build_object(
        'colaborador_id', c.id,
        'nome', c.nome,
        'funcao', c.funcao,
        'periodos', eq.periodos,
        'ponto', case when p.id is null then null else to_jsonb(p) end,
        'ausencia', case when a.id is null then null else to_jsonb(a) end
      ) order by
        case
          when lower(coalesce(c.funcao,'')) like '%encarreg%' then 1
          when lower(coalesce(c.funcao,'')) like '%pedreiro%' then 2
          when lower(coalesce(c.funcao,'')) like '%servente%' then 3
          else 4 end,
        c.nome)
      from equipa eq
      join public.colaboradores c on c.id = eq.colaborador_id
      left join public.ponto_pessoal_obra p
        on p.colaborador_id = c.id and p.obra_id = p_obra_id and p.data = p_data
      left join public.ausencias a
        on a.colaborador_id = c.id and a.data = p_data
    ), '[]'::jsonb) end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_guardar_ponto_obra(p_obra_id uuid, p_colaborador_id uuid, p_data date, p_estado text, p_entrada_manha time without time zone DEFAULT NULL::time without time zone, p_saida_manha time without time zone DEFAULT NULL::time without time zone, p_entrada_tarde time without time zone DEFAULT NULL::time without time zone, p_saida_tarde time without time zone DEFAULT NULL::time without time zone, p_observacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_atual public.utilizadores;
  v_empresa_id uuid;
  v_pode_gerir boolean;
  v_periodos text[];
  v_horas numeric(5,2);
  v_registo public.ponto_pessoal_obra;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  v_empresa_id := v_atual.empresa_id;
  v_pode_gerir := public.fn_e_admin() or public.fn_e_administrativo();
  if not v_pode_gerir and not public.fn_e_encarregado_da_obra(p_obra_id) then
    raise exception 'Sem permissÃ£o para registar o ponto desta obra.' using errcode = '42501';
  end if;
  if p_estado not in ('presente','falta_com_justificacao','falta_sem_justificacao') then
    raise exception 'Estado de presenÃ§a invÃ¡lido.';
  end if;
  if p_estado = 'falta_com_justificacao' and nullif(btrim(p_observacao), '') is null then
    raise exception 'Indique a justificaÃ§Ã£o apresentada pelo colaborador.';
  end if;

  with eventos as (
    select q.*, slot.periodo_efetivo
    from public.quadro_pessoal_alocacao q
    cross join lateral unnest(case when q.periodo = 'dia_inteiro'
      then array['manha','tarde']::text[] else array[q.periodo]::text[] end) slot(periodo_efetivo)
    where q.colaborador_id = p_colaborador_id and q.data <= p_data
  ), efetivos as (
    select distinct on (periodo_efetivo) obra_id, tipo_alocacao, periodo_efetivo
    from eventos order by periodo_efetivo, data desc, criado_em desc, id desc
  )
  select array_agg(periodo_efetivo order by periodo_efetivo) into v_periodos
  from efetivos where obra_id = p_obra_id and tipo_alocacao = 'obra';

  if coalesce(cardinality(v_periodos), 0) = 0 then
    raise exception 'Este colaborador nÃ£o estÃ¡ alocado a esta obra na data indicada.';
  end if;
  if not exists (select 1 from public.colaboradores c where c.id = p_colaborador_id and c.empresa_id = v_empresa_id) then
    raise exception 'Colaborador inexistente ou fora da empresa.';
  end if;
  if p_estado = 'presente' and exists (
    select 1 from public.ausencias a
    where a.colaborador_id = p_colaborador_id and a.data = p_data
      and (a.tipo = 'ferias' or a.estado in ('confirmada','justificada'))
  ) then
    raise exception 'Este colaborador tem uma ausÃªncia ou fÃ©rias jÃ¡ confirmadas nesta data.';
  end if;

  if p_estado = 'presente' then
    if 'manha' = any(v_periodos) and (p_entrada_manha is null or p_saida_manha is null or p_saida_manha <= p_entrada_manha) then
      raise exception 'Preencha um horÃ¡rio vÃ¡lido para a manhÃ£.';
    end if;
    if 'tarde' = any(v_periodos) and (p_entrada_tarde is null or p_saida_tarde is null or p_saida_tarde <= p_entrada_tarde) then
      raise exception 'Preencha um horÃ¡rio vÃ¡lido para a tarde.';
    end if;
    if p_saida_manha is not null and p_entrada_tarde is not null and p_entrada_tarde < p_saida_manha then
      raise exception 'Os perÃ­odos da manhÃ£ e da tarde nÃ£o podem sobrepor-se.';
    end if;
    if not ('manha'=any(v_periodos)) then p_entrada_manha:=null; p_saida_manha:=null; end if;
    if not ('tarde'=any(v_periodos)) then p_entrada_tarde:=null; p_saida_tarde:=null; end if;
    v_horas := public.fn_ponto_horas(
      p_entrada_manha, p_saida_manha, p_entrada_tarde, p_saida_tarde
    );
    if v_horas <= 0 or v_horas > 16 then raise exception 'O total diÃ¡rio deve estar entre 0 e 16 horas.'; end if;
    if exists (
      select 1 from public.ponto_pessoal_obra outro
      where outro.colaborador_id=p_colaborador_id and outro.data=p_data
        and outro.obra_id<>p_obra_id and outro.estado='presente'
        and (
          (p_entrada_manha is not null and outro.entrada_manha is not null and p_entrada_manha < outro.saida_manha and outro.entrada_manha < p_saida_manha)
          or (p_entrada_manha is not null and outro.entrada_tarde is not null and p_entrada_manha < outro.saida_tarde and outro.entrada_tarde < p_saida_manha)
          or (p_entrada_tarde is not null and outro.entrada_manha is not null and p_entrada_tarde < outro.saida_manha and outro.entrada_manha < p_saida_tarde)
          or (p_entrada_tarde is not null and outro.entrada_tarde is not null and p_entrada_tarde < outro.saida_tarde and outro.entrada_tarde < p_saida_tarde)
        )
    ) then raise exception 'O horÃ¡rio sobrepÃµe-se ao ponto deste colaborador noutra obra.'; end if;
  else
    v_horas := 0;
    p_entrada_manha := null; p_saida_manha := null;
    p_entrada_tarde := null; p_saida_tarde := null;
  end if;

  insert into public.ponto_pessoal_obra(
    empresa_id, obra_id, colaborador_id, data, periodos_alocados, estado,
    entrada_manha, saida_manha, entrada_tarde, saida_tarde, horas,
    observacao, justificacao_estado, registado_por, atualizado_por, atualizado_em
  ) values (
    v_empresa_id, p_obra_id, p_colaborador_id, p_data, v_periodos, p_estado,
    p_entrada_manha, p_saida_manha, p_entrada_tarde, p_saida_tarde, v_horas,
    nullif(btrim(p_observacao), ''),
    case when p_estado='falta_com_justificacao' then 'pendente' else 'nao_aplicavel' end,
    v_atual.id, v_atual.id, now()
  ) on conflict (colaborador_id, obra_id, data) do update set
    periodos_alocados = excluded.periodos_alocados,
    estado = excluded.estado,
    entrada_manha = excluded.entrada_manha,
    saida_manha = excluded.saida_manha,
    entrada_tarde = excluded.entrada_tarde,
    saida_tarde = excluded.saida_tarde,
    horas = excluded.horas,
    observacao = excluded.observacao,
    justificacao_estado = excluded.justificacao_estado,
    atualizado_por = v_atual.id,
    atualizado_em = now()
  returning * into v_registo;

  return to_jsonb(v_registo);
end;
$function$;
DROP FUNCTION public.fn_quadro_renomear_interno(jsonb,boolean,text);
DROP FUNCTION public.fn_quadro_contexto(date,date);
DROP FUNCTION public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean);
DROP FUNCTION public.fn_quadro_criar_colaborador_interno(text,text,date,date,text,uuid,text,numeric,text,text,text,text,text);
DROP FUNCTION public.fn_quadro_dia_explicito(uuid,date);
DROP FUNCTION public.fn_quadro_resolver_data(date);
DROP FUNCTION public.fn_quadro_ler_obra(uuid);
ALTER TABLE public.quadro_pessoal_movimentos DROP COLUMN origem_operacao,DROP COLUMN request_id;
DROP TABLE public.quadro_escrita_interna,public.quadro_dias_revisoes,public.quadro_operacoes;
COMMIT;
