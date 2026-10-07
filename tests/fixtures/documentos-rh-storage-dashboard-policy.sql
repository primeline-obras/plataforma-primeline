-- SYNTHETIC ONLY. Emulates the approved external policy editor using a separate local owner.
-- Never a production SQL rollout script; no role/ownership/grant changes.
DO $external_policy$ DECLARE p record; stmt text; BEGIN
 FOR p IN SELECT * FROM primeline_documentos_rh_backup.policies WHERE schemaname='storage' AND tablename='objects' ORDER BY policyname LOOP
  stmt:=format('ALTER POLICY %I ON storage.objects',p.policyname);
  IF p.qual IS NOT NULL THEN stmt:=stmt||format(' USING ((%s) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name))',p.qual); END IF;
  IF p.with_check IS NOT NULL THEN stmt:=stmt||format(' WITH CHECK ((%s) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name))',p.with_check); END IF;
  EXECUTE stmt;
 END LOOP;
END $external_policy$;
