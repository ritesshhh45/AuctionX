-- Run after 02_functions_and_rls.sql
create function set_captain(p_team uuid, p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare tid uuid; uid uuid;
begin
  select tournament_id into tid from teams where id = p_team;
  if tid is null or not is_owner(tid) then raise exception 'Only the organizer can do this'; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'No account with this email. Ask the captain to sign up first'; end if;
  update teams set captain_user_id = uid where id = p_team;
end $$;

create function set_auto_sold(p_tournament uuid, p_value boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  update auction_rules set auto_sold = p_value where tournament_id = p_tournament;
  update auction_state set version = version + 1 where tournament_id = p_tournament;
end $$;

create function undo_last_sale(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a audit_log%rowtype;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into a from audit_log l
    where l.tournament_id = p_tournament and l.action = 'sold'
      and not exists (select 1 from audit_log u where u.tournament_id = p_tournament
                      and u.action = 'undo' and u.player_id = l.player_id and u.id > l.id)
    order by l.id desc limit 1;
  if a.id is null then raise exception 'Nothing to undo'; end if;
  update players set auction_status = 'available', sold_team_id = null, sold_price = null where id = a.player_id;
  insert into audit_log (tournament_id, action, player_id, team_id, amount, actor_id)
    values (p_tournament, 'undo', a.player_id, a.team_id, a.amount, auth.uid());
  update auction_state set version = version + 1 where tournament_id = p_tournament;
end $$;
