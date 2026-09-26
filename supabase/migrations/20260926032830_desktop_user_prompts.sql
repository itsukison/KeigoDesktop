-- Desktop buttons become independent of the phone. No phone rows or triggers change.
-- The guard also makes replaying this migration harmless: the snapshot happens once,
-- never as an ongoing import for new desktop accounts or deleted configurations.
do $migration$
begin
  if to_regclass('public.desktop_user_prompts') is not null then
    return;
  end if;

  create table public.desktop_user_prompts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    slot text not null check (slot in ('main', 'sub')),
    builtin_key text check (builtin_key in ('polite', 'natural', 'email', 'translateToEnglish')),
    title text not null,
    prompt text not null,
    is_enabled boolean not null default true,
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    origin text check (origin is null or origin in ('builtin', 'onboarding_builder', 'onboarding_preset', 'user_authored'))
  );
  create index desktop_user_prompts_user_sort_idx
    on public.desktop_user_prompts (user_id, slot, sort_order);
  create unique index desktop_user_prompts_user_builtin_unique
    on public.desktop_user_prompts (user_id, builtin_key) where builtin_key is not null;
  create trigger desktop_user_prompts_touch_updated_at before update
    on public.desktop_user_prompts for each row execute function public.touch_updated_at();

  alter table public.desktop_user_prompts enable row level security;
  revoke all on public.desktop_user_prompts from public, anon, authenticated;
  grant select, insert, update, delete on public.desktop_user_prompts to authenticated;
  grant all on public.desktop_user_prompts to service_role;
  create policy desktop_buttons_select on public.desktop_user_prompts
    for select to authenticated using ((select auth.uid()) = user_id);
  create policy desktop_buttons_insert on public.desktop_user_prompts
    for insert to authenticated with check ((select auth.uid()) = user_id);
  create policy desktop_buttons_update on public.desktop_user_prompts
    for update to authenticated using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
  create policy desktop_buttons_delete on public.desktop_user_prompts
    for delete to authenticated using ((select auth.uid()) = user_id);

  insert into public.desktop_user_prompts
    (id, user_id, slot, builtin_key, title, prompt, is_enabled, sort_order, created_at, updated_at, origin)
  select p.id, p.user_id, p.slot, p.builtin_key, p.title, p.prompt,
         p.is_enabled, p.sort_order, p.created_at, p.updated_at, p.origin
  from public.user_prompts p
  where exists (select 1 from desktop.activations a where a.user_id = p.user_id);
end;
$migration$;
