-- Run AFTER the schema, step_for() and place_bid() from the BidLeague doc.
create function is_owner(t uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from tournaments where id = t and owner_id = auth.uid()) $$;

create function create_tournament(p_name text, p_purse int default 10000) returns uuid
language plpgsql security definer set search_path = public as $$
declare tid uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  insert into tournaments (owner_id, name, join_code)
    values (auth.uid(), p_name, upper(substr(md5(random()::text), 1, 6))) returning id into tid;
  insert into auction_rules (tournament_id, team_purse) values (tid, p_purse);
  insert into auction_state (tournament_id) values (tid);
  return tid;
end $$;

create function start_player(p_tournament uuid, p_player uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b int;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select base_price into b from players
    where id = p_player and tournament_id = p_tournament and auction_status = 'available';
  if b is null then raise exception 'Player not available'; end if;
  update auction_state set status = 'bidding', current_player_id = p_player, current_bid = b,
    leading_team_id = null, timer_ends_at = null, version = version + 1
  where tournament_id = p_tournament;
end $$;

create function bid_next(p_tournament uuid, p_team uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype; r auction_rules%rowtype; amt int;
begin
  select * into s from auction_state where tournament_id = p_tournament;
  select * into r from auction_rules where tournament_id = p_tournament;
  amt := case when s.leading_team_id is null then s.current_bid
              else s.current_bid + step_for(r.increment_tiers, s.current_bid) end;
  perform place_bid(p_tournament, p_team, amt);
end $$;

create function mark_sold(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into s from auction_state where tournament_id = p_tournament for update;
  if s.status <> 'bidding' or s.leading_team_id is null then raise exception 'No winning bid yet'; end if;
  update players set auction_status = 'sold', sold_team_id = s.leading_team_id, sold_price = s.current_bid
    where id = s.current_player_id;
  insert into audit_log (tournament_id, action, player_id, team_id, amount, actor_id)
    values (p_tournament, 'sold', s.current_player_id, s.leading_team_id, s.current_bid, auth.uid());
  update auction_state set status = 'idle', current_player_id = null, leading_team_id = null,
    current_bid = 0, version = version + 1 where tournament_id = p_tournament;
end $$;

create function mark_unsold(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into s from auction_state where tournament_id = p_tournament for update;
  if s.status <> 'bidding' then raise exception 'No player on the block'; end if;
  update players set auction_status = 'unsold' where id = s.current_player_id;
  insert into audit_log (tournament_id, action, player_id, actor_id)
    values (p_tournament, 'unsold', s.current_player_id, auth.uid());
  update auction_state set status = 'idle', current_player_id = null, leading_team_id = null,
    current_bid = 0, version = version + 1 where tournament_id = p_tournament;
end $$;

create function edit_live_price(p_tournament uuid, p_amount int) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype; b int; pur int; spent int;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into s from auction_state where tournament_id = p_tournament for update;
  if s.status <> 'bidding' then raise exception 'No player on the block'; end if;
  select base_price into b from players where id = s.current_player_id;
  if p_amount < b then raise exception 'Price cannot go below base %', b; end if;
  if s.leading_team_id is not null then
    select team_purse into pur from auction_rules where tournament_id = p_tournament;
    select coalesce(sum(sold_price), 0) into spent from players
      where sold_team_id = s.leading_team_id and auction_status = 'sold';
    if pur - spent < p_amount then raise exception 'Leading team does not have enough purse'; end if;
  end if;
  update auction_state set current_bid = p_amount, version = version + 1 where tournament_id = p_tournament;
end $$;

create function reauction_unsold(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  update players set auction_status = 'available' where tournament_id = p_tournament and auction_status = 'unsold';
end $$;

-- Row Level Security
alter table profiles enable row level security;
alter table user_roles enable row level security;
alter table tournaments enable row level security;
alter table auction_rules enable row level security;
alter table teams enable row level security;
alter table players enable row level security;
alter table auction_state enable row level security;
alter table bids enable row level security;
alter table audit_log enable row level security;
alter table sponsors enable row level security;
alter table payments enable row level security;
alter table whatsapp_messages enable row level security;
alter table bookmarks enable row level security;

-- public read (live view); NOTE players.phone is readable, so do not collect phones until a public view hides it
create policy pub_read on tournaments for select using (true);
create policy pub_read on auction_rules for select using (true);
create policy pub_read on teams for select using (true);
create policy pub_read on players for select using (true);
create policy pub_read on auction_state for select using (true);
create policy pub_read on bids for select using (true);
create policy pub_read on sponsors for select using (true);

create policy own_upd on tournaments for update using (owner_id = auth.uid());
create policy own_del on tournaments for delete using (owner_id = auth.uid());
create policy own_upd on auction_rules for update using (is_owner(tournament_id));
create policy own_all on teams for all using (is_owner(tournament_id)) with check (is_owner(tournament_id));
create policy own_all on players for all using (is_owner(tournament_id)) with check (is_owner(tournament_id));
create policy own_all on sponsors for all using (is_owner(tournament_id)) with check (is_owner(tournament_id));
create policy own_read on audit_log for select using (is_owner(tournament_id));
create policy own_read on whatsapp_messages for select using (is_owner(tournament_id));
create policy own_read on payments for select using (user_id = auth.uid());
create policy own_all on profiles for all using (id = auth.uid()) with check (id = auth.uid());
create policy own_all on bookmarks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_read on user_roles for select using (user_id = auth.uid());
-- auction_state, bids: no write policies on purpose, only the functions above can change them.

alter publication supabase_realtime add table auction_state;
