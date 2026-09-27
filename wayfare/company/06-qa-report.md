# Wayfare QA Report (v1, pre-first-build)

Owner: QA & Release Lead. Scope: every Swift file in `ios/Wayfare` and `ios/WayfareTests` (63 app files + 5 test files),
`ios/project.yml`, `docs/api-contract.md`, and all of `backend/src`.
Date: 2026-09-27.

## 1. Verdict

**Ready for the first Xcode build, with medium confidence.** There is still no Swift compiler in this sandbox (the
swift.org and apt toolchain downloads are blocked by the proxy), so this is a careful manual type check, not a real
compile. The code is unusually consistent. I cross-checked every member access on the shared services (`store`, `sync`,
`session`, `router`, `permission`, `devices`, `toasts`, `network`, `api`, `scheduler`) against its declaration, every
`TimeFormat.*` call, every memberwise initializer's argument order, and every environment object against
`withServices`. Every one matched.

- **1 definite compile error fixed.** It would have broken the test target.
- **4 conservative hardening edits** on the constructs that were most likely to be rejected (see §2).
- **Contract:** iOS and backend match on every endpoint. No backend change was needed, and `npm test` passes
  (103/103).
- **4 logic/release fixes:** a sign-out reminder race, a more reliable sign-out wipe, the privacy manifest, and a
  DEBUG-only briefing hour picker for testing.

Expect the first build to show somewhere between zero and a handful of errors. If one file shows many errors, fix the
first one and rebuild (see §5, risk 1, for where to look).

## 2. Compile fixes (file:line → reason)

| # | Kind | File:line | Change | Reason |
|---|---|---|---|---|
| 1 | **Definite** | `ios/Wayfare/Notifications/DeviceRegistrar.swift:45` | `static func hexString` → `nonisolated static func hexString` | `DeviceRegistrar` is `@MainActor`, and `DTOCodingTests.testDeviceTokenHex` (nonisolated XCTest method) calls it synchronously. That is an error even in Swift 5 mode ("call to main actor-isolated static method in a synchronous nonisolated context"). The function is pure, so `nonisolated` is correct. |
| 2 | Hardening | `ios/Wayfare/Features/DayMap/DayMapView.swift:42-61` | `ForEach { if let … else … }` split into two `ForEach`es (numbered / symbol pins). The route `let` moved out of the `Map` builder. | This was risky spot #1 in the iOS notes. The `MapContentBuilder` content now uses only plain `if` and `ForEach`, which is the most widely used form. The behavior is identical. |
| 3 | Hardening | `ios/Wayfare/Features/Trips/TripsListView.swift:330` | Added `@ViewBuilder` to `SearchableIfNeeded.body(content:)` | The `if/else` returns two different view types. `@ViewBuilder` inference from `ViewModifier` is fine on current SDKs, and the explicit attribute removes any doubt. |
| 4 | Hardening | `ios/Wayfare/Features/ItemEditor/ItemFormView.swift:137,173` | Property `toolbar` renamed to `toolbarItems` | A bare `toolbar` inside `.toolbar { … }` competes with SwiftUI's `View.toolbar(…)` overloads during name lookup. The rename removes the ambiguity. |
| 5 | Hardening | `ios/Wayfare/Features/TripDetail/TripDetailView.swift:141,199` | Method `toolbar(_:role:)` renamed to `toolbarItems(_:role:)` | Same reason as #4. |

**Reviewed and left as they are** (all use real iOS 17 APIs with correct labels): `credentialState(forUserID:)` (the
async form of `getCredentialState`), the `nonisolated` UN delegate methods in `AppDelegate`,
`MainActor.assumeIsolated` in `LocationSearchModel`, `navigationDestination(item:)`, `PasteButton(payloadType:)`,
`searchable(text:isPresented:placement:prompt:)`, `MapPolyline.stroke(_:style:)`, `sensoryFeedback(_:trigger:condition:)`,
`confirmationDialog(…presenting:…)`, `ContentUnavailableView`, `@Bindable var router = router` in `body`, the
`[String: String]` stored in `@Model Item`, and `if case` inside builders. None of the `@Model` classes use
relationships or enums (kinds and roles are stored as raw `String`s), so the "relationships need their inverse declared"
and "enums need to be Codable" rules don't apply. `project.yml` is valid: the sources paths, the generated Info.plist,
the entitlements path and properties, and the test host (set automatically because the test target depends on the app)
are all correct. `SWIFT_VERSION: 5.0` and `SWIFT_STRICT_CONCURRENCY: minimal` mean Sendable problems show up as
warnings, not errors.

If `MapPolyline(...).stroke(_:style:)` is still rejected, replace it with `.stroke(Palette.accent.opacity(0.6), lineWidth: 3)`
(you lose the dash).

## 3. Contract conformance (iOS ↔ backend ↔ `docs/api-contract.md`)

Checked for each endpoint: path, method, request field names, optional fields, date formats, status codes, handling of
204 empty bodies, and the error shape.

| Endpoint | iOS | Backend | Status | Notes |
|---|---|---|---|---|
| `GET /v1/health` | `APIClient.health` (DEBUG Developer section) | `{ok, version:"1"}` | ✅ | `HealthDTO` accepts `version` as a string or an int. |
| `POST /v1/auth/apple` | `AppleAuthRequest` sends `identityToken`, `authorizationCode`, `displayName`, with explicit `null`s | Accepts `null` or a string for the code and the name; exchanges the code in `waitUntil` | ✅ | The code is UTF-8 decoded from `credential.authorizationCode`. The name is sent only when Apple provides it. |
| `GET /v1/me` | `UserDTO` (email optional) | `email: … \|\| null` | ✅ | |
| `PATCH /v1/me` | `{displayName}`, 1–40 characters | 1–100 characters, trimmed | ✅ | |
| `DELETE /v1/me` | `perform` ignores the body on 204 | 204, revokes the Apple token first | ✅ | The local wipe happens only after 204. Revocation needs the `APPLE_SIWA_*` secrets (see the release checklist). |
| `POST /v1/auth/logout` | Sends `{apnsToken}` only when a token exists, otherwise no body | Parses an empty or missing body safely. Deletes the device only when the token belongs to the caller. | ✅ | Token hex is lowercase on both sides. |
| `PUT /v1/devices/current` | `DeviceRegistrationDTO` (6 fields), `sandbox` in DEBUG, `production` otherwise | Validates `^[0-9a-f]{64,200}$`, hour 0–23 | ✅ | See risk 5 (Release build run from Xcode). |
| `GET /v1/sync?since=` | Cursor in `UserDefaults`, idempotent upserts keyed by lowercased id, tombstones | 5 s overlap. Removed trips come back as tombstones along with your own member tombstone. | ✅ | `details` values are always strings (enforced by `validateDetails`), so the strict `[String:String]` decode is safe. Instants have no fractional seconds (they are stored as validated strings). |
| `PUT /v1/trips/:id` | `TripWriteDTO` (8 writable fields), color uppercased | Full replace. 403 viewer/non-member, 409 deleted | ✅ | 403/409 are permanent rejections: the client does a full resync and shows a toast. |
| `DELETE /v1/trips/:id` | Owner only | 204, idempotent. 404 unknown | ✅ | The client treats 404 as success. |
| `PUT /v1/trips/:t/items/:i` | `ItemWriteDTO` (18 fields, explicit `null`s, whole-second UTC instants) | Body `id`/`tripId` must match the URL (lowercase normalized). `endAt ≥ startAt` | ✅ | All-day end is stored at local midnight and is ≥ start, so the server accepts it. Collaborator push is sent from `waitUntil`. |
| `DELETE /v1/trips/:t/items/:i` | Sent for rows the server has acknowledged. 404 counts as success | 204, idempotent | ✅ | Items that never synced (`updatedAt == 0`) are deleted locally without a request. |
| `POST /v1/trips/:t/invites` | `{role}`, owner/editor UI only | 403 for viewers. Returns `{code,url,expiresAt}` | ✅ | `expiresAt` has no fractional seconds (`isoInstant`). The client would accept them anyway. |
| `POST /v1/invites/:code/accept` | Path-escaped code, no body. 404 → "expired" state | Case, space and hyphen insensitive. Idempotent | ✅ | Deep-link codes pass through unchanged and the server uppercases them. |
| `DELETE /v1/trips/:t/members/:u` | Owner removes others. Members leave with their own id | Owner can't leave (403). The client sends `DELETE /trips/:id` for owners instead | ✅ | |
| `POST /v1/trips/:t/import` | `{text}` ≤ 20,000 characters. 45 s timeout. Handles 429, 403, and other errors | `claude-sonnet-5`, adaptive thinking, `output_config.format` json_schema. Drafts are sanitized. 30/day | ⚠️ | The request shape is valid for the current Messages API. **Timeout mismatch:** the server allows 90 s but the app gives up after 45 s. See risk 4. |
| Error body | `APIErrorBody {error:{code,message}}`, with a synthesized fallback | `errorResponse` | ✅ | |
| IDs | `UUID().uuidString.lowercased()`. Every DTO decoder and model init lowercases | `normalizeUuid` lowercases | ✅ | The `SyncApplyTests` uppercase-id test covers this. |
| Push `itemChanged` | `NotificationPayload` reads `type`, `tripId`, `itemId` (lowercased). Background sync via `didReceiveRemoteNotification` | Custom keys `type/tripId/itemId`. `content-available: 1` is now in `buildPayload` | ✅ | iOS notes §7.1 is already fixed on the backend. A tap opens the trip, syncs, then pushes the item. |
| Push `briefing` | `type/tripId/date` → opens the trip and scrolls to `date` | `{type:"briefing", tripId, date}` | ✅ | |

## 4. Logic fixes

| File:line | Fix | Why |
|---|---|---|
| `ios/Wayfare/Notifications/NotificationScheduler.swift:21,59-80,86` | Added a `generation` counter, bumped by `cancelAll()`. A reschedule pass started before sign-out stops before it adds requests. | **Sign-out race:** `performReschedule` awaits `notificationSettings()` and `pendingNotificationRequests()`. If the user signed out during those awaits, the pass would re-add the previous account's reminders *after* `cancelAll()`. |
| `ios/Wayfare/Sync/TripStore.swift:206` | `wipeAll()` fetches and deletes each row instead of calling the batch `context.delete(model:)`. | A batch delete bypasses objects already registered in the main context, so `@Query` lists could keep showing the old account's trips after sign-out or account deletion until the next launch. The data sets are small, so this is cheap. |
| `ios/Wayfare/Notifications/DeviceRegistrar.swift:26-32` | DEBUG builds offer briefing hours 0–23 (Release keeps 5–11 AM). | Lets you force the daily briefing during testing (test plan step 30). The server already accepts 0–23. |
| `ios/Wayfare/Resources/PrivacyInfo.xcprivacy` (new) | Privacy manifest: UserDefaults required-reason API `CA92.1`, no tracking, and the collected data types. | App Store Connect flags uploads that use required-reason APIs without a manifest. The data types match the nutrition labels in `07-release-checklist.md`. |

**Reviewed and found correct** (no change):
- **Time-zone day grouping:** grouping uses the trip zone, all-day items keep their own local date, sections use UTC
  calendar arithmetic (safe across DST), and "Today" and Now/Next use real instants. The JFK 22:30 EDT → LIS flight groups
  under the next Lisbon day with an "Oct 1 · EDT" badge and "+1", as UX spec 5.1 requires.
- **Reminders:** only future reminders within 60 days, capped at the 60 soonest with stable tie-breaks. Triggers use
  explicit UTC components. Stale `item-*` requests are removed. Viewers get editors' reminders (UX 5.3, v1 decision).
- **Sync:** dirty rows are never overwritten by incoming rows. A mid-flight edit keeps `needsPush` (the `localRevision`
  check). Pushes go trips first, so offline-created trips and their items work. Permanent rejections trigger a full
  resync and a toast. The cursor is stored only after a successful apply, and `reset()` clears it on sign-out. The
  sign-out order (logout with APNs token → wipe → Keychain) is correct.
- **Viewer read-only UI:** the "+" menu, Edit, swipe and context actions, "Add" on empty days, AI import, invite section,
  Edit Trip and Add notes are all hidden when `role.canEdit` is false. Leave Trip, Directions, Copy Code and Copy Details
  stay available, and the "View only" pill with its popover is shown.

## 5. Remaining risks (ranked)

1. **The app has never been compiled** (likelihood: medium, impact: blocks everything). Look first at:
   `DayMapView` (`MapPolyline.stroke(_:style:)`), `LocationSearch.swift` (`@Observable` on an `NSObject` delegate; the
   fallback is `ObservableObject` + `@StateObject`), `SessionStore.checkAppleCredentialState` (the fallback is to wrap
   `getCredentialState` in `withCheckedThrowingContinuation`), and `ImportView` (`PasteButton`). Sendable warnings are
   expected; ignore them in Swift 5 mode.
2. **No app icon** (certain, blocks upload). `AppIcon.appiconset` has an empty 1024 slot. Debug builds run; archive
   validation fails.
3. **Placeholder legal URLs** (certain, blocks review). `AppConfig` points at `https://wayfare.app/privacy`, `/terms` and
   `mailto:support@wayfare.app`. These pages and the mailbox must exist, or the URLs must be changed before submission.
4. **AI import timeout mismatch** (likely on long emails). The app times out at 45 s (per the UX spec), but the Worker
   waits up to 90 s for Claude with adaptive thinking. On a big confirmation email the user sees "Import didn't finish"
   while the server completes and counts the import against the 30/day limit. Recommendation (a product decision): raise
   the `importDrafts` timeout to 90 s, or lower `output_config.effort` to `low` on the server.
5. **APNs environment mismatch.** The app reports `sandbox` only in DEBUG. A **Release** build run from Xcode (with a
   development-signed `aps-environment`) registers as `production`. APNs then answers `BadDeviceToken`, and the server
   deletes that device row. Result: no pushes until the next device upload. Always test pushes with the Debug scheme or
   with TestFlight.
6. **The Sign in with Apple token exchange depends on secrets.** Without `APPLE_SIWA_KEY_ID`, `APPLE_TEAM_ID` and
   `APPLE_SIWA_PRIVATE_KEY`, sign-in still works but no refresh token is stored, so account deletion can't revoke the
   Apple token. That is a review risk under 5.1.1(v) and Apple's revocation requirement.
7. **Title length units.** The client limits titles by grapheme count (200), but the server counts UTF-16 units (200).
   An emoji-heavy title could get a 400. A never-synced item would then be dropped with a "can no longer edit that trip"
   toast, which is the wrong reason. This is rare.
8. **SwiftData runtime behavior.** `@Attribute(.unique)` together with the in-code upsert is fine, and the
   `[String:String]` attribute should work. If `details` misbehaves at runtime, store it as `Data` (iOS notes §6.7).
9. **Invite links use only the `wayfare://` scheme.** Some messaging apps don't make custom schemes tappable. The share
   message also contains the 8-character code, and Join with Code works.
10. **A just-joined trip shows the viewer UI for a moment** until the first sync delivers the member rows (the role
    falls back to viewer). This corrects itself within seconds.
11. **`SyncEngine.reset()` race.** A cancelled sync can clear `runningTask` after a new sync has started, which allows
    one duplicate (idempotent) pass. This is harmless.

## 6. Manual test plan: first device session

**Setup:** The backend is deployed with all secrets (see `07-release-checklist.md` §3). `Config.xcconfig` has the real
`API_BASE_URL` and your team ID. Use the **Debug** scheme. You need **Device A** (your iPhone, Apple ID #1) and
**Device B** (a second iPhone, Apple ID #2; a Simulator signed in to Apple ID #2 works for everything except pushes).
Both devices' Settings → General → Date & Time should be automatic. Device A's time zone should be New York for the
time-zone steps (Settings → General → Date & Time → turn off automatic → New York), or just note your own zone.

### Sign-in and first launch
1. [ ] Run on A. The Welcome screen appears. There is **no** notification prompt at launch.
2. [ ] Tap Sign in with Apple, choose "Hide My Email", and continue. The name capture screen appears if Apple sent no
   name. Enter "Nick" → Continue. The empty Trips list shows "No trips yet".
3. [ ] Settings (avatar): the name is Nick, the email reads "Hidden by Apple", and Last synced is "just now".

### A trip with every item kind
4. [ ] + → New Trip: "Lisbon & Porto", Destination search "Lisbon" → pick it. The time zone becomes Europe/Lisbon and
   the cover becomes 🇵🇹. Dates **Oct 1 – Oct 9, 2026**. Create.
5. [ ] The priming card appears ("Get a heads-up…") → Turn On Notifications → Allow. (In the Xcode console, APNs
   registration should not report errors.)
6. [ ] + → Flight. Flight number TP202, From JFK, To LIS, Seat 14A. Departs **Oct 1, 22:30**, departure time zone
   **America/New_York**. Add arrival time **Oct 2, 09:45**, arrival time zone **Europe/Lisbon**. Confirmation ABC123,
   reminder 3 hours. Add.
7. [ ] The flight appears under **Fri, Oct 2 · Day 2** (not Oct 1). The time column shows 22:30 with the badge
   "Oct 1 · EDT" and the end time "09:45 +1". Item Detail shows "JFK → LIS", a duration of 6 h 15 min, and "+1" on the arrival.
8. [ ] + → Lodging: "Memmo Alfama", location search "Memmo Alfama Lisbon". Check-in Oct 2 15:00, check-out Oct 6 11:00.
   The timeline shows check-in on Oct 2 ("Check-in · 4 nights"), "Staying at … Night 2 of 4" bands on Oct 3–5, and
   Check-out on Oct 6.
9. [ ] + → Food: "Dinner at Taberna", Oct 3 20:30, party size 2, reminder 1 hour. + → Activity: "Tram 28 tour",
   Oct 4 10:00. + → Transport: mode Train, "Lisboa Santa Apolónia → Porto Campanhã", Oct 6 13:09–16:05. + → Note:
   "Pick up SIM card", all day on Oct 2.
10. [ ] Order within Oct 2: the all-day note comes before the timed rows, and the flight and check-in are in time
    order. On Oct 3: the staying band comes first, then dinner. Pull to refresh. The unsynced markers disappear.
11. [ ] The Map tab: day chips; Oct 3 shows a numbered pin, Directions opens Apple Maps. "All" shows kind symbols.
12. [ ] Info tab: the Summary counts ("1 flight, 1 stay…"). Tap "1 meal" to filter the timeline, then clear the chip.

### Time zones (the JFK → LIS midnight flight)
13. [ ] Change Device A's time zone to Europe/Lisbon (Settings → General → Date & Time) and return to the app. The flight
    still groups under Oct 2 (the trip zone governs grouping) and still shows 22:30 with the EDT badge. Nothing moves.
14. [ ] Edit the flight and change the departure time zone to Europe/London. The wall clock stays at 22:30 (the instant
    moves), and the row regroups. Cancel → Discard.

### Offline edits, then reconnect
15. [ ] Turn on Airplane Mode. After about 2 s, the "Offline" banner appears on the Trips list and in the trip.
16. [ ] Offline: edit Dinner to 21:00, delete Tram 28, and add a Note "Buy Lisboa Card" (Oct 4). Each shows the sync
    marker. Create a whole new trip "Offline test" with one activity.
17. [ ] Settings → Sync shows "N changes waiting to sync". Sign Out warns that changes will be lost. **Cancel.**
18. [ ] Turn off Airplane Mode. Within a few seconds the markers clear and the banner goes away. Pull to refresh on
    Device A. Everything is still there, and Tram 28 is gone.

### Reminders
19. [ ] Add an Activity starting **6 minutes from now** with a 5-minute reminder. Lock the phone. The reminder fires
    about 1 minute later with the body "Starts at HH:MM…". Tap it and the app opens that item.
20. [ ] Long-press a reminder for an item that has a confirmation code (make one 2 minutes out): "Copy Code" copies it
    and shows a toast. "Directions" opens Maps.

### Sharing between two Apple IDs
21. [ ] A: Trip → Share (person icon) → Can edit → Create Invite Link → Share Invite… → send it to yourself (Notes or
    iMessage) and copy the code.
22. [ ] B: install, sign in with Apple ID #2, name "Sam". + → Join with Code → enter the code (try lowercase with a
    hyphen, e.g. `ab12-cd34`). You see "You're in!" → Open Trip. Items and members appear after about a second.
    Allow notifications on the priming card.
23. [ ] A: the Share sheet shows 2 people (Nick – Owner, Sam – Editor). The trip row shows the shared icon.
24. [ ] A: create a second invite as **View only** and join it from B for a second trip. On B, that trip shows the
    "View only" pill. There is no + button, no swipe actions, no Edit, and Add is hidden on empty days. Leave Trip
    still works.

### Collaborator push
25. [ ] B: in "Lisbon & Porto", add Food "Pastéis at Manteigaria". Within seconds A (locked) gets a push titled
    "Lisbon & Porto" with the body "Sam added “Pastéis at Manteigaria” to Lisbon & Porto". Tap it and A opens that
    item.
26. [ ] B: edit that item twice within 2 minutes. A gets **no** second push (coalescing). With A in the foreground a
    quiet banner shows and the timeline updates on its own.
27. [ ] A: Settings → turn off "Plan changes by others". B edits again after 2 minutes. A gets nothing.

### Daily briefing
28. [ ] Make sure a trip is **in progress today** in its own zone. Edit "Lisbon & Porto" dates to include today, or
    create "Briefing test" (today → today + 2) with one timed item today.
29. [ ] A (Debug build): Settings → Morning briefing ON → Briefing time = the **next** hour (the DEBUG build offers all
    24 hours). The device uploads the setting within about 1 s (it needs a connection).
30. [ ] Wait for the top of the hour (the cron is `0 * * * *`). A gets "Today in Portugal" with the body "N plans ·
    first: … at HH:MM". Tap it and the trip opens scrolled to today.
    - **Force it immediately instead:** set the briefing hour to the **current** hour, then trigger the cron by hand:
      `cd backend && npx wrangler dev --remote --test-scheduled`, then in another terminal
      `curl "http://localhost:8787/__scheduled?cron=0+*+*+*+*"` (this needs the APNs secrets in `.dev.vars`).
    - **To re-send the same day:** `npx wrangler d1 execute wayfare --remote --command "UPDATE devices SET last_briefing_date = NULL"`.

### AI import (paste the sample email below)
31. [ ] A: in "Lisbon & Porto" → + → Import from Email… The consent screen appears once ("Pasted text is sent to
    Anthropic…") → Agree & Continue.
32. [ ] Paste the sample email → Find Plans. Within about 45 s you see a review list: the flight TP 202 (22:30 EDT → Oct 2
    09:45 WEST), the hotel (Oct 2–6), and dinner Oct 3 20:30. The flight should be marked "Possible duplicate" and
    unchecked, because ABC123 already exists.
33. [ ] Tap the hotel draft, change the room type, tap Done, then Add 2 Plans. A toast appears, the timeline scrolls to
    the earliest new plan, and the plans sync.
34. [ ] Settings → About → AI Import Consent → Withdraw. The next import shows the consent screen again.

### Sign out and account deletion
35. [ ] B: Settings → Sign Out. The Welcome screen appears, there are no trips on B, and no reminders are pending. On A,
    edit an item in the shared trip: **B gets no push** (the device was unregistered on logout).
36. [ ] B: sign in again as Sam. The trips come back from the server.
37. [ ] A: Settings → Delete Account. The page lists "Lisbon & Porto (2 people)" as deleted for everyone. Offline, the
    button is disabled with an explanation. Online → Delete → confirm. A returns to Welcome with no data.
38. [ ] B: pull to refresh. "Lisbon & Porto" disappears (the owner deleted their account and the trip comes back as a
    tombstone). If it was open, B gets "… is no longer available."
39. [ ] A: sign in with Apple ID #1 again. You get a **fresh empty account**, and iOS Settings → Apple ID → Sign-In &
    Security → Sign in with Apple no longer lists Wayfare before this sign-in (confirming the token was revoked).

### Sample confirmation email for step 32

```
From: TAP Air Portugal <noreply@flytap.com>
Subject: Your booking confirmation – ABC123

Dear Mr Nick Traveler,

Thank you for choosing TAP Air Portugal. Your booking is confirmed.

Booking reference: ABC123

OUTBOUND
Thu 01 Oct 2026   TP 202   New York (JFK) Terminal 1  22:30  ->  Lisbon (LIS) Terminal 1  09:45 (+1)
Economy Classic · Seat 14A · Operated by TAP Air Portugal

Passenger: NICK TRAVELER   E-ticket: 047 2345678901

---------------------------------------------------------------
Booking.com – Reservation confirmed
Memmo Alfama Hotel, Travessa das Merceeiras 27, 1100-348 Lisboa, Portugal
Phone: +351 21 049 5660
Check-in:  Friday 2 October 2026 (from 15:00)
Check-out: Tuesday 6 October 2026 (until 11:00)
Deluxe Double Room, river view · 4 nights
Confirmation number: 4417.228.901   PIN: 7731

---------------------------------------------------------------
TheFork: Your table is booked!
Taberna da Rua das Flores, Rua das Flores 103, Lisboa
Saturday 3 October 2026 at 20:30 · 2 people
Reservation ID: TF-88213
```

Expected drafts: a flight with startAt `2026-10-02T02:30:00Z` (America/New_York) and endAt `2026-10-02T08:45:00Z`
(Europe/Lisbon, UTC+1 in October); lodging `2026-10-02T14:00:00Z` → `2026-10-06T10:00:00Z` with code 4417.228.901; food
`2026-10-03T19:30:00Z`, party size 2. If the times in any draft are off by an hour, the model got a zone conversion
wrong. Report it with the draft JSON.
