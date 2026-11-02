-- Run after 03_phase2.sql
create function create_auction(p_name text, p_starts timestamptz, p_purse int, p_min_bid int, p_step int)
returns uuid language plpgsql security definer set search_path = public as $$
declare tid uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  insert into tournaments (owner_id, name, join_code, starts_at)
    values (auth.uid(), p_name, upper(substr(md5(random()::text), 1, 6)), p_starts) returning id into tid;
  insert into auction_rules (tournament_id, team_purse, base_price, min_bid, increment_tiers)
    values (tid, p_purse, p_min_bid, p_min_bid,
            jsonb_build_array(jsonb_build_object('min', 0, 'step', p_step)));
  insert into auction_state (tournament_id) values (tid);
  return tid;
end $$;
