-- Invite code like MILO-XXXX (unambiguous alphabet), guaranteed unique.
create or replace function public.gen_invite_code()
returns text
language plpgsql
set search_path = public
as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
  i int;
begin
  loop
    code := 'MILO-';
    for i in 1..4 loop
      code := code || substr(alphabet, 1 + floor(random()*length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.households where invite_code = code);
  end loop;
  return code;
end $$;

-- Create a household and add the caller as its first member.
create or replace function public.create_household(hh_name text, member_name text default 'You')
returns public.households
language plpgsql
security definer
set search_path = public
as $$
declare hh public.households;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.households(name, invite_code)
    values (coalesce(nullif(hh_name,''), 'My household'), public.gen_invite_code())
    returning * into hh;
  insert into public.members(household_id, user_id, display_name, initials, palette)
    values (hh.id, auth.uid(), coalesce(nullif(member_name,''),'You'),
            upper(left(coalesce(nullif(member_name,''),'You'),1)), 'you');
  return hh;
end $$;

-- Join a household by invite code.
create or replace function public.join_household(code text, member_name text default 'Member')
returns public.households
language plpgsql
security definer
set search_path = public
as $$
declare hh public.households;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into hh from public.households where invite_code = upper(code);
  if hh.id is null then raise exception 'invalid invite code'; end if;
  insert into public.members(household_id, user_id, display_name, initials, palette)
    values (hh.id, auth.uid(), coalesce(nullif(member_name,''),'Member'),
            upper(left(coalesce(nullif(member_name,''),'Member'),1)), 'you')
  on conflict (household_id, user_id) do nothing;
  return hh;
end $$;

revoke all on function public.create_household(text,text) from public, anon;
revoke all on function public.join_household(text,text) from public, anon;
grant execute on function public.create_household(text,text) to authenticated;
grant execute on function public.join_household(text,text) to authenticated;

-- Realtime for the shared live dashboard.
alter publication supabase_realtime add table public.log_entries;
alter publication supabase_realtime add table public.dogs;
alter publication supabase_realtime add table public.members;
