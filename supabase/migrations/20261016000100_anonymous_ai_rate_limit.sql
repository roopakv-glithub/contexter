drop function if exists public.consume_ai_request();

create table if not exists public.ai_request_limits (
  client_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists ai_request_limits_client_created_idx
  on public.ai_request_limits (client_hash, created_at desc);

alter table public.ai_request_limits enable row level security;
revoke all on public.ai_request_limits from anon, authenticated;

create or replace function public.consume_ai_request(p_client_hash text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  recent_requests integer;
begin
  if p_client_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid client identifier';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_client_hash, 0));
  delete from public.ai_request_limits
    where client_hash = p_client_hash
      and created_at < now() - interval '1 day';

  select count(*) into recent_requests
    from public.ai_request_limits
    where client_hash = p_client_hash
      and created_at > now() - interval '1 minute';

  if recent_requests >= 5 then
    return false;
  end if;

  insert into public.ai_request_limits (client_hash) values (p_client_hash);
  return true;
end;
$$;

revoke all on function public.consume_ai_request(text) from public, anon, authenticated;
grant execute on function public.consume_ai_request(text) to service_role;
