-- Run after 05_phase3.sql. Safe to run more than once.
alter table tournaments add column if not exists views int default 0;
alter table tournaments add column if not exists youtube_url text;
alter table tournaments add column if not exists live_theme text default 'classic';
alter table tournaments add column if not exists reg_open boolean default true;
alter table sponsors add column if not exists kind text default 'Sponsor';
alter table sponsors add column if not exists amount int default 0;

create or replace function add_view(p_tournament uuid) returns void
language sql security definer set search_path = public as $$
  update tournaments set views = coalesce(views, 0) + 1 where id = p_tournament $$;

-- Block self-registration while registration is closed.
create or replace function check_reg_open() returns trigger
language plpgsql as $$
begin
  if new.source = 'link' and exists (select 1 from tournaments where id = new.tournament_id and reg_open = false) then
    raise exception 'Registration is closed';
  end if;
  return new;
end $$;
drop trigger if exists trg_reg_open on players;
create trigger trg_reg_open before insert on players for each row execute function check_reg_open();

-- Account deletion (needed for Play Store). Removes the user's auctions and data.
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
