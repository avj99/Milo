-- Members may edit their own row (display name / initials / palette),
-- so a profile rename in the app can sync to the household.
create policy member_update_self on public.members for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Invite codes: match the app's designed 6-character format (e.g. 4B29K7)
-- instead of MILO-XXXX. Same unambiguous alphabet, still unique.
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
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random()*length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.households where invite_code = code);
  end loop;
  return code;
end $$;
