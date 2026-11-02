# BidLeague Online (Flutter + Supabase), Phase 1

## 1. Backend (once)
1. Create a free project at supabase.com.
2. SQL editor: run the schema, step_for() and place_bid() from the BidLeague doc, THEN sql/02_functions_and_rls.sql.
3. Authentication > Providers > Email: switch "Confirm email" OFF while testing.
4. Project Settings > API: copy the Project URL and the anon public key.

## 2. App
  flutter create --org com.yourname --project-name bidleague_online .
  (delete test/widget_test.dart)
  flutter pub get
  dart run flutter_launcher_icons
  flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=your_anon_key

## Works in Phase 1
Email login, create auction (auto join code), teams, players, live auction console (pick player, BID for a team with tiered
increments, edit live price, sold, unsold, re-auction), purse safety and squad reserve (server side), realtime public live
view by auction code on any phone.

## Not built yet (next phases, in this order)
2: captain login + captain-only bid panel, undo last sale, bid timer + auto-sold, rename team/player live, bid history.
3: player self-registration link + approval, bulk teams (Excel), photos, Excel/PDF export.
4: overlays (5 themes) for OBS/YouTube, squad poster, sponsors, hammer animation + own sounds.
5: UPI/Razorpay payment + gating the Rs 2499 plan (NOT gated yet: anyone can create auctions), Google sign-in,
   Play Billing, push notifications, WhatsApp messages, Marathi/Hindi, auctioneer directory, white-label.

## Before Play Store
Pick your own package id and keystore. Gate auctions behind payment. Hide players.phone before collecting phones.

## Phase 2 additions
- Captain: Teams tab > tap a team > "Set captain (by email)" (captain must sign up first). Captain logs in, taps the cricket icon
  (Captain panel), opens their team and gets a BID button for their own team only (server checks this too).
- Undo last sale, bid history for the current player, rename teams/players (tap row), countdown after every bid,
  optional auto-sold (organizer's console must stay open; it uses the device clock).
- Run sql/03_phase2.sql in Supabase.
