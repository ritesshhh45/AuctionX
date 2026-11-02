-- BidLeague captain access. Run in the "Bid league" Supabase project (olaubcixtxsnkjiovucz). Safe to run again.

-- secrets live in private tables: only the organizer can read them
create table if not exists tournament_secrets (
  tournament_id uuid primary key references tournaments on delete cascade,
  captain_code text not null);
create table if not exists team_secrets (
  team_id uuid primary key references teams on delete cascade,
  pin text not null);
alter table tournament_secrets enable row level security;
alter table team_secrets enable row level security;
drop policy if exists own_read on tournament_secrets;
create policy own_read on tournament_secrets for select using (is_owner(tournament_id));
drop policy if exists own_read on team_secrets;
create policy own_read on team_secrets for select
  using (exists (select 1 from teams t where t.id = team_id and is_owner(t.tournament_id)));

-- backfill existing auctions and teams
insert into tournament_secrets (tournament_id, captain_code)
  select id, upper(substr(md5(random()::text || id::text), 1, 6)) from tournaments on conflict do nothing;
insert into team_secrets (team_id, pin)
  select id, lpad((floor(random() * 10000))::int::text, 4, '0') from teams on conflict do nothing;

-- new auctions and teams get their secrets automatically
create or replace function trg_tournament_secret() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into tournament_secrets (tournament_id, captain_code)
    values (new.id, upper(substr(md5(random()::text || new.id::text), 1, 6))) on conflict do nothing;
  return new;
end $$;
drop trigger if exists tournament_secret_ins on tournaments;
create trigger tournament_secret_ins after insert on tournaments for each row execute function trg_tournament_secret();

create or replace function trg_team_secret() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into team_secrets (team_id, pin)
    values (new.id, lpad((floor(random() * 10000))::int::text, 4, '0')) on conflict do nothing;
  return new;
end $$;
drop trigger if exists team_secret_ins on teams;
create trigger team_secret_ins after insert on teams for each row execute function trg_team_secret();

-- captain enters the captain code: list that auction's teams (and which are taken)
create or replace function captain_teams(p_code text)
returns table(team_id uuid, team_name text, tournament_id uuid, tournament_name text, claimed boolean)
language sql security definer set search_path = public as $$
  select t.id, t.name, a.id, a.name, t.captain_user_id is not null
  from tournament_secrets s
  join tournaments a on a.id = s.tournament_id
  join teams t on t.tournament_id = a.id
  where s.captain_code = upper(trim(p_code))
  order by t.name
$$;

-- captain picks a team and enters its PIN: the team is locked to this account
create or replace function claim_team(p_code text, p_team uuid, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare tid uuid; current_captain uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select teams.tournament_id, teams.captain_user_id into tid, current_captain from teams where teams.id = p_team;
  if tid is null then raise exception 'Team not found'; end if;
  if not exists (select 1 from tournament_secrets s where s.tournament_id = tid and s.captain_code = upper(trim(p_code))) then
    raise exception 'Wrong captain code';
  end if;
  if not exists (select 1 from team_secrets x where x.team_id = p_team and x.pin = trim(p_pin)) then
    raise exception 'Wrong team PIN';
  end if;
  if current_captain is not null and current_captain <> auth.uid() then
    raise exception 'This team already has a captain. Ask the organizer to reset it.';
  end if;
  if exists (select 1 from teams where teams.tournament_id = tid and teams.captain_user_id = auth.uid() and teams.id <> p_team) then
    raise exception 'You are already captain of another team in this auction';
  end if;
  update teams set captain_user_id = auth.uid() where id = p_team;
end $$;

-- organizer: remove the captain and generate a new PIN
create or replace function reset_team_access(p_team uuid) returns void
language plpgsql security definer set search_path = public as $$
declare tid uuid;
begin
  select teams.tournament_id into tid from teams where teams.id = p_team;
  if tid is null or not is_owner(tid) then raise exception 'Only the organizer can do this'; end if;
  update teams set captain_user_id = null where id = p_team;
  update team_secrets set pin = lpad((floor(random() * 10000))::int::text, 4, '0') where team_id = p_team;
end $$;

-- bid history only shows bids of the current round of a player
alter table auction_state add column if not exists block_started_at timestamptz;
create or replace function start_player(p_tournament uuid, p_player uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b int;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select base_price into b from players
    where id = p_player and tournament_id = p_tournament and auction_status::text in ('available', 'unsold');
  if b is null then raise exception 'Player not available'; end if;
  update players set auction_status = 'available' where id = p_player;
  update auction_state set status = 'bidding', current_player_id = p_player, current_bid = b,
    leading_team_id = null, timer_ends_at = null, block_started_at = now(), version = version + 1
  where tournament_id = p_tournament;
end $$;

notify pgrst, 'reload schema';
