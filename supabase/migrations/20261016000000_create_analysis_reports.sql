create table if not exists public.analysis_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_name text not null,
  source text not null,
  report jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists analysis_reports_user_created_idx
  on public.analysis_reports (user_id, created_at desc);

alter table public.analysis_reports enable row level security;

create policy "Users can read their own analysis reports"
  on public.analysis_reports for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can save their own analysis reports"
  on public.analysis_reports for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can delete their own analysis reports"
  on public.analysis_reports for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.prompt_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_name text not null,
  original_prompt text not null,
  enhanced_prompt text not null,
  created_at timestamptz not null default now()
);

create index if not exists prompt_history_user_created_idx
  on public.prompt_history (user_id, created_at desc);

alter table public.prompt_history enable row level security;

create policy "Users can read their own prompt history"
  on public.prompt_history for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can save their own prompt history"
  on public.prompt_history for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can delete their own prompt history"
  on public.prompt_history for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.ai_usage_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists ai_usage_events_user_created_idx
  on public.ai_usage_events (user_id, created_at desc);

alter table public.ai_usage_events enable row level security;
revoke all on public.ai_usage_events from anon, authenticated;

create or replace function public.consume_ai_request()
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_user_id uuid := auth.uid();
  recent_requests integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(current_user_id::text, 0));
  delete from public.ai_usage_events
    where user_id = current_user_id
      and created_at < now() - interval '1 day';

  select count(*) into recent_requests
    from public.ai_usage_events
    where user_id = current_user_id
      and created_at > now() - interval '1 minute';

  if recent_requests >= 5 then
    return false;
  end if;

  insert into public.ai_usage_events (user_id) values (current_user_id);
  return true;
end;
$$;

revoke all on function public.consume_ai_request() from public, anon;
grant execute on function public.consume_ai_request() to authenticated;
