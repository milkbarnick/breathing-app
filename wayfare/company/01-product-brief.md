# Wayfare: Product Brief (v1)

Owner: Product Strategist · Inputs: `00-operating-model.md`, `decisions.md`, `docs/api-contract.md` (v1).
Rule for this doc: the contract defines what v1 can do. Nothing here adds endpoints or fields. Anything
the contract can't support goes on the roadmap.

## 1. Problem, and the owner as first user

A trip today lives in six places: airline apps, hotel emails, a Notes file, Google Maps pins, screenshots,
and a group chat. That's fine at a desk. It breaks down on the road:

- **No signal, no plan.** You land, roaming isn't on yet, and the hotel address is stuck in an email that won't load.
- **Wrong time zone, wrong time.** Email confirmations mix local times, UTC, and "your" time zone. A 9:45 arrival is ambiguous.
- **No "what's next".** Nothing tells you what's next or when to leave. You end up rebuilding the day in your head at every stop.
- **Retyping is where errors come from.** Copying confirmation codes, seats, and check-in times by hand is slow and error-prone.
- **Companions ask the same questions.** "What time is dinner?" gets answered over and over in chat because nobody else has the plan.

The owner is an independent traveler who takes 3–6 trips a year and builds personal apps to fit their own
habits. They are user zero. v1 succeeds when the owner deletes their Notes itinerary for the next trip
and runs the whole trip from Wayfare. Going public comes second, and it must not bend v1.

## 2. Target users

**Primary: the owner (independent planner).** Plans alone or plans for a small group. Books directly with
airlines and hotels, so the inbox is full of confirmations. Uses an iPhone on the road, often offline or on
a weak signal. Wants one authoritative plan, fast entry, and quiet, timely nudges.

**Secondary: the travel companion.** A partner, friend, or family member who receives a shared trip. They
don't plan and just need to know where to be and when. They install the app, sign in with Apple, open
an invite link, and see the trip. If they're an editor they may add a dinner. As a viewer they only read.
They are also the main way the app would grow if it goes public, so their first-run experience has to be very short.

Not targeted in v1: travel agents, large groups (10+), business travel managers, and people who plan
entirely inside one airline or OTA app.

## 3. Jobs to be done and core principles

**Jobs**
1. *When I book something*, I want it in my itinerary without retyping, so the plan is complete and correct.
2. *When I'm on the road*, I want to see what's next and how to get there, even offline.
3. *When the day starts*, I want a one-line summary of today, so I don't have to open the app to know the shape of the day.
4. *When I travel with someone*, I want them to see and edit the same plan, so we stop coordinating in chat.
5. *When I need a detail at a counter* (confirmation code, seat, address), I want it within two taps.

**Principles** (these break ties in design and engineering decisions)
- **Works in airplane mode.** Every read, create, edit, and reminder works offline. Sync catches up later (D6, D7).
- **The next thing is always one glance away.** Opening a trip in progress lands on today, scrolled to the next item.
- **Never retype a confirmation.** Paste the email, review the drafts, save. Manual entry is the fallback.
- **Times are local to where you are.** Each item shows its own time zone. Flights show departure and arrival in their own zones.
- **The user always reviews AI output.** AI drafts, the human saves. Nothing is written without review (D8).
- **Quiet by default.** One briefing a day, reminders only where set, collaborator pushes grouped together.
- **Private by design.** Apple sign-in only, no tracking, no ads, and deleting the account is easy.

## 4. MVP feature list (mapped to the contract)

| # | Feature | Contract basis |
|---|---|---|
| F1 | Trips | `Trip`, `PUT/DELETE /v1/trips/:id` |
| F2 | Day-by-day timeline, 6 item kinds | `Item.kind`, `startAt`, time-zone fields, `sortIndex` |
| F3 | Item detail | `Item` fields + `details` map |
| F4 | Per-day map | `Item.latitude/longitude/address` |
| F5 | Local reminders | `Item.reminderMinutes` (device-scheduled) |
| F6 | Daily briefing push | `PUT /v1/devices/current`, briefing push |
| F7 | Collaborator push | item upsert side effect, `itemChanged` push |
| F8 | Sharing via invite link | `/invites`, `/invites/:code/accept`, `Member.role`, `DELETE .../members/:userId` |
| F9 | AI import from pasted text | `POST /v1/trips/:id/import` |
| F10 | Sign in with Apple | `POST /v1/auth/apple`, `/v1/me`, `/v1/auth/logout` |
| F11 | Offline sync | client-generated IDs, `GET /v1/sync?since=`, tombstones, LWW |
| F12 | Account deletion | `DELETE /v1/me` |

**Acceptance criteria**

**F1 Trips.** Create, edit, and delete a trip with title, destination, dates, IANA time zone, emoji, color, and notes.
- The trip list is split into Upcoming/Now and Past, and the trip in progress is pinned to the top.
- A trip can be created offline. It appears immediately and syncs when back online (client-generated UUID).
- End date earlier than start date is blocked in the UI. Delete is owner-only and asks for confirmation. Non-owners see "Leave trip" instead.

**F2 Timeline.** The trip opens as a list of day sections from `startDate` to `endDate`. Each item has an icon for its kind: flight, lodging, activity, food, transport, note.
- Items group by the local date of `startAt` in `startTimeZone`. Within a day they sort by `startAt`, then by `sortIndex`.
- A trip in progress opens on today, scrolled to the next upcoming item. The next item is visually marked.
- Lodging also shows as a slim "Staying at X" row on every night between check-in and check-out.
- All-day items sit at the top of their day. Items outside the trip's dates appear in a "Before/After trip" section and are never hidden.
- Flights show departure and arrival in their own zones (e.g. "22:30 EDT → 09:45 WEST +1").

**F3 Item detail.** Shows every populated field. Confirmation code, seat, and address are tap-to-copy. The address opens in Apple Maps, and the phone number starts a call.
- The edit form adapts to the kind and uses the suggested `details` keys for it. Unknown keys still display.
- Viewers see no edit controls.

**F4 Per-day map.** A MapKit view of the selected day's items that have coordinates, numbered in timeline order.
- Items that have an address but no coordinates are geocoded on the device when saved. Items that can't be geocoded are listed under the map as "not on map".
- Map tiles need a connection. Offline, the screen falls back to the ordered list with addresses and doesn't show an empty map.

**F5 Local reminders.** A per-item reminder with presets (none, 15m, 1h, 3h, 1 day). Flights default to 3h and everything else to none.
- It fires in airplane mode. Changing or deleting the item (locally or through sync) reschedules or cancels it.
- Reminders are rescheduled after sync for items edited by collaborators.
- iOS limits an app to 64 pending notifications, so the app schedules the soonest 64.

**F6 Daily briefing.** An opt-in morning push at the chosen hour (default 7) on each day of a trip in progress: "Today in Lisbon · 3 plans · first: Breakfast at 8:30".
- It uses the device's time zone for the hour and the trip's time zone for "today". Tapping it opens that trip on that date.
- Settings has a toggle and an hour picker that sync through `PUT /v1/devices/current`.

**F7 Collaborator push.** When another member adds or edits an item, the other members get "Sam added 'Dinner at Taberna' to Lisbon & Porto". Tapping it opens the item.
- It can be turned off in Settings (`collabAlertsEnabled`). Pushes are grouped to at most 1 per trip per person every 2 minutes. You never get a push for your own edit.

**F8 Sharing.** An owner or editor generates an invite link for either the Editor or Viewer role and shares it through the iOS share sheet. The link expires after 7 days.
- Accepting the link is idempotent. The trip appears after the next sync. An expired or unknown code shows a clear "Ask for a new link" state.
- The members list shows each person's name and role. The owner can remove anyone, and any member can leave.
- Removed members lose the trip on their next sync (tombstone).
- Known limitation: the `wayfare://` link only works for people who already have the app installed. The share message includes a line saying the app is needed.

**F9 AI import.** From a trip, choose "Import", paste text (up to 20,000 chars), get draft items, then review, edit, deselect, and save.
- Nothing is saved until the user confirms. Accepted drafts are PUT as normal items with new IDs.
- A flight confirmation produces a flight with correct airline, number, codes, local times, and confirmation code. A hotel email produces lodging with check-in and check-out.
- Import needs a connection. Offline, the button explains that. The 429 error message reads "Daily import limit reached".
- Garbage input returns zero drafts with a helpful message. It never crashes and never produces a partial save.

**F10 Sign in with Apple.** It's the only way in. The first launch gets the user to a signed-in, empty state within 2 taps.
- The name is captured on first sign-in and can be edited in Settings. Sign out revokes the session and clears local data.

**F11 Offline sync.** Every screen works offline. Local writes queue up and sync when back online, and pull-to-refresh syncs too.
- It syncs by delta cursor, applies tombstones, and resolves conflicts last-write-wins. After the owner edits on one device, a second device shows the change within one sync.
- A quiet status line reports "Synced 2 min ago" or "Offline, changes saved". No blocking spinners.

**F12 Account deletion.** In Settings under Account, "Delete account" requires a destructive confirmation, then calls `DELETE /v1/me`, wipes local data, and returns to sign-in.
- Shared trips the user owns disappear for their members. The confirmation text says so explicitly.

## 5. Out of scope for v1, and roadmap

**Explicitly out of v1:** packing lists, expenses, document vault, widgets / Live Activities, live flight status,
calendar export, Wallet pass import, Share Extension, email-forwarding import, universal links, offline map tiles,
in-app purchases, Android/web, iPad-optimized layout, localization beyond English, and analytics SDKs.
(Consistent with D9.)

**v1.1: remove friction from the core loop**
1. **Share Extension import (from Mail/Safari/PDF).** Pasting is the biggest remaining source of friction, and this reuses `/import` with no new backend.
2. **Home Screen widget: "Next up".** Delivers "one glance away" without opening the app. It reads local SwiftData only.
3. **Universal links for invites.** The companion's first run is the growth path, and `wayfare://` fails when the app isn't installed.
4. **Calendar export (.ics / EventKit).** Cheap to build, and it puts the plan wherever the companion already looks.

**v1.2: travel-day power**
1. **Live Activity for the next flight.** Countdown, gate, and seat on the Lock Screen. It's the flagship moment for the App Store.
2. **Flight-status tracking.** Delays and gate changes pushed to the traveler. It needs a paid data provider, which is a cost decision.
3. **Packing lists.** High demand and simple. Per-trip checklists with reusable templates.
4. **Apple Wallet pass import.** Boarding passes and bookings already sit in Wallet, so this is another "never retype" win.

**Later**
- **Expenses with currency conversion.** Useful for groups, but it's a separate product surface. Only if the owner wants group-first.
- **Document vault (passport, insurance).** High trust and security burden (encryption, backups). Wait for demand.
- **Email-forwarding address for import.** The best "never retype" experience, but it needs inbound mail infrastructure and spam handling.
- **Offline map packs / saved places.** Useful, but MapKit offline is limited. Revisit if the owner hits no-signal map pain on the road.
- **iPad and Mac (Catalyst) planning view.** Planning happens at a desk, and the app travels on the phone.

## 6. Success metrics

Two phases, measured honestly with what v1 actually records. v1 has no analytics SDK. Metrics come from D1
server data, App Store Connect / Xcode Organizer, and the owner's own judgment.

**Phase A: personal use (first 2 trips)**
- **Owner runs a full trip in Wayfare** with no separate itinerary in Notes. Binary, and it's the metric that matters.
- **Import share ≥ 60%** of flight and lodging items created through import. Proxy: accepted drafts vs. items created per trip. Precise attribution needs a client counter (v1.1).
- **Import accuracy ≥ 90%** of drafts saved without field edits (owner spot-check).
- **Crash-free sessions ≥ 99.5%** (Xcode Organizer).
- **Zero wrong-time incidents**: no item shown at the wrong local time during a trip.
- **Sync latency**: a companion sees an edit in under 1 minute when online.

**Phase B: public launch**
- **Activation:** % of new users who create a trip with at least 3 items in 24h (target 40%).
- **Import adoption:** % of active trips with at least 1 import (target 50%). Imports per active user per month, also used as a cost input.
- **Sharing:** % of trips with at least 1 accepted invite (target 25%), and invite acceptance rate (target 60%).
- **Briefing engagement:** briefing opt-in rate (target 50%) and open rate (target 30%). Tracking open rate needs a lightweight tap event, which is a v1.1 contract addition.
- **Retention:** % of users who create a second trip within 6 months (target 35%). Travel is seasonal, so weekly retention is the wrong lens.
- **Quality:** crash-free sessions ≥ 99.5% and App Store rating ≥ 4.6.
- **Unit economics:** AI cost per active user per month below 10% of revenue per user.

## 7. App Store positioning

**Name.** "Wayfare" is a working name (D1). Alternatives:
1. **Onward**: short and hopeful, but crowded, so expect conflicts.
2. **Daybound**: suggests day-by-day and is distinctive.
3. **Tripsheet**: plain and descriptive, and good for search.
4. **Itinero**: an obvious itinerary cue that reads well internationally.
5. **Nextstop**: matches "the next thing is always one glance away".

> **Must check before committing:** USPTO/EUIPO trademark search (class 9 and 39), App Store name
> availability (names are unique across the store), domain and social handles. "Wayfare" is close to
> "Wayfair" (a large retailer), which is a real confusion risk. Flag for the owner.

**Subtitle** (≤30): **"Your trip, one glance away"** (26 chars)

**Promo text** (≤170): "Paste a booking email and watch it become your itinerary. Day-by-day plans, local-time reminders,
and a morning briefing that work even in airplane mode."

**Keywords** (100 chars, no words repeated from name or subtitle):
`itinerary,travel,planner,tour,flight,hotel,organizer,offline,booking,vacation,schedule,share,journey`

**Category:** Travel (primary), Productivity (secondary).

**Pricing recommendation (public launch): freemium with an annual subscription.**
- **Free:** unlimited trips, timeline, map, reminders, briefing, sharing, and **5 AI imports per month**.
  Companions are always free, because charging the invitee kills sharing.
- **Wayfare Plus: $19.99/yr (or $2.99/mo)** for more imports (up to the contract's 30/day cap). This tier later gets
  flight status, Live Activities, and the Share Extension as the premium bundle.
- **Why not one-time:** AI import and push/cron have a cost per use and per month that recurs forever. A one-time
  price turns heavy users into a loss. **Why not all-paid:** a travel app is judged on one trip, and a paywall
  before the first trip kills trials. Each import costs on the order of a cent or a few cents, depending on the model and email length.
  The free cap bounds the exposure. Verify real per-call cost in Phase A before setting the cap.
- **Until then:** ship personal/TestFlight builds free with no IAP. IAP needs StoreKit work and a server
  entitlement check, and both are post-v1 contract additions.

**Privacy nutrition label (based on the v1 contract)**
- **Data linked to the user:**
  - *Contact Info*: name (optional, editable) and email (usually an Apple private relay address).
  - *Identifiers*: user ID.
  - *User Content*: trips, items, notes, confirmation codes, addresses, and coordinates the user enters, plus text pasted for import.
  - *Other*: device push token and device time zone.
  - Purpose for all of these is **App Functionality** only.
- **Location:** the app doesn't collect the device's location. Coordinates are user-entered place data (declare as User Content, not Location).
- **Not collected:** usage data, diagnostics (crash reports via Apple opt-in only), financial data, browsing history, and contacts.
- **Tracking: none.** No ads, no third-party SDKs, no ATT prompt.
- **Third-party processing:** pasted import text is sent to Anthropic to generate drafts. The privacy policy must state this,
  and the app must get explicit consent in the app before the first import (see Risks).

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **Guideline 4.2 (Minimum Functionality)**: reviewer sees "just a list" | Rejection | Ship with the native map, local reminders, briefing, and import. Provide a demo account with a pre-filled trip, plus review notes explaining offline-first design. |
| **Guideline 5.1.1(v) (account deletion)** | Rejection | F12 is in-app, easy to find (Settings → Account), and deletes server data. **Also revoke the Apple token** via Apple's REST revoke endpoint on deletion. This isn't in the contract yet, and the CTO should confirm it. |
| **Sign in with Apple (4.8) handling** | Rejection or broken accounts | It's the only login, so 4.8 is satisfied. Handle a missing email or name, and handle the credential-revoked state (sign out cleanly). |
| **Guideline 5.1.2: sharing personal data with third-party AI** | Rejection | A one-time consent sheet before the first import names Anthropic and what's sent. The privacy policy covers it, and the import screen has a "don't paste passwords or card numbers" hint. |
| **AI cost runaway** (abuse or heavy users) | Real money | The contract's 30/day per-user cap, the free-tier monthly cap at launch, the 20k char limit, and a cheap model for extraction. Monitor spend weekly in Phase B. |
| **AI extraction errors** (wrong date or time zone) | Missed flight | Mandatory review screen, with time zones shown on every draft. Low-confidence fields are highlighted (UX). Never auto-save. |
| **Time zones and DST** | Wrong times, the worst failure for a travel app | Store UTC plus IANA zones per item (contract). Always render in the item's zone. Test cases: red-eye across the date line, DST changeover days, trips spanning zones, and a briefing when the device zone differs from the trip zone. |
| **Invite link requires the app** (`wayfare://`) | Companion drop-off | Share message includes an App Store line. Universal links in v1.1. |
| **Last-write-wins overwrites** a companion's edit | Lost edits (rare at this group size) | Accepted for v1. Collaborator push makes changes visible. Revisit if the owner reports it. |
| **iOS 64-pending-notification cap** | Missing reminders on long trips | Schedule the nearest 64 and top up on launch/sync. |
| **Name conflict** (Wayfare vs. Wayfair) | Forced rename, legal letter | Clear the name before building any branding assets (see §7). |

## 9. Open questions for the owner

1. **Solo or group-first?** Do you mostly travel alone and share read-only, or co-plan with a partner/friends?
   Group-first moves expenses and conflict handling up the roadmap.
2. **Which pain is worst today:** getting bookings *in* (entry), finding things *on the road* (retrieval),
   or keeping companions *in sync*? That decides what v1.1 builds first.
3. **Is pasting good enough,** or do you want the Share Extension (or email forwarding) in v1? It's the biggest
   friction left in "never retype".
4. **Do you want to go public, and do you want to make money from it?** If yes, we plan for IAP and the name/trademark check
   now. If no, we skip monetization entirely and stay free/TestFlight.
5. **Is the Live Activity for the next flight a must-have for your next trip?** It's the most-requested "wow" feature and
   could be moved into v1 if you'll accept a later ship date.
6. **What does your morning look like on a trip?** Is 7:00 a single briefing right, or do you want an evening
   "tomorrow" preview instead of (or in addition to) the morning one?
7. **Do you often carry items like passports or insurance PDFs** that you'd want in the app offline, or does Files/Wallet
   already cover that? This decides whether the document vault belongs on the roadmap at all.
8. **Name:** keep "Wayfare" despite the Wayfair similarity, or pick from the shortlist in §7?
