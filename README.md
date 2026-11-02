# AuctionX Online (Flutter + Supabase), Phase 1

## 1. Backend (once)
1. Create a free project at supabase.com.
2. SQL editor: run the schema, step_for() and place_bid() from the AuctionX doc, THEN sql/02_functions_and_rls.sql.
3. Authentication > Providers > Email: switch "Confirm email" OFF while testing.
4. Project Settings > API: copy the Project URL and the anon public key.

## 2. App
  flutter create --org com.yourname --project-name auctionx .
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

## AuctionX UI (v3)
Home (today's auctions, Create Auction, View Auction by code, Captain panel), My Auction, Bookmarks, Auctioneer (placeholder), Profile.
Run sql/04_create_auction.sql in Supabase. App label on the phone: edit android/app/src/main/AndroidManifest.xml (android:label=\"AuctionX\").

## Phase 3
- Players: tap "Add players" and paste many lines ("Name, role, base price"). Teams: paste many names, one per line.
- Registration: someone opens View Auction (code) > person+ icon > fills form. Entry is PENDING until the organizer taps the player > Approve.
  Registration needs a login for now; a fully open link comes when the web build is hosted.
- Photos: tap the photo circle when registering, or player > Set photo. Shown on the live player card.
- Export: download icon in the auction screen > Excel (summary + one sheet per team + unsold) or PDF (Latin text only).
- Run sql/05_phase3.sql in Supabase. Phone numbers are stored in a private table (player_contacts), readable only by the organizer.
  (The organizer-facing contacts screen is not built yet.)

## Phase 4 (auction detail page)
Open an auction: header (banner, code, date, points/team, views) + tabs TEAMS, PLAYERS, MVP, SPONSORS, LINK, CONFIGURATION, ABOUT,
and a VIEW AUCTION button (live console for the organizer, live view for everyone else). Right-side menu: Create Auction, My Auction,
My Bookmark, Pricing, Auctioneers, Join as player, View Auction, About Us, Tutorial Videos, Policies, Support, Delete Account, Logout.
- MVP = the 10 most expensive sold players.
- LINK > Live view opens the projector display (full width, uses the live screen theme chosen in CONFIGURATION).
- Web links (copy/share) need the web build hosted; put its address in kWebBase (lib/config.dart). OBS overlay pages come with that step.
- Run sql/06_phase4.sql. Replace the placeholder text for Policies and the support email (kSupportEmail).

## Login + splash (v5)
- Splash screen, then a login page: email/password (show/hide, forgot password), Continue with Google, and "Player or viewer?" (open any auction by code
  without an account, watch live, register as a player).
- Google sign-in setup: Google Cloud Console > Credentials > OAuth client ID (Web) with redirect URI https://<project>.supabase.co/auth/v1/callback;
  paste Client ID + Secret in Supabase > Authentication > Sign In / Providers > Google; add http://localhost:*/** (and your hosted web URL)
  in Authentication > URL Configuration > Redirect URLs. Android APK needs an extra deep-link setup, done at the APK step.

## Offline + speed (v6)
- Teams, players, rules, auction lists and the auction header are saved on the device after every successful load. With no internet the app shows
  the saved copy and a banner. Bidding, sold/unsold and registration need internet (they show a clear message instead of failing silently).
- Live bidding no longer reloads everything on every bid; it reloads only when the player changes or after sold/unsold.
- The web build also caches the app files (service worker), so repeat visits open fast.

## Host on Vercel (free)
1. Install Node.js, then once: npm i -g vercel   and   vercel login
2. Run deploy.bat (builds web, copies web_deploy/vercel.json, runs vercel deploy --prod). First time answer the prompts: framework Other, output directory .
3. Copy the https://....vercel.app address: put it in lib/config.dart as kWebBase, add it to Supabase Authentication > URL Configuration > Redirect URLs,
   and to Google Cloud OAuth client > Authorized JavaScript origins. Rebuild and deploy again.
4. Links then work: <site>/#/view/CODE (projector), <site>/#/register/CODE (player form), <site>/#/manage/CODE (organizer).
5. Edit web/index.html <title> and web/manifest.json name to AuctionX; run dart run flutter_launcher_icons to refresh web icons.

## Brand + theme (v7)
App name AuctionX, icon assets/icon.png (launcher/web icon), small in-app logo assets/logo.png, banner assets/banner.jpg (splash + login).
Premium Dark theme: background #10111D, gold #DDB65B, purple #6D42C1, white text. Colours live in lib/theme.dart (kBg, kCard, kText, kGold, kPurple).
Run: dart run flutter_launcher_icons (refreshes the app icon), then deploy.bat.

## Bid slabs (v8)
Create Auction and Configuration both have a Bid slabs editor: pick "From bid" and "Increase by" for each slab (default 0 > +10, 100 > +20, 200 > +50).
Saved in auction_rules.increment_tiers; the server uses it for every bid. Existing auctions: Configuration > Bid slabs > Save.

## v9: live page redesign + repair SQL
Run sql/07_repair_all.sql in the Bid league Supabase project (fixes missing undo/sold/unsold functions, adds sold_at, city, batting/bowling style).
Live page: stage card, bid history, team cards with purse bars, Next up / Unsold / Sold lists, animated SOLD banner. Unsold players can be put on the block again.

## v10: captain access + new Home
Captain flow: organizer shares the Captain code (Link tab) and each team's PIN (Teams tab > team > Captain access). The captain opens Join as captain,
enters the code, picks a team, enters its PIN. The team is locked to that account and the captain only sees and bids for that team.
The server (place_bid) already refuses bids from anyone except the organizer or that team's captain. Run sql/08_captain_access.sql.

## v11
Create Auction: players per team, venue, point system, remote team bidding, visibility. View Auction: code boxes. Live SOLD / UNSOLD banners with player photo,
animated bid price. Players tab: tap a photo circle to add a photo. Registration is a stand-alone page with a success screen. Run sql/09_create_extras.sql first.

## v12: animated intro + registration link
lib/splash.dart: lights on, golden hammer strike, emblem reveal (assets/emblem.png), AuctionX name shine, zoom into the app (about 2.8 s, shown once at start,
respects reduced motion, never blocks the app). Link tab now starts with a Player registration link card: copy, share, open, QR, open/closed switch.

