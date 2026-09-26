-- Run inside a transaction and ROLLBACK. Uses two existing account identities,
-- never creates users and never commits test button rows.
select set_config('test.buttons_owner_a', (select id::text from auth.users order by id limit 1), true);
select set_config('test.buttons_owner_b', (select id::text from auth.users order by id offset 1 limit 1), true);
select set_config('request.jwt.claim.sub', current_setting('test.buttons_owner_a'), true);
set local role authenticated;
insert into public.desktop_user_prompts(id, user_id, slot, title, prompt, origin)
values ('00000000-0000-4000-8000-000000000001', auth.uid(), 'sub', 'Storage test', 'Original', 'user_authored');
do $$
begin
  if not exists(select 1 from public.desktop_user_prompts where id='00000000-0000-4000-8000-000000000001') then
    raise exception 'Owner cannot read inserted button';
  end if;
  update public.desktop_user_prompts set prompt='Edited' where id='00000000-0000-4000-8000-000000000001';
  if not exists(select 1 from public.desktop_user_prompts where id='00000000-0000-4000-8000-000000000001' and prompt='Edited') then
    raise exception 'Owner cannot update button';
  end if;
  begin
    update public.desktop_user_prompts set user_id=current_setting('test.buttons_owner_b')::uuid
    where id='00000000-0000-4000-8000-000000000001';
    raise exception 'Ownership reassignment was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub', current_setting('test.buttons_owner_b'), true);
do $$
declare affected integer;
begin
  if exists(select 1 from public.desktop_user_prompts where user_id=current_setting('test.buttons_owner_a')::uuid) then
    raise exception 'Another owner can read buttons';
  end if;
  update public.desktop_user_prompts set prompt='Stolen' where id='00000000-0000-4000-8000-000000000001';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Cross-account update was allowed'; end if;
  delete from public.desktop_user_prompts where id='00000000-0000-4000-8000-000000000001';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Cross-account delete was allowed'; end if;
  begin
    insert into public.desktop_user_prompts(user_id,slot,title,prompt)
    values(current_setting('test.buttons_owner_a')::uuid,'sub','Wrong owner','Wrong owner');
    raise exception 'Cross-account insert was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub', current_setting('test.buttons_owner_a'), true);
delete from public.desktop_user_prompts where id='00000000-0000-4000-8000-000000000001';
do $$ begin
  if exists(select 1 from public.desktop_user_prompts where id='00000000-0000-4000-8000-000000000001') then
    raise exception 'Owner cannot delete button';
  end if;
end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform 1 from public.desktop_user_prompts;
    raise exception 'Anonymous access was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
