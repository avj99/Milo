-- Returns the household ids the current user belongs to.
-- SECURITY DEFINER so it bypasses RLS on members (avoids policy recursion).
create or replace function public.user_households()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $$
  select household_id from public.members where user_id = auth.uid()
$$;
revoke all on function public.user_households() from public, anon;
grant execute on function public.user_households() to authenticated;

alter table public.households    enable row level security;
alter table public.members       enable row level security;
alter table public.dogs          enable row level security;
alter table public.dog_allergens enable row level security;
alter table public.products      enable row level security;
alter table public.log_entries   enable row level security;

-- Households: members can read/rename their own household.
-- (creation/joining goes through SECURITY DEFINER RPCs, so no direct insert policy.)
create policy hh_select on public.households for select to authenticated
  using (id in (select public.user_households()));
create policy hh_update on public.households for update to authenticated
  using (id in (select public.user_households()))
  with check (id in (select public.user_households()));

-- Members: read members of your households; you may only remove yourself.
-- (adding members is done via join_household RPC, not direct insert.)
create policy member_select on public.members for select to authenticated
  using (household_id in (select public.user_households()));
create policy member_delete_self on public.members for delete to authenticated
  using (user_id = auth.uid());

create policy dogs_all on public.dogs for all to authenticated
  using (household_id in (select public.user_households()))
  with check (household_id in (select public.user_households()));

create policy dog_allergens_all on public.dog_allergens for all to authenticated
  using (dog_id in (select id from public.dogs where household_id in (select public.user_households())))
  with check (dog_id in (select id from public.dogs where household_id in (select public.user_households())));

create policy products_all on public.products for all to authenticated
  using (household_id in (select public.user_households()))
  with check (household_id in (select public.user_households()));

create policy log_all on public.log_entries for all to authenticated
  using (household_id in (select public.user_households()))
  with check (household_id in (select public.user_households()));
