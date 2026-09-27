# Wayfare iOS: Engineering Notes (v1)

Owner: iOS Engineer. Inputs: `docs/api-contract.md` (incl. the logout `apnsToken` change),
`company/01-product-brief.md`, `02-ux-spec.md`, `03-design-system.md`, `decisions.md`.
Code: `wayfare/ios/`. Setup, TestFlight and App Store Connect steps: `wayfare/ios/README.md`.

**Honesty note:** this was written on Linux with no Swift compiler. Every file was parsed with a
tree-sitter Swift grammar (all 63 parse cleanly), and the APIs were chosen from what I'm confident
exists in the iOS 17 SDK. That is not a type check. Expect a small number of compile errors on the first
build; section 6 lists where to look first.

---

## 1. Architecture

```
SwiftUI views ──read──▶ @Query (SwiftData, main context)      ◀── the local truth (D6)
      │
      └─write──▶ TripStore ──marks dirty──▶ SyncEngine ──▶ APIClient ──▶ Worker
                     │                          │  push dirty rows, then GET /v1/sync
                     └──▶ NotificationScheduler ◀┘  (reschedule after every save and sync)
```

- **Single source of truth is SwiftData.** Views never wait on the network. They read with `@Query`, and
  every write goes through `TripStore`, which writes locally at once, sets `needsPush`/`pendingDelete`,
  bumps `localRevision`, reschedules reminders, and asks `SyncEngine` for a debounced sync.
- **Everything app-level is `@MainActor`** (`APIClient`, `SyncEngine`, stores). URLSession does the waiting
  off the main thread; JSON payloads are small. That keeps us clear of Sendable problems.
- **`AppServices`** owns and wires every long-lived object. The `AppDelegate` creates it lazily, and
  `WayfareApp` injects each `@Observable` into the environment (`withServices`). Previews use
  `AppServices.preview()` (in-memory store plus `SampleData`).
- **Navigation:** a single `NavigationStack(path: [AppRoute])` owned by `AppRouter` (UX spec 1.1). Deep
  links and notification taps replace the path. Root sheets are one `RootSheet` enum.
- **Pure logic is separate and unit-tested:** `CalendarDay`, `TimeFormat`, `DayGrouping`, `NowNext`,
  `TripPhase`, `ReminderPlanner`, `ImportReview`, `ItemFormState`, the DTOs. They work on value types
  (`ItemSnapshot`), not on SwiftData models.
- Swift 5 language mode (`SWIFT_VERSION = 5.0`, strict concurrency `minimal`), iOS 17.0, iPhone only, no
  third-party packages.

## 2. File map

| Path (under `ios/`) | Lines | What it does |
|---|---|---|
| `project.yml` | 113 | XcodeGen spec: app + test targets, Info.plist keys, entitlements, scheme |
| `Config.xcconfig` | 21 | `API_BASE_URL` (the `https:/$()/` trick), `DEVELOPMENT_TEAM`, versions, optional local include |
| `README.md` | 114 | Owner setup, run, TestFlight, App Store Connect |
| `Wayfare/Wayfare.entitlements` | 12 | Sign in with Apple (Default), `aps-environment` development |
| **App/** | | |
| `WayfareApp.swift` | 39 | `@main`, delegate adaptor, environment injection helpers |
| `AppDelegate.swift` | 72 | APNs token → hex, push delivery, notification taps and foreground presentation |
| `AppServices.swift` | 266 | Composition root, launch/foreground, wipe, deep links, notification routing |
| `AppRouter.swift` | 106 | `@Observable` path, sheets, timeline focus, pending invite, `wayfare://invite/<code>` parsing |
| `SessionStore.swift` | 193 | Sign in with Apple, name capture, reauth, sign-out, account deletion |
| `RootView.swift` | 104 | NavigationStack, sheets, Welcome cover, `.onOpenURL`, scene phase, offline banner modifier |
| **Models/** | | |
| `Trip.swift`, `Item.swift`, `Member.swift` | 89 / 112 / 36 | SwiftData `@Model`s with `needsPush`, `pendingDelete`, server `updatedAt`, `localRevision` |
| `ItemKind.swift` | 193 | `ItemKind` (name, symbols, color tokens), `TransportMode`, `MemberRole` |
| `ItemSnapshot.swift` | 54 | Immutable item value used by pure logic and views |
| `DTOs.swift` | 420 | Contract DTOs (lenient decoding, explicit `null`s on writes), request bodies, error body |
| `ModelMapping.swift` | 146 | DTO ⇄ model mapping, `writeDTO`s, second-precision dates |
| `SampleData.swift` | 132 | "Lisbon & Porto" preview trip: flight, hotel, dinner, train, tour, note |
| **Networking/** | | |
| `APIClient.swift` | 202 | All contract endpoints, bearer token, typed errors, 401 hook, 45 s import timeout |
| `APIError.swift` | 97 | Typed errors from the contract's error body and URLError mapping |
| `JSONCoding.swift` | 48 | `.iso8601` encoding; lenient ISO decoding (accepts fractional seconds too) |
| `Keychain.swift` | 83 | Generic-password Keychain helper and `TokenStore` |
| `AppConfig.swift` | 59 | `APIBaseURL` from Info.plist, DEBUG override, APNs environment, links |
| `NetworkMonitor.swift` | 46 | `NWPathMonitor`; banner after 2 s offline; reconnect hook |
| **Sync/** | | |
| `SyncEngine.swift` | 412 | Push (trips → items → deletes/leaves), pull, idempotent apply, tombstones, cursor |
| `TripStore.swift` | 217 | All local writes (create/edit/delete/leave/duplicate/drafts), reads, wipe |
| **Notifications/** | | |
| `ReminderPlanner.swift` | 128 | Pure: fire dates, 60-soonest cap within 60 days, body copy per kind |
| `NotificationScheduler.swift` | 104 | `UNCalendarNotificationTrigger` requests `item-<id>`, categories/actions |
| `NotificationPermission.swift` | 114 | Authorization status, priming moments A/B/C bookkeeping |
| `DeviceRegistrar.swift` | 127 | `PUT /v1/devices/current` (debounced, retried), preferences, sandbox/production |
| **DesignSystem/** | | |
| `Palette.swift` | 151 | Every color token (light/dark, Increase Contrast variants), cover palette, spacing, radii |
| `Typography.swift` | 46 | Font styles, rounded large-title nav bar |
| `Components/Components.swift` | 260 | KindIcon, CoverTile, Pill, ZoneBadge, UnsyncedMarker, AvatarCircle, card, banners |
| `Components/Toast.swift` | 77 | Toast center and overlay |
| **Utilities/** | | |
| `CalendarDay.swift` | 100 | `YYYY-MM-DD` value type, zone-aware conversions |
| `TimeFormatting.swift` | 228 | Pure formatters: times in a zone, zone badge, +1/−1, durations, countdowns |
| `DayGrouping.swift` | 211 | Pure: trip phase, timeline sections, lodging bands, Now/Next |
| `SystemActions.swift` | 84 | Apple Maps directions, call, open link, copy; `NotificationPayload` |
| **Features/** | | |
| `Welcome/WelcomeView.swift` | 208 | Welcome, Sign in with Apple, invite card, name capture |
| `Trips/TripsListView.swift` | 345 | Now/Upcoming/Past, search (6+), swipe/context actions, empty/first-sync/status states |
| `Trips/TripRowViews.swift` | 183 | Trip row, hero card with "Next up", placeholder row |
| `TripEditor/TripEditorView.swift` | 338 | New/Edit trip, destination search, cover picker |
| `TripEditor/TripFormState.swift` | 106 | Trip form value, emoji/flag helpers |
| `TripEditor/TimeZonePickerView.swift` | 97 | Searchable `knownTimeZoneIdentifiers` with Suggested |
| `TripDetail/TripDetailView.swift` | 252 | Header, Timeline/Map/Info, toolbar, sheets, tombstone handling |
| `TripDetail/TripInfoView.swift` | 142 | Overview, notes, people, kind summary (filters timeline), actions |
| `Timeline/TripTimelineView.swift` | 317 | Day sections, Now/Next each minute, auto-scroll, Today button, swipe/context menus |
| `Timeline/TimelineRowView.swift` | 308 | Row text (pure), row with rail/chip/pills/zone badge, staying band, section header |
| `ItemDetail/ItemDetailView.swift` | 415 | Actions row, code block + Show Large, map snapshot, details, reminder, footer |
| `ItemDetail/ItemHeaderCard.swift` | 412 | Per-kind header cards, Copy Details text |
| `ItemEditor/ItemEditorView.swift` | 90 | Add/Edit sheet, kind grid, wall-clock helpers |
| `ItemEditor/ItemFormView.swift` | 619 | The form: kind sections, zone-aware pickers, location, reminder, conflicts |
| `ItemEditor/ItemFormState.swift` | 247 | Form value: defaults, validation, auto-title, kind-change cleanup |
| `ItemEditor/LocationSearch.swift` | 242 | `MKLocalSearchCompleter` + `MKLocalSearch` model and view |
| `DayMap/DayMapView.swift` | 340 | `Map` + `Marker`s, day chips, dashed route, selection card, list fallback |
| `Share/ShareTripView.swift` | 314 | Invite (role, link, ShareLink, copy), members, remove/leave |
| `Invite/InviteViews.swift` | 217 | Accept invite states, Join with Code |
| `Import/ImportView.swift` | 401 | Consent → paste → loading → review → save; error states |
| `Import/ImportReview.swift` | 84 | Pure: draft rows, warnings, duplicate detection |
| `Settings/SettingsView.swift` | 369 | Account, notifications, sync, about, Developer (DEBUG), sign out |
| `Settings/DeleteAccountView.swift` | 109 | Account deletion page |
| `Priming/PrimingSheet.swift` | 72 | Notification priming card |
| `Resources/Assets.xcassets` | JSON | AppIcon (empty slot), AccentColor, LaunchBackground |
| **WayfareTests/** | | |
| `DTOCodingTests.swift` | 236 | Contract JSON samples, writes, errors, invite URLs |
| `DayGroupingTests.swift` | 200 | Trip-zone grouping, midnight, all-day, lodging, date line, badges, Now/Next |
| `ReminderTests.swift` | 137 | Fire dates, body copy, 60 cap, horizon, stable ties |
| `FormAndImportTests.swift` | 122 | Form defaults/validation, wall clock, import warnings, emoji, hex |
| `SyncApplyTests.swift` | 70 | Idempotent upserts (incl. uppercase ids), local edits kept, tombstones |

`Wayfare/Info.plist` is **generated** by XcodeGen from `project.yml` (`info:` block) and isn't checked in.

## 3. How sync works

State per row: `updatedAt` (server ms; 0 = never acknowledged), `needsPush`, `pendingDelete`,
`localRevision`. The cursor lives in `UserDefaults` (`sync.cursor`).

1. **Triggers:** launch (`AppServices.start`), foreground (`scenePhase == .active`), 1.5 s after any local
   edit (`TripStore.save → SyncEngine.localChangeMade`), pull-to-refresh (`await syncNow()`), reconnect
   (`NetworkMonitor.onReconnect`), and an `itemChanged` push (foreground delivery or tap). Calls coalesce:
   a request during a running sync asks for one more pass.
2. **Push, in order:** trip upserts (`PUT /v1/trips/:id`) → item upserts/deletes (`PUT`/`DELETE`, skipping
   items of trips being deleted) → trip deletes (owner: `DELETE /v1/trips/:id`; others:
   `DELETE /v1/trips/:id/members/<me>`, i.e. leave). Trips go first, so an offline-created item in an
   offline-created trip works.
   - A response only clears `needsPush` if `localRevision` didn't change during the request, so an edit made
     mid-flight is never lost.
   - Rows the server never saw (`updatedAt == 0`) are deleted locally without a request.
   - `DELETE` → 404 counts as success.
   - Permanent rejections (400/403/404/409): a never-acknowledged row is dropped. Otherwise the local flag
     is cleared and the next pull is a **full resync** (`since=0`), which restores the server's version
     (e.g. after a downgrade to viewer). A one-time toast reports discarded changes (UX spec 5.3).
   - Offline, 429, 5xx: the sync stops, rows stay dirty, and the next trigger retries.
3. **Pull:** `GET /v1/sync?since=<cursor>`. Every row is an **idempotent upsert keyed by the lowercased id**
   (per the CTO: the server's cursor overlaps by about 5 s and joined trips come back in full). Tombstones
   delete the local row. A trip tombstone also deletes its items and members, and rows for a trip
   tombstoned in the same response are ignored. Rows with unpushed local changes are **skipped**: our
   write goes next and wins (last write wins by server receive time). Then the cursor is stored.
4. **After every pass,** reminders are rescheduled from the live items (collaborator edits update your
   reminders too).

IDs are generated as `UUID().uuidString.lowercased()`. Every DTO decoder, model initializer and write lowercases
IDs, so an uppercase ID from anywhere can't create a duplicate.

## 4. Notifications

- **Local reminders** (`ReminderPlanner` + `NotificationScheduler`): fire = `startAt − reminderMinutes`,
  identifier `item-<id>`, `threadIdentifier = tripId`. Only future reminders within 60 days are scheduled,
  capped at the **60 soonest**. Stale `item-` requests are removed on every pass. Triggers are
  `UNCalendarNotificationTrigger` with explicit UTC components, so a zone change on the device can't shift
  them. Categories: `ITEM_REMINDER` (Directions) and `ITEM_REMINDER_CODE` (Directions + Copy Code).
- **Permission** is never requested at launch. It's requested only from the priming card, at moments A
  (first trip created), B (first reminder picked in a form) and C (joined a trip), each at most once, and
  from Settings/"Turn On" rows.
- **Device registration:** `PUT /v1/devices/current` with `sandbox` in DEBUG and `production` otherwise,
  debounced by 1 s. It is re-sent on token change, on foreground if the zone changed, and after failures.
- **Sign-out** sends `POST /v1/auth/logout` with `{ "apnsToken": … }` when a token exists (contract change),
  then wipes local data, the Keychain token and all pending notifications.

## 5. Deviations from the UX spec (and why)

| Spec | What I built | Why |
|---|---|---|
| Schedule the 64 soonest reminders (4.1 / brief F5) | 60 | Task brief asked for 60. It leaves headroom under iOS's 64. |
| Tokens as asset-catalog Color Sets (DS §2) | Tokens in code (`Palette`, dynamic `UIColor`, incl. Increase Contrast). Only `AccentColor` and `LaunchBackground` are in the catalog | Single diffable source, no hand-edited JSON. Visually the same. |
| Trip Detail large title | Inline title; the header row holds dates / "Day X of Y" | A large title doesn't collapse over a VStack(header, picker, list). It would waste space. |
| Deep link while a dirty form is open → "Discard changes?" (4.3) | The path is replaced and the sheet closes | Needs a global dirty-form registry. TODO. |
| State restoration (<1 h) (1.2) | Not implemented | TODO. |
| New-item 1 s highlight flash (3.5) | Timeline scrolls to the new item, no flash | TODO. |
| "Please sign in again" as a sheet (5.7) | The Welcome cover with reauth copy. Local data is kept; a different Apple ID wipes first | Reuses one sign-in surface. |
| Offline banner on every screen | Trips list and Trip detail only | Low value on sheets. Each network-bound action has inline offline copy. |
| Geocode address-only items on save; map centers on the geocoded destination (brief F4, 3.3.2) | Directions for address-only items hand the address to Apple Maps. An empty day shows the card and `.automatic` camera | Avoids `CLGeocoder` (deprecated in the iOS 26 SDK) and rate limits. |
| Developer section in Debug **and TestFlight** | DEBUG only | Task brief. TestFlight detection via receipt URL is deprecated. |
| Notes "links detected" | Plain selectable text | TODO: `AttributedString` with data detection. |
| Pending invite retried on reconnect "with a local toast" | Reconnect reopens the Accept Invite sheet | Simpler, same outcome. |
| Deletion toast "{name} deleted …" (5.6) | "“{title}” was deleted." | The tombstone row is gone before we can read `updatedBy`. |
| Map pins: custom `Annotation` with a numbered badge | `Marker` with `monogram` numbers (days) or kind symbol (All) | Task asked for `Map` + `Marker`. It's native and accessible. |

## 6. What might not compile (check these first)

In order of likelihood:

1. **`Features/DayMap/DayMapView.swift` L44–64:** `if/else` inside `ForEach` inside the `Map` content
   builder, and `MapPolyline(...).stroke(_:style:)`. If `MapContentBuilder` rejects the `if/else`, use two
   `ForEach`s (numbered / unnumbered). If `.stroke(_:style:)` is missing, use `.stroke(color, lineWidth: 3)`.
2. **`Features/ItemEditor/LocationSearch.swift` L20–113:** `@Observable` on an `NSObject` subclass that
   conforms to `MKLocalSearchCompleterDelegate`, with `nonisolated` delegate methods that hop via
   `MainActor.assumeIsolated`. If Xcode complains, drop `@Observable` and use
   `ObservableObject` + `@Published` + `@StateObject` in `LocationSearchView`.
3. **`App/SessionStore.swift` ~L146:** `try await ASAuthorizationAppleIDProvider().credentialState(forUserID:)`
   (the async form of `getCredentialState(forUserID:completion:)`). If missing, wrap the completion API in
   `withCheckedContinuation`, or delete the check.
4. **`App/AppDelegate.swift` L47–72:** `nonisolated` UNUserNotificationCenterDelegate methods in a
   `@MainActor` class that hop with `Task { @MainActor in … }`. It should be fine in Swift 5 mode. If you
   see a "cannot satisfy nonisolated requirement" diagnostic, this is where.
5. **`Features/Import/ImportView.swift` ~L69** `navigationDestination(item:)` (iOS 17) and **~L143**
   `PasteButton(payloadType:)` closure (may be `@Sendable`; the assignment already hops to the main actor).
6. **`Features/ItemEditor/LocationSearch.swift` ~L211:** `.searchable(text:isPresented:placement:prompt:)`
   (iOS 17 overload with `isPresented`).
7. **`Models/Item.swift` L24:** `var details: [String: String]` stored directly in SwiftData. It compiles. If
   it misbehaves at runtime, store `Data` and expose a computed `[String: String]`.
8. **`Sync/TripStore.swift` L207–209:** `context.delete(model:)` batch deletes on wipe.
9. **`Features/Timeline/TripTimelineView.swift` ~L140:** `if case .staying(let night, let nights) = row.role`
   inside a `Button` label builder.
10. `View` extensions marked `@MainActor` (`withServices`, `offlineBanner`, `toastOverlay`) access
    main-actor state. That's needed with Xcode 15 and harmless with 16+.

If the first build shows dozens of errors in one file, it's probably one bad line cascading. Fix the
first error in each file and rebuild.

## 7. Contract and spec issues found

1. **`itemChanged` pushes can't trigger a background sync.** The backend's payload (`apns.js buildPayload`)
   has no `content-available: 1`, so iOS delivers it to the app only in the foreground or on tap. Add
   `"content-available": 1` to the `aps` of collaborator pushes if you want reminders updated before the
   user opens the app. (The client already syncs on delivery.)
2. **`User.email` may be `null`** (the backend returns `email || null`, the contract shows a string). The client
   treats it as optional.
3. **`expiresAt` format for invites** isn't pinned to "no fractional seconds" like other instants. The
   backend uses its `isoInstant` helper. The client decodes both forms anyway.
4. **Invite code alphabet/case.** The contract says "8-char code". The backend normalizes to uppercase and strips
   spaces and hyphens. Worth writing into the contract. The client uppercases typed codes and passes deep-link
   codes through unchanged.
5. **No endpoint for saving notification preferences without an APNs token** (Simulator, or before the user
   allows notifications). Preferences stay local until a token exists. Fine for v1, but worth knowing.
6. **Member rows on a trip tombstone**: the contract doesn't say whether member tombstones accompany a
   removed or deleted trip. The client deletes members with the trip either way.
7. **Default `colorHex` `#2F6FEB`** (contract example and backend default) isn't in the design system cover
   palette (Lagoon `#0A6B7C` is the default). The client always sends a palette color and renders unknown
   hex values as-is (DS 7.1).
8. **Permanent write rejections** have no per-row reason in `/v1/sync`. The client does a full resync
   (`since=0`) after one. That's fine at personal scale, but heavy for big accounts. A `GET /v1/trips/:id`
   would be cheaper.
9. **UX spec 4.1 vs brief F5 vs this task:** 64 vs 60 reminders. I used 60 (see §5).
10. The UX spec asks for the deleter's name on item tombstones (5.6). `updatedBy` on a tombstone would work if
    the client read it before deleting the row. That's a small TODO, not a contract gap.

## 8. Assets

- `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` has a **single 1024×1024 universal slot with
  no image** (I can't produce a PNG). **App Store / TestFlight uploads fail without it.** Drop a 1024×1024
  opaque PNG (brief: design system §8, "The Folded Route") into that slot in Xcode. For iOS 18 you can
  add Dark and Tinted variants in the same set.
- `AccentColor.colorset`: `accent` light `#0A6B7C`, dark `#4EC3D4` (set as the global accent via
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`).
- `LaunchBackground.colorset`: `background` light `#F6F4EF`, dark `#0F1115`, used by `UILaunchScreen`.
- All other tokens live in `DesignSystem/Palette.swift`, copied verbatim from the design system.
- The Welcome screen draws a placeholder icon (teal gradient + SF Symbol) until the real artwork exists.

## 9. TODOs

- State restoration of the last open trip/segment (<1 h).
- Guard deep links against dirty forms (global "has unsaved form" flag + Discard dialog).
- New-item highlight flash; offline banner on remaining screens; link detection in notes.
- Geocode address-only items on save (MapKit `MKGeocodingRequest` on iOS 26+, or `MKLocalSearch` with the address).
- Destination geocode + cache for the empty day map.
- Show the deleter's name on remote item deletion.
- Name the trip in the "role downgraded" notice (currently a generic count).
- UI tests for sign-in-free flows (create trip, add item offline, reminders).
- When the backend adds `content-available`, also handle background refresh completion timing.
