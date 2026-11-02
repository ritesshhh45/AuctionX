-- Run after 04_create_auction.sql. Safe to run more than once.

-- Phone numbers live in a private table, never in the public players table.
create table if not exists player_contacts (player_id uuid primary key references players on delete cascade, phone text);
alter table player_contacts enable row level security;
drop policy if exists own_read on player_contacts;
create policy own_read on player_contacts for select
  using (exists (select 1 from players p where p.id = player_id and is_owner(p.tournament_id)));

-- Self registration: creates a PENDING player; organizer approves in the Players tab.
drop function if exists register_player;
create function register_player(p_code text, p_name text, p_phone text, p_role text,
                                p_photo text, p_jersey text, p_tshirt text) returns void
language plpgsql security definer set search_path = public as $$
declare tid uuid; b int; pid uuid; n int;
begin
  select id into tid from tournaments where join_code = upper(p_code);
  if tid is null then raise exception 'Invalid auction code'; end if;
  if length(trim(p_name)) < 2 then raise exception 'Enter your name'; end if;
  select count(*) into n from players where tournament_id = tid and source = 'link' and reg_status = 'pending';
  if n >= 500 then raise exception 'Too many pending registrations'; end if;
  select base_price into b from auction_rules where tournament_id = tid;
  insert into players (tournament_id, name, role, photo_url, jersey_name, tshirt_size, base_price, reg_status, source)
    values (tid, trim(p_name), p_role, p_photo, p_jersey, p_tshirt, coalesce(b, 50), 'pending', 'link')
    returning id into pid;
  insert into player_contacts (player_id, phone) values (pid, p_phone);
end $$;

-- Photo storage (public read, anyone logged in can upload)
insert into storage.buckets (id, name, public) values ('player-photos', 'player-photos', true)
  on conflict (id) do nothing;
drop policy if exists "player photos read" on storage.objects;
create policy "player photos read" on storage.objects for select using (bucket_id = 'player-photos');
drop policy if exists "player photos upload" on storage.objects;
create policy "player photos upload" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'player-photos');
