-- A executer une seule fois dans le SQL Editor Supabase.
-- L'application de production passe par l'API Vercel. Les navigateurs ne
-- doivent donc avoir aucun acces direct aux tables contenant des e-mails.

revoke all on table public.clients from anon, authenticated;
revoke all on table public.sessions from anon, authenticated;
revoke all on table public.photos from anon, authenticated;
revoke all on table public.device_logs from anon, authenticated;

grant all on table public.clients to service_role;
grant all on table public.sessions to service_role;
grant all on table public.photos to service_role;
grant all on table public.device_logs to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Les quatre tables doivent indiquer relrowsecurity=true.
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('clients', 'sessions', 'photos', 'device_logs')
order by relname;
