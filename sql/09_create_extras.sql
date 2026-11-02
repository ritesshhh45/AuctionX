-- BidLeague v11. Run in the "Bid league" Supabase project (olaubcixtxsnkjiovucz) BEFORE running the new app. Safe to run again.
alter table tournaments add column if not exists point_system text default 'Points';
alter table tournaments add column if not exists remote_bidding boolean default true;
alter table tournaments add column if not exists visibility text default 'public';

-- bid check: only the organizer, or the captain of that team (and only if remote bidding is on)
drop function if exists place_bid(uuid, uuid, int);
create function place_bid(p_tournament uuid, p_team uuid, p_amount int) returns void
language plpgsql security definer set search_path = public as $$
declare s auction_state%rowtype; r auction_rules%rowtype; t teams%rowtype;
        spent int; bought int; maxbid int; expected int;
begin
  select * into s from auction_state where tournament_id = p_tournament for update;
  select * into r from auction_rules where tournament_id = p_tournament;
  select * into t from teams where id = p_team and tournament_id = p_tournament;
  if s.status::text <> 'bidding' then raise exception 'Bidding is not open'; end if;
  if t.id is null then raise exception 'Team not found'; end if;
  if not (coalesce(t.captain_user_id = auth.uid(), false) or is_owner(p_tournament)) then
    raise exception 'Not allowed to bid for this team';
  end if;
  if not is_owner(p_tournament) then
    if (select coalesce(remote_bidding, true) from tournaments where id = p_tournament) = false then
      raise exception 'Remote bidding is off for this auction. The organizer places the bids.';
    end if;
  end if;
  if s.leading_team_id = p_team then raise exception 'This team already leads the bid'; end if;

  expected := case when s.leading_team_id is null then s.current_bid
                   else s.current_bid + step_for(r.increment_tiers, s.current_bid) end;
  if p_amount <> expected then raise exception 'Next valid bid is %', expected; end if;
  if r.max_bid is not null and p_amount > r.max_bid then raise exception 'Above max bid'; end if;

  select coalesce(sum(sold_price), 0), count(*) into spent, bought
    from players where sold_team_id = p_team and auction_status::text = 'sold';
  maxbid := r.team_purse - spent
            - greatest(coalesce(r.min_squad, 11) - bought - 1, 0) * coalesce(r.reserve_per_slot, 0);
  if p_amount > maxbid then raise exception 'Not enough purse (max bid %)', maxbid; end if;
  if bought >= coalesce(r.max_squad, 99) then raise exception 'Squad is full'; end if;

  insert into bids (tournament_id, player_id, team_id, amount)
    values (p_tournament, s.current_player_id, p_team, p_amount);
  update auction_state
     set current_bid = p_amount, leading_team_id = p_team,
         timer_ends_at = now() + make_interval(secs => coalesce(r.timer_seconds, 30)),
         version = version + 1
   where tournament_id = p_tournament;
end $$;

notify pgrst, 'reload schema';
