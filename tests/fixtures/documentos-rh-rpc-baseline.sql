CREATE OR REPLACE FUNCTION public.fn_apagar_documento_entidade(p_documento_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar documentos de entidades.';
  end if;

  if not exists (
    select 1
    from public.documentos
    where id = p_documento_id
  ) then
    raise exception 'Documento não encontrado.';
  end if;

  delete from public.documentos
  where id = p_documento_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_apagar_documento_entidade(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_documento_entidade(uuid) TO authenticated;
