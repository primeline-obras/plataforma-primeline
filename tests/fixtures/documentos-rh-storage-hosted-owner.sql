-- SYNTHETIC LOCAL FIXTURE ONLY. Never run against Supabase.
-- Existing generic suites bootstrap as superuser; the hosted-resume suite
-- separately demotes its postgres executor and has no Storage-owner membership.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_storage_admin') THEN
  CREATE ROLE supabase_storage_admin NOLOGIN NOSUPERUSER;
 END IF;
END $$;
ALTER TABLE storage.objects OWNER TO supabase_storage_admin;
ALTER TABLE storage.buckets OWNER TO supabase_storage_admin;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO supabase_storage_admin;
GRANT SELECT ON storage.objects,storage.buckets TO postgres;
