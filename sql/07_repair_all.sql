-- AuctionX repair + upgrade. Run in the "Bid league" Supabase project (olaubcixtxsnkjiovucz). Safe to run again.

-- columns the app uses
alter table players add column if not exists sold_at timestamptz;
alter table players add column if not exists city text;
alter table players add column if not exists batting_style text;
alter table players add column if not exists bowling_style text;
alter table players add column if not exists age int;
alter table tournaments add column if not exists views int default 0;
alter table tournaments add column if not exists youtube_url text;
alter table tournaments add column if not exists live_theme text default 'classic';
alter table tournaments add column if not exists reg_open boolean default true;
alter table sponsors add column if not exists kind text default 'Sponsor';
alter table sponsors add column if not exists amount int default 0;
create table if not exists player_contacts (player_id uuid primary key references players on delete cascade, phone text);

create or replace function is_owner(t uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from tournaments where id = t and owner_id = auth.uid()) $$;

-- put a player on the block (available or unsold players)
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
    leading_team_id = null, timer_ends_at = null, version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function mark_sold(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into s from auction_state where tournament_id = p_tournament for update;
  if s.status::text <> 'bidding' or s.leading_team_id is null then raise exception 'No winning bid yet'; end if;
  update players set auction_status = 'sold', sold_team_id = s.leading_team_id, sold_price = s.current_bid, sold_at = now()
    where id = s.current_player_id;
  insert into audit_log (tournament_id, action, player_id, team_id, amount, actor_id)
    values (p_tournament, 'sold', s.current_player_id, s.leading_team_id, s.current_bid, auth.uid());
  update auction_state set status = 'idle', current_player_id = null, leading_team_id = null,
    current_bid = 0, version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function mark_unsold(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into s from auction_state where tournament_id = p_tournament for update;
  if s.status::text <> 'bidding' then raise exception 'No player on the block'; end if;
  update players set auction_status = 'unsold' where id = s.current_player_id;
  insert into audit_log (tournament_id, action, player_id, actor_id)
    values (p_tournament, 'unsold', s.current_player_id, auth.uid());
  update auction_state set status = 'idle', current_player_id = null, leading_team_id = null,
    current_bid = 0, version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function undo_last_sale(p_tournament uuid) returns void
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
  update players set auction_status = 'available', sold_team_id = null, sold_price = null, sold_at = null where id = a.player_id;
  insert into audit_log (tournament_id, action, player_id, team_id, amount, actor_id)
    values (p_tournament, 'undo', a.player_id, a.team_id, a.amount, auth.uid());
  update auction_state set version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function reauction_unsold(p_tournament uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  update players set auction_status = 'available' where tournament_id = p_tournament and auction_status::text = 'unsold';
  update auction_state set version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function edit_live_price(p_tournament uuid, p_amount int) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype; b int; pur int; spent int;
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  select * into s from auction_state where tournament_id = p_tournament for update;
  if s.status::text <> 'bidding' then raise exception 'No player on the block'; end if;
  select base_price into b from players where id = s.current_player_id;
  if p_amount < b then raise exception 'Price cannot go below base %', b; end if;
  if s.leading_team_id is not null then
    select team_purse into pur from auction_rules where tournament_id = p_tournament;
    select coalesce(sum(sold_price), 0) into spent from players
      where sold_team_id = s.leading_team_id and auction_status::text = 'sold';
    if pur - spent < p_amount then raise exception 'Leading team does not have enough purse'; end if;
  end if;
  update auction_state set current_bid = p_amount, version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function set_captain(p_team uuid, p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare tid uuid; uid uuid;
begin
  select tournament_id into tid from teams where id = p_team;
  if tid is null or not is_owner(tid) then raise exception 'Only the organizer can do this'; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'No account with this email. Ask the captain to sign up first'; end if;
  update teams set captain_user_id = uid where id = p_team;
end $$;

create or replace function set_auto_sold(p_tournament uuid, p_value boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner(p_tournament) then raise exception 'Only the organizer can do this'; end if;
  update auction_rules set auto_sold = p_value where tournament_id = p_tournament;
  update auction_state set version = version + 1 where tournament_id = p_tournament;
end $$;

create or replace function add_view(p_tournament uuid) returns void
language sql security definer set search_path = public as $$
  update tournaments set views = coalesce(views, 0) + 1 where id = p_tournament $$;

create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  delete from payments where user_id = auth.uid();
  delete from tournaments where owner_id = auth.uid();
  update teams set captain_user_id = null where captain_user_id = auth.uid();
  update bids set placed_by = null where placed_by = auth.uid();
  delete from auth.users where id = auth.uid();
end $$;

create or replace function check_reg_open() returns trigger language plpgsql as $$
begin
  if new.source = 'link' and exists (select 1 from tournaments where id = new.tournament_id and reg_open = false) then
    raise exception 'Registration is closed';
  end if;
  return new;
end $$;
drop trigger if exists trg_reg_open on players;
create trigger trg_reg_open before insert on players for each row execute function check_reg_open();

-- player self registration (now with city, age, batting and bowling style)
drop function if exists register_player;
create function register_player(p_code text, p_name text, p_phone text, p_role text, p_photo text, p_jersey text,
                                p_tshirt text, p_city text, p_batting text, p_bowling text, p_age int) returns void
language plpgsql security definer set search_path = public as $$
declare tid uuid; b int; pid uuid; n int;
begin
  select id into tid from tournaments where join_code = upper(p_code);
  if tid is null then raise exception 'Invalid auction code'; end if;
  if length(trim(p_name)) < 2 then raise exception 'Enter your name'; end if;
  select count(*) into n from players where tournament_id = tid and source = 'link' and reg_status::text = 'pending';
  if n >= 500 then raise exception 'Too many pending registrations'; end if;
  select base_price into b from auction_rules where tournament_id = tid;
  insert into players (tournament_id, name, role, photo_url, jersey_name, tshirt_size, city, batting_style, bowling_style,
                       age, base_price, reg_status, source)
    values (tid, trim(p_name), p_role, p_photo, p_jersey, p_tshirt, p_city, p_batting, p_bowling,
            p_age, coalesce(b, 50), 'pending', 'link')
    returning id into pid;
  insert into player_contacts (player_id, phone) values (pid, p_phone);
end $$;

notify pgrst, 'reload schema';
