# Wayfare UX Spec v1

Owner: UX Designer. Inputs: `docs/api-contract.md` v1, `company/decisions.md`.
Visual tokens, type styles and symbol names are defined in `company/03-design-system.md` and referenced here by token name (e.g. `kindFlight`, `accent`).

This spec only designs what API contract v1 supports. Anything that would need a contract change is listed under "Open questions for the owner".

---

## 0. Design principles

1. **The next thing first.** On a trip day, the app opens on what's happening now and what's next. Everything else comes second.
2. **Local time, always labelled.** Every time is shown in the zone where it happens. When that zone differs from the trip's zone, a badge says so.
3. **Works in airplane mode.** Every read and every edit works offline. Only four things need a network: sign-in, invites, AI import, and location search. Each of those says so in plain words when it's unavailable.
4. **Nothing is saved without review.** AI drafts, destructive actions and the permission prompt all ask first.
5. **Native, not novel.** Use stock SwiftUI containers (`NavigationStack`, `List`, `Form`, sheets, swipe actions, context menus, `.searchable`). Custom drawing is limited to the timeline rail and trip cover tiles.

---

## 1. Information architecture and navigation

### 1.1 Decision: single stack, no TabView

The app has one root, a list of trips, so a tab bar would hold only one tab. We use a single `NavigationStack`. Everything else is a push or a sheet.

```
NavigationStack (root)
└── Trips List                                   [root]
    ├── (sheet) Settings                          ← avatar button, top-left
    ├── (sheet) New Trip                          ← "+" menu → New Trip
    ├── (sheet) Join with Code                    ← "+" menu → Join with Code
    └── (push) Trip Detail                        ← tap a trip
        ├── Segmented control: Timeline | Map | Info
        ├── (sheet) Add Item  (kind grid → form)  ← "+" menu → a kind
        ├── (sheet) AI Import                     ← "+" menu → Import from Email
        ├── (sheet) Share & Members               ← people button
        ├── (sheet) Edit Trip                     ← Info tab → Edit
        └── (push) Item Detail                    ← tap a timeline row / map card
            └── (sheet) Edit Item
Full-screen cover (only when signed out): Welcome / Sign in
Overlay sheet (from any state): Accept Invite       ← wayfare://invite/<code>
```

### 1.2 Navigation rules

- **Push** is for drilling into content: trip, then item.
- **Sheets** are for creating, editing or configuring. Every form sheet has **Cancel** (leading) and **Save / Add** (trailing, bold, disabled until the form is valid). Swipe-to-dismiss on a dirty form shows the confirmation dialog "Discard changes?" (`interactiveDismissDisabled` while dirty, with a Discard / Keep Editing dialog on Cancel).
- **Trip Detail segments** use a `Picker(.segmented)` pinned under the navigation title, not in the toolbar, so the title can stay large. The selected segment is remembered per trip for the session. A trip always opens on **Timeline** except when deep-linked into Map (never in v1).
- **Deep links** replace the navigation path. They pop to root, then push trip, then item. They never stack on top of an unrelated path.
- **State restoration:** relaunching restores the last open trip and segment if the app was killed less than 1 hour ago. Otherwise it opens on the Trips list.

### 1.3 Toolbar map

| Screen | Leading | Title | Trailing |
|---|---|---|---|
| Trips List | Avatar circle (initials) → Settings | "Trips" (large) | `+` Menu: New Trip, Join with Code |
| Trip Detail | Back | Trip title (large, cover emoji prefixed) | People button (`person.2.fill` + member count when >1), `+` Menu (hidden for viewers) |
| Item Detail | Back | Inline, item title truncated | Edit (hidden for viewers), `ellipsis.circle` Menu: Copy Details, Delete |

`+` Menu in Trip Detail, in order: Flight, Lodging, Activity, Food, Transport, Note, divider, **Import from Email…** (`sparkles`). Picking a kind opens the Add Item sheet with that kind already chosen, skipping the kind grid.

---

## 2. Onboarding and Sign in with Apple

### 2.1 Welcome (signed-out root, full-screen cover)

**Purpose:** get the person signed in with one tap, and explain why sign-in is needed (sync and sharing).

**Layout (top to bottom, vertically centered, max content width 420pt):**
1. App icon artwork, 96pt, 22pt corner radius.
2. "Wayfare" in `.largeTitle.rounded.bold`.
3. Tagline in `.title3`, `textSecondary`: "Every plan for every trip, in one calm timeline."
4. Three value rows (symbol 24pt in `accent` + `.body` text):
   - `calendar.day.timeline.left`: "Flights, stays and plans, sorted by day in local time"
   - `wifi.slash`: "Works offline, syncs when you land"
   - `person.2.fill`: "Plan together with the people you travel with"
5. Spacer.
6. `SignInWithAppleButton(.signIn)`, full width, height 52, corner radius 12. Style is `.black` in light mode and `.white` in dark mode. Scopes: `.fullName`, `.email`. On success, send both `identityToken` and `authorizationCode` to `POST /v1/auth/apple` (the server needs the code to revoke Apple access on account deletion).
7. Footnote in `.footnote`, `textSecondary`: "By continuing you agree to the Terms and Privacy Policy." Both are links.

**Pending invite variant:** if the app was opened from `wayfare://invite/<code>` while signed out, a card appears above the Sign in button: `envelope.open.fill` + "You've been invited to a trip. Sign in to join." The code is kept in memory and in `UserDefaults` until it's accepted or expires.

**States:**
- *Signing in:* the button is replaced by a `ProgressView` with the label "Signing in…". The whole screen ignores taps.
- *Apple sheet cancelled:* no error. Return to idle.
- *Network error:* inline banner above the button, "Can't reach Wayfare. Check your connection and try again." (`danger` symbol `exclamationmark.triangle.fill`).
- *Server error (`unauthorized` from `/v1/auth/apple`):* "Sign in with Apple didn't complete. Please try again."

**Accessibility:** the value rows are combined into a single VoiceOver element each. The Apple button keeps its system label. At accessibility text sizes the icon shrinks to 64pt and the content scrolls.

### 2.2 Name capture (conditional)

Apple sends the name only on first sign-in. If `/v1/auth/apple` returns a user with an empty `displayName`, push **"What should your travel companions call you?"**:
- One `TextField` (`.givenName` content type, autofocus), placeholder "Your name".
- Footnote: "Shown to people you share trips with, like 'Nick added Dinner at Taberna.'"
- Button **Continue** (disabled while empty; trimmed, 1–40 chars) → `PATCH /v1/me`.
- **Skip** in the toolbar sets nothing. The app falls back to "A trip member" in UI copy.

### 2.3 First run landing

After sign-in the Trips list shows its empty state (section 3.1). There is no tutorial carousel and no system prompt on launch. If an invite is pending, the Accept Invite sheet (section 3.10) opens right away.

### 2.4 Notification-permission priming

We never call `requestAuthorization` at launch. The system prompt appears only after our own priming card, and only at one of these moments. Whichever comes first wins, and priming is shown at most **once per moment type** and never again after the system prompt has been answered.

| Moment | Trigger | Priming card copy |
|---|---|---|
| **A. First trip created** (primary) | New Trip sheet saves the user's first trip | Title: "Get a heads-up before each plan" · Body: "Wayfare can remind you before flights and check-ins, and send a short morning briefing on each day of {Trip title}." |
| **B. First reminder chosen** | User picks any reminder other than None in an Item form while status is `.notDetermined` | Title: "Turn on reminders?" · Body: "We'll remind you {n} before {item title}, even with no signal." |
| **C. Joined a shared trip** | Accept Invite succeeds while status is `.notDetermined` | Title: "Know when plans change" · Body: "Get a notification when {owner name} or others add or change plans in {Trip title}." |

**Priming card UI:** a `.presentationDetents([.medium])` sheet containing a 56pt `bell.badge.fill` symbol in `accent`, the title (`.title2.bold`), the body (`.body`, `textSecondary`), a primary button **Turn On Notifications** (calls `requestAuthorization([.alert, .sound, .badge])`, then registers for remote notifications and `PUT /v1/devices/current` with defaults `briefingEnabled: true`, `briefingHour: 7`, `collabAlertsEnabled: true`), and a secondary text button **Not Now**.

- **Not Now:** reminders stay saved on items but won't fire. Item forms show the inline "Notifications are off" row (section 3.5, Reminder field).
- **Denied at system prompt:** same as Not Now. Settings shows the "Open iOS Settings" row.
- **Granted:** haptic `.success`, sheet dismisses, and all existing reminders are scheduled.

---

## 3. Screen specs

Conventions used below:
- **Offline banner:** a thin bar under the navigation bar: `wifi.slash` + "Offline. Changes will sync when you're back online." (`.footnote`, `textSecondary` on `surface2`). It appears 2s after connectivity is lost (so brief drops don't flicker it) and disappears on reconnect, when sync runs automatically.
- **Unsynced marker:** any trip or item with local changes not yet acknowledged by the server shows a small `arrow.triangle.2.circlepath` (12pt, `textSecondary`) after its title. VoiceOver appends ", not yet synced".
- **Viewer mode:** see section 5.3.

### 3.1 Trips List (root)

**Purpose:** see all trips at a glance, jump straight into the current one.

**Layout:** `List` with `.insetGrouped` style on the `background` color, large title "Trips". Sections, in order:

1. **Now** (only if a trip is in progress, meaning today in the trip's time zone falls between `startDate` and `endDate` inclusive). Each trip here is a **Hero card**:
   - Cover tile (64pt, emoji on `colorHex`, radius 16).
   - Title in `.title2.rounded.bold`, destination in `.subheadline` `textSecondary`.
   - Progress line: "Day 3 of 9" (`.subheadline.monospacedDigit`) plus a thin 4pt progress bar in the trip color.
   - **Next up** row: kind symbol + item title + time ("Next · 20:30 Dinner at Taberna"). If nothing remains today: "Nothing else today". If the day has no items: "Free day".
   - Tap opens Trip Detail with the timeline scrolled to today.
2. **Upcoming:** start date in the future, sorted by `startDate` ascending. Standard **Trip row**: 44pt cover tile, title (`.headline`), a subtitle "Oct 1 – 9 · Portugal" (`.subheadline`, `textSecondary`), and a trailing countdown chip "in 12 days" ("Tomorrow" at 1, "in 3 wks" beyond 20 days, "in 4 mo" beyond 60 days).
3. **Past:** end date before today, sorted by `endDate` descending. Same Trip row, no countdown, title in `textSecondary`. The section is **collapsed by default** once it holds more than 3 trips ("Show 12 past trips" disclosure row). The expanded state is remembered.

Shared trips show a trailing `person.2.fill` (12pt, `textSecondary`) after the title. Trips where the user is a viewer also show an `eye` badge.

**Search:** `.searchable` (placement `.navigationBarDrawer(displayMode: .automatic)`) appears once there are 6 or more trips. It filters on title, destination, and item titles/location names, and results are grouped by the same sections.

**Interactions:**
- Tap a row → push Trip Detail.
- Swipe trailing: **Delete** (owner, red, `trash`) or **Leave** (non-owner, red, `rectangle.portrait.and.arrow.right`). Both open a confirmation dialog (section 3.3.4). No full-swipe for destructive actions.
- Context menu (long press, with a preview of the trip card): Open, Edit Trip (owner/editor), Share (owner/editor), Delete or Leave.
- Pull to refresh → sync now.

**States:**
- *Empty (no trips):* centered `ContentUnavailableView`, symbol `suitcase.rolling.fill` in `accent`, title "No trips yet", description "Create a trip, then add flights, stays and plans, or paste a confirmation email and let Wayfare fill it in." Two buttons: **New Trip** (borderedProminent) and **Join with Code** (bordered).
- *First sync in progress (fresh install, no local data, cursor 0):* 3 redacted placeholder rows (`.redacted(reason: .placeholder)`) for up to 10s. After that, the empty state appears with a footer "Still syncing…".
- *Sync error:* a non-blocking footer row at the bottom of the list, "Couldn't sync. Pull to retry." Local data stays visible.
- *Offline:* offline banner. Everything still works.
- *Search with no results:* `ContentUnavailableView.search(text:)`.

**Accessibility:** each trip row is one element. Label: "{title}, {destination}, {date range spoken}, {countdown}{, shared}{, view only}". The Hero card label adds "Day 3 of 9. Next: Dinner at Taberna at 8:30 PM." Custom actions: Edit, Share, Delete/Leave.

### 3.2 New / Edit Trip form

**Purpose:** create a trip with enough info (dates and time zone) to build the timeline correctly.

**Presentation:** sheet with `NavigationStack` and a `Form`. Title "New Trip" or "Edit Trip". Cancel / **Create** (or **Save**).

**Sections:**
1. **Cover preview** (header, not a form row): an 88pt cover tile centered, with the title below it updating live. Tapping the tile scrolls to the Cover section.
2. **Trip**
   - Title: `TextField`, placeholder "e.g. Lisbon & Porto", required, 1–80 chars, autofocus on New.
   - Destination: a row that pushes **Destination Search** (MKLocalSearchCompleter, `resultTypes = .address`, filtered to cities, regions and countries). Picking a result sets `destination` to the result's title ("Lisbon, Portugal"), **and** sets `timeZone` from the resolved `MKMapItem.timeZone` if the user hasn't changed the time zone manually, **and** suggests the country's flag emoji as `coverEmoji` if the user hasn't picked one. Free text is also allowed: the search screen has "Use "{typed text}"" as its first row.
3. **Dates**
   - Start: `DatePicker(.date)`, default today + 14 days on New.
   - End: `DatePicker(.date)`, `in: start...`, default start + 4 days. If the user moves Start past End, End moves to keep the same length.
   - Footer (live): "9 days · 8 nights".
4. **Time zone**
   - One row: "Time Zone" with the value on the trailing side ("Lisbon (GMT+1)"). It pushes a **Time Zone Picker**: a `.searchable` list of all `TimeZone.knownTimeZoneIdentifiers`, city names from the identifier's last component with underscores replaced, current offset on the trailing side. Pinned top section: "Suggested", with the destination's zone and the device's current zone.
   - Footer: "Your timeline is organized by days in this time zone."
5. **Cover:** emoji and color picker (see design system, section 9). An emoji field (a single-grapheme text field whose keyboard opens to emoji, `keyboardType(.default)` with a "Choose Emoji" hint; non-emoji input is rejected), 12 color swatches in a 6-column grid (44pt tap targets, selected swatch has a 3pt `textPrimary` ring and a `checkmark` symbol).
6. **Notes:** `TextField(axis: .vertical)`, `lineLimit(3...10)`, placeholder "Notes for everyone on this trip".
7. *(Edit only, owner)* **Delete Trip** (destructive button, centered). *(Edit only, non-owner)* **Leave Trip**.

**Validation:** Create is disabled until the title is non-empty. There are no other hard requirements (defaults: device time zone, ✈️ emoji, `#0A6B7C` color).

**Changing dates or time zone on a trip with items:** items are never moved. Items that fall outside the new range are flagged (section 5.2). Changing the time zone shows a footer warning while editing: "Days will be regrouped in the new time zone. Item times don't change."

**After Create:** the sheet dismisses, Trip Detail is pushed with its empty timeline, then priming moment A (section 2.4) is shown if eligible.

**Accessibility:** color swatches are labelled by color name ("Lagoon, selected"). The emoji field is labelled "Cover emoji, {emoji name}".

### 3.3 Trip Detail container

Large title: "{coverEmoji} {title}". Under it, a **trip header** (not sticky): the date range "Thu, Oct 1 – Fri, Oct 9" in `.subheadline`, and when in progress "Day 3 of 9" in `accent`. Then the segmented control **Timeline | Map | Info**.

#### 3.3.1 Timeline tab

**Purpose:** the day-by-day plan, reading like a boarding pass stack.

**Grouping rule:** items are grouped into **days in the trip's time zone** (`Trip.timeZone`), using `startAt` converted to that zone. Sections cover every date from `startDate` to `endDate`, **including empty days**. Days outside that range are added only when items fall on them (section 5.2).

**Section header** (sticky, `.pinnedViews`-style behavior via `List` section headers):
- "Thu, Oct 1" (`.headline`) + "Day 1" (`.subheadline`, `textSecondary`) on the leading side.
- Today's header adds a "Today" capsule in `accent` (`onAccent` text).
- Days before the trip: "Before trip", and after: "After trip", in `warning`.

**Row order within a day:**
1. **Lodging "staying" band** (see below) if a lodging stay covers this night but doesn't start or end today.
2. All-day items (`allDay == true`), by `sortIndex`.
3. Timed items by `startAt` ascending, ties broken by `sortIndex`, then `title`.

**Timeline row anatomy** (leading to trailing, min height 60pt):
- **Time column** (fixed width, fits "00:00" or "12:00 PM" at the current Dynamic Type size, trailing-aligned): start time in `.subheadline.monospacedDigit.weight(.semibold)`. For ranged items, the end time goes below in `.caption.monospacedDigit`, `textSecondary`. All-day items show "All day" in `.caption`.
  - Time is formatted **in the item's `startTimeZone`** (end time in `endTimeZone ?? startTimeZone`), respecting the user's 12/24-hour setting.
  - **Zone badge:** if the item zone's UTC offset at that instant differs from the trip zone's offset at that instant, a capsule appears under the time: the zone abbreviation ("EDT", or "GMT−4" when the system has no abbreviation), `.caption2.monospacedDigit`, `textSecondary` on `surface2`. If the item's local calendar date also differs from the section's date, the badge reads "Oct 1 · EDT".
  - **Day-offset suffix:** if an end time lands on a later local calendar date than its start, append a superscript-style "+1" (or "+2", or "−1" for date-line crossings westbound), `.caption2.bold`, `kind` color. Example: "09:45 ⁺¹".
- **Rail + chip:** a 32pt circular chip (kind tint background, kind-colored SF Symbol 15pt semibold) sitting on a 2pt vertical rail in `separator` that connects consecutive rows of the same day. The rail segment **above** the Now/Next item is `accent`.
- **Content:**
  - Title: `.body.weight(.semibold)`, 2 lines max.
  - Subtitle (`.subheadline`, `textSecondary`, 1 line), per kind:
    - flight: "JFK → LIS · Seat 14A", or if codes are missing, `locationName`
    - lodging: "Check-in 15:00" / "Check-out 11:00"
    - transport: "{fromName} → {toName}", or `locationName`
    - activity/food: `locationName`, else first line of notes
    - note: first line of notes
  - Optional trailing badges: `bell.fill` (10pt, `textSecondary`) if `reminderMinutes != nil`, and the unsynced marker.
- **Now / Next pill** (see below) aligned trailing on the title line.

**Now / Next highlighting** (only while the trip is in progress or on the day before it starts):
- **Now:** any timed item with `startAt ≤ now < endAt` (lodging excluded, as it would be "now" for days). The row gets a `accent` 3pt leading edge bar, and a "Now" pill (`accent` background, `onAccent` text, `.caption.bold`).
- **Next:** the first timed, non-lodging item with `startAt > now`. "Next" pill (`accentTint` background, `accent` text), plus a relative time under the title: "in 2 h 15 min" (updates each minute via `TimelineView(.everyMinute)`).
- If several items are Now, all get the pill. Only one item is ever Next.
- **Auto-scroll:** on open, when the trip is in progress, the list scrolls so today's header sits at the top (`ScrollViewReader`, no animation on first load). A floating **Today** button (`.bordered`, capsule, bottom-center) appears whenever today's section is scrolled off-screen, and scrolls back with animation.
- **Past items today** (endAt, or startAt when there is no end, before now) render title and time in `textSecondary`. They're not hidden.

**Multi-day lodging rendering:**
- **Check-in day:** a full row, kind lodging, time = check-in time, title = item title, subtitle "Check-in · 3 nights".
- **Each intermediate day:** a compact **staying band** pinned first in the section. It's 36pt tall, lodging tint background with radius 10, `bed.double.fill` 13pt, and the text "Staying at {title} · Night 2 of 3" in `.footnote`. Tapping it opens the same item. It isn't counted in Now/Next.
- **Check-out day:** a full row, time = check-out time, title = item title, subtitle "Check-out".
- If a lodging has no `endAt`, only the check-in row is shown, subtitle "Check-in".
- Both full rows open the same Item Detail.

**Empty day:** a single muted row, "Nothing planned", with an inline **Add** button (borderless, `plus.circle`) that opens Add Item with the date preset to that day at 12:00 in the trip zone. Hidden for viewers ("Nothing planned" only).

**Empty trip (no items at all):** `ContentUnavailableView`, symbol `calendar.badge.plus`, title "Start your plan", description "Add your flights, where you're staying, and anything you've booked." Buttons: **Add Item** (borderedProminent) and **Import from Email** (bordered, `sparkles`). Viewers see "Nothing planned yet" with no buttons.

**Interactions:**
- Tap row → push Item Detail.
- Swipe trailing: **Delete** (red, `trash`) with a confirmation dialog. Swipe leading: **Edit** (`accent`, `pencil`). Neither appears for viewers.
- Context menu (with row preview): Edit, Duplicate (creates a copy with a new id, title + " (copy)", same time), Copy Confirmation Code (when present), Directions (when coordinates exist), Delete.
- Pull to refresh → sync.
- Drag to reorder is **not** supported in v1 (time order wins). `sortIndex` only breaks ties and orders all-day items. It's set to the item's position among same-day all-day items at creation.

**Accessibility:**
- Each row is a single combined element. Example label: "Flight. TP 202 JFK to Lisbon. Departs 10:30 PM Eastern time, arrives 9:45 AM Lisbon time the next day. Seat 14A. Next, in 2 hours 15 minutes. Reminder set."
- Section headers have the `.isHeader` trait so the VoiceOver headings rotor jumps day by day.
- Custom actions: Edit, Delete, Copy confirmation code, Directions.
- At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`), the time column moves **above** the title (vertical stack) and the rail is hidden.
- The Now/Next pills are also announced, not just colored.

#### 3.3.2 Map tab (Day map)

**Purpose:** see where each day's plans are, get directions.

**Layout:**
- `Map` (MapKit for SwiftUI) fills the tab below the segmented control, respecting the safe area. Style `.standard(pointsOfInterest: .excludingAll)` so our pins aren't competing.
- **Day selector:** a horizontally scrolling row of capsule chips floating at the top over `.regularMaterial`: "All", then one chip per trip day ("Oct 1", "Oct 2", …). The default is today when the trip is in progress, otherwise "All". The selected chip is filled with `accent`.
- **Pins:** one `Annotation` per item that has coordinates. It's a 30pt kind-colored circle with a white SF Symbol, plus a number badge (order within the day, 1-based) when a single day is selected. Lodging pins are always shown on the days they cover, without a number.
- **Route line:** when a single day is selected, a `MapPolyline` joins that day's non-flight items in time order, 3pt, dashed `[6, 6]`, `accent` at 60% opacity. Flights are pinned at their departure point but never connected.
- **Camera:** fits all visible pins with 60pt padding, animated on day change (instant under Reduce Motion). A single pin uses a 2km span.
- **User location:** `UserAnnotation()` is shown only if location permission is already granted. The map never requests permission itself. A `MapUserLocationButton` appears only when authorized.
- **Selection card:** tapping a pin selects it (pin scales to 36pt) and shows a bottom card over `.regularMaterial`, radius 20: kind chip, title, time (with zone badge rules), `locationName`, and buttons **Directions** (`arrow.triangle.turn.up.right.diamond.fill`) and **Details** (pushes Item Detail).
- **Missing locations:** if some items for the selected day have no coordinates, a capsule at the bottom-leading corner reads "3 without a location" and opens a small sheet listing them. Tapping one pushes Item Detail, and editors see "Add location" there.

**States:**
- *No located items (for selection):* the map centers on the trip's destination if we can geocode it (cache the result), otherwise the world. An overlay card says "No places on this day yet. Add a location to an item to see it here."
- *Offline:* map tiles may be missing. Pins and the card still render, with the offline banner. No extra error.

**Accessibility:** `Map` pins get labels "{order}. {kind}: {title}, {time}". Below the map, VoiceOver users get an accessible **"List places"** button (also visible) that shows the same pins as a list sorted by time, because maps are hard to navigate by swiping.

#### 3.3.3 Info tab

A `Form`-style inset grouped list:
1. **Overview:** destination, dates ("Oct 1 – 9, 2026 · 9 days"), time zone ("Lisbon · GMT+1").
2. **Notes:** trip notes as `.body` text (links detected). "No notes" placeholder for viewers, "Add notes" button for editors.
3. **People:** up to 5 member rows (avatar initials circle in the trip color, name, role label), then "See All & Invite" → Share sheet.
4. **Summary:** counts by kind ("2 flights · 1 stay · 6 plans"), each tappable to filter the timeline to that kind (a filter chip "Flights ×" appears above the timeline and is cleared with ×).
5. **Actions:** **Edit Trip** (owner/editor), **Delete Trip** (owner, destructive) or **Leave Trip** (others, destructive).

#### 3.3.4 Destructive confirmations

- **Delete trip** (owner): `confirmationDialog`, title "Delete "{title}"?", message "This deletes the trip and all {n} plans for everyone it's shared with. This can't be undone.", button **Delete Trip** (destructive).
- **Leave trip:** "Leave "{title}"? You'll lose access until someone invites you again." Button **Leave Trip**.
- **Delete item:** "Delete "{item title}"?" Message only if shared: "It will be removed for everyone on this trip." Button **Delete**.

### 3.4 Item Detail

**Purpose:** everything needed at the counter or the door, with one-tap actions.

**Common layout** (`ScrollView`, `background` color):
1. **Header card** (surface, radius 20, padding 20). Its content varies by kind (see below). The kind label sits on top: a small caps line with symbol + "FLIGHT" in `.caption.bold` and the kind color.
2. **Action row:** a horizontal row of up to 4 equal-width vertical buttons (symbol 20pt over `.caption` label, 64pt tall, `surface` tint background, radius 14). Only applicable actions appear, in this order:
   - **Directions** (`arrow.triangle.turn.up.right.diamond.fill`): if lat/lon exist, or if an address exists (the address is geocoded on tap). Opens Apple Maps via `MKMapItem.openInMaps` with the default transport mode for the kind (walking for food/activity, driving otherwise).
   - **Call** (`phone.fill`): if `details.phone` exists. Opens `tel:`.
   - **Copy Code** (`doc.on.doc`): if `confirmationCode` exists. Copies to the pasteboard with a light impact haptic and a toast "Confirmation code copied".
   - **Website** (`safari`): if `details.website` or `details.bookingUrl` exists (`bookingUrl` takes priority, label "Booking").
3. **Confirmation code block** (if present): a large code in `.title2.monospaced.bold` with letter spacing +2, tappable to copy. Long press shows a context menu: Copy, **Show Large**, which presents the code full-screen at max size, landscape-friendly, for showing to staff.
4. **Location block** (if coordinates): a non-interactive `Map` snapshot, 160pt tall, radius 16, single pin, with `locationName` and `address` below it. Tapping it opens Directions.
5. **Details list:** label/value rows for any remaining `details` keys not already shown in the header (e.g. roomType, partySize, operator). Unknown keys are shown with a title-cased key. Values are selectable (`.textSelection(.enabled)`).
6. **Notes:** `.body`, links detected, selectable.
7. **Reminder row:** `bell.fill` + "Reminder: 3 hours before" or "No reminder". Also a warning line when notifications are off (same row as section 3.5, Reminder field).
8. **Footer meta:** "Updated by Sam · 2 h ago" (`.footnote`, `textSecondary`). This uses `updatedBy` resolved against members, or "You".

**Per-kind header layouts:**

- **Flight:**
  - Route line: `fromCode` and `toCode` in `.largeTitle.monospaced.bold` (e.g. `JFK ──✈── LIS`). An `airplane` symbol sits centered on a hairline between the codes. When codes are missing, use the title.
  - Under each code: local time (`.title3.monospacedDigit.semibold`), the date ("Thu, Oct 1") and zone abbreviation (`.caption`). The arrival time shows the "+1" suffix when applicable.
  - Center, under the plane: duration computed from instants ("7 h 15 min").
  - A 3-column grid below: Airline + flight number, Terminal, Gate, and Seat (only the keys present; empty slots are hidden and the grid reflows).
- **Lodging:**
  - Title in `.title2.bold`, then `locationName`.
  - Two columns: **Check-in** (date + time, big in `.title3.monospacedDigit`) and **Check-out**, with "3 nights" between them.
  - Room type under that, when present.
  - During the stay, a line "Night 2 of 3" in `kindLodging`.
- **Transport:**
  - Mode symbol (per mode, design system section 5), then "{fromName} → {toName}" in `.title2.bold`.
  - Departure and arrival times, same treatment as flight but with the names at `.headline` instead of big codes.
  - Operator and Seat grid.
- **Activity / Food:**
  - Title `.title2.bold`, then `locationName`.
  - Time block: "Sat, Oct 3 · 20:30–22:30" (with zone badge rule).
  - Party size ("Table for 4" for food, "4 people" for activity) when present.
- **Note:**
  - Title `.title2.bold`, then date/time or "All day".
  - Notes rendered prominently (`.body`, no card title). Actions row usually empty and hidden.

**Toolbar:** Edit (not for viewers). Menu: **Copy Details** (a plain-text summary of title, times with zones, location, and code, suitable for pasting in a message), **Duplicate** (editors), **Delete** (editors, destructive).

**States:**
- *Item deleted remotely while open:* see section 5.6.
- *Offline:* Directions still opens Maps. Map snapshot may be blank (show a `surface2` placeholder with a `mappin.and.ellipse` symbol).

**Accessibility:** the header card is one element per logical group: "Departs JFK, New York, Thursday October 1, 10:30 PM Eastern time"; "Arrives LIS, Lisbon, Friday October 2, 9:45 AM Lisbon time"; "Duration 7 hours 15 minutes". The confirmation code is read character by character (`.speechSpellsOutCharacters`). Action buttons have full labels ("Get directions to JFK Terminal 1").

### 3.5 Add / Edit Item form

**Presentation:** sheet, `NavigationStack`, `Form`. Titles "New Flight" / "Edit Flight" etc.

**Step 1: Kind picker** (Add only, skipped when a kind was chosen from the `+` menu): a 2×3 grid of 100pt-tall tiles, each with the kind tint background, kind symbol 28pt, and label. Order: Flight, Lodging, Activity, Food, Transport, Note. Tap = selection haptic + push to the form. When editing, the kind shows as the first form row ("Type", a `Picker` menu). Changing it keeps the common fields and hides, but doesn't delete until save, the old kind's `details` keys.

**Common fields** (all kinds, in this order, with kind-specific sections inserted where noted):

1. **Title** (required). Placeholder per kind: flight "e.g. TP 202 to Lisbon", lodging "e.g. Memmo Alfama", activity "e.g. Tram 28 tour", food "e.g. Dinner at Taberna", transport "e.g. Train to Porto", note "e.g. Pick up SIM card".
   - **Flight auto-title:** if the title is empty when saving and airline/flight number/codes exist, the title becomes "{flightNumber} {fromCode} → {toCode}".
2. *[Kind-specific section: see below]*
3. **When**
   - All day toggle (all kinds. Default on for note, off otherwise. Hidden for flight and transport.)
   - Start: `DatePicker` (date + time; date only if all day). **The picker edits wall-clock time in the start time zone**, so its displayed zone is `startTimeZone` (set the picker's environment `\.timeZone`).
   - Start time zone row: "Time Zone · Lisbon" → Time Zone Picker (same component as 3.2). Default: the trip's zone. Auto-filled from location search (below).
   - End (optional for all kinds except lodging, where it's required and labelled "Check-out"): an "Add end time" button that reveals the End picker (edited in `endTimeZone ?? startTimeZone`). For flight and transport, the End row is labelled "Arrives" and has its own time zone row ("Arrival time zone"). Other kinds don't show an end zone row (it stays null).
   - Labels by kind: flight "Departs" / "Arrives"; lodging "Check-in" / "Check-out"; transport "Departs" / "Arrives"; others "Starts" / "Ends".
   - Defaults on Add: the selected day (if launched from a day's Add) or the trip's start date, at 09:00 (lodging check-in 15:00, check-out next day 11:00; food 19:30).
   - Validation: end must be after start as an instant (not wall clock). Error text under the row: "Arrival must be after departure." Save is disabled.
4. **Location**: a row showing `locationName` or "Add Location" that pushes **Location Search** (below). Flight label: "Departure Airport". Transport: "Departure Station / Stop". If a location is set, the row shows name + address and has a clear button (`xmark.circle.fill`).
5. **Confirmation code**: `TextField`, `.monospaced`, autocapitalization characters, autocorrection off. Placeholder "e.g. ABC123". Hidden for note.
6. **Reminder**: `Picker` (menu style) labelled "Reminder": None, At time of event, 5 min, 15 min, 30 min, 1 hour, 2 hours, 3 hours, 1 day, 2 days before (stored as 0, 5, 15, 30, 60, 120, 180, 1440, 2880 minutes).
   - Defaults on Add: flight 180, transport 60, activity 60, food 60, lodging none, note none.
   - For lodging, the reminder is relative to check-in.
   - If system notifications are denied or not yet allowed, a row below it reads `bell.slash` "Notifications are off", with a **Turn On** button (priming moment B if not determined, otherwise opens iOS Settings).
7. **Notes**: multi-line `TextField`.
8. *(Edit only)* **Delete Item** destructive button.

**Kind-specific sections** (all map into `details` keys from the contract; empty fields are not stored):

| Kind | Section title | Fields (→ details key) |
|---|---|---|
| flight | Flight | Airline (`airline`), Flight number (`flightNumber`, uppercase, monospaced), From (`fromCode`, 3-letter IATA, uppercase), To (`toCode`), Terminal (`terminal`), Gate (`gate`), Seat (`seat`) · also an **Arrival Airport** search row that only sets `endTimeZone` (and fills `toCode` if empty and the result name contains a 3-letter code in parentheses) |
| lodging | Stay | Room type (`roomType`), Phone (`phone`, `.telephoneNumber` keyboard), Check-in time note (`checkInTime`, free text like "from 15:00"), Check-out time note (`checkOutTime`) |
| transport | Journey | Mode (`mode`, segmented-style menu: Train, Bus, Car, Ferry, Rideshare, Other; default Train), Operator (`operator`), From (`fromName`), To (`toName`), Seat (`seat`) · also an **Arrival** search row that sets `endTimeZone` and fills `toName` |
| activity | Booking | Phone (`phone`), Website (`website`, URL keyboard), Booking link (`bookingUrl`), Party size (`partySize`, Stepper 1–20, stored as string) |
| food | Reservation | Same as activity |
| note | none | none (no location or confirmation code rows, but location is available under a "More" disclosure) |

**Location Search** (pushed view):
- `.searchable` with prompt "Search places" (flight: "Search airports", e.g. "JFK" or "Lisbon airport"), active on appear.
- Results from `MKLocalSearchCompleter`, with the region biased to the trip destination (or the current start-zone location when known). Rows: title + subtitle. For flight, the query gets " airport" appended internally when it's 3 letters or fewer, and `pointOfInterestFilter` includes `.airport`.
- Selecting a row runs `MKLocalSearch` for the completion and sets `locationName` = mapItem.name, `address` = formatted postal address, and `latitude`/`longitude`. **It also sets `startTimeZone` = mapItem.timeZone** when that exists and the user hasn't manually picked a start zone in this editing session. A toast confirms: "Time zone set to Lisbon".
- First row when there's typed text: "Use "{text}" without a map location" (sets only `locationName`).
- *Offline:* the list shows "Place search needs a connection. You can type a name now and add the map location later." with the same "Use "{text}"" row.
- *No results:* "No places found for "{text}"".

**Save behavior:** writes to SwiftData immediately (with a new client UUID on Add), schedules or updates the local reminder, dismisses with a `.success` haptic, and the timeline scrolls to the new item and highlights it (a 1s background flash in the kind tint, or no flash under Reduce Motion). Sync happens in the background.

**Accessibility:** every field has a visible label (no placeholder-only fields). Error messages are announced (`AccessibilityNotification.Announcement`). Kind tiles read "Flight, button". The time zone rows read "Start time zone, Lisbon, GMT plus 1".

### 3.6 Share & Members sheet

**Opens from:** the people button in Trip Detail, Info → See All & Invite, and trip context menus. `.presentationDetents([.medium, .large])`.

**Layout** (`List`, inset grouped), title "Share Trip":
1. **Invite section** (owner and editors only; viewers see the members list only):
   - Header "Invite people".
   - Role picker (segmented): **Can edit** (`editor`) | **View only** (`viewer`). Default: Can edit. Footer changes with the selection: "Editors can add, change and delete plans and invite others." / "Viewers can see everything but can't make changes."
   - **Create Invite Link** button (borderedProminent, full width, `link`). It calls `POST /invites`, shows a spinner in the button, and on success replaces itself with:
     - An invite card: the code in `.title.monospaced.bold`, spaced as "AB12 CD34", with the caption "Expires Sat, Oct 4 · {role label}".
     - `ShareLink` **Share Invite…** with message text: "Join my trip "{title}" on Wayfare: {url}  (or open Wayfare → + → Join with Code and enter {code}). Expires {date}."
     - **Copy Code** button.
   - Changing the role after creating a link clears the card, so a new link must be created for the other role.
   - Offline: the button is disabled with the footer "Creating an invite needs a connection."
2. **Members** section, header "{n} people":
   - Owner first, then editors, then viewers, alphabetical within each role. "You" is suffixed "(You)".
   - Row: 36pt initials avatar (trip color background, white initials), name (`.body`), role (`.subheadline`, `textSecondary`) with a role symbol: owner `crown.fill`, editor `pencil`, viewer `eye`.
   - **Owner** can swipe or use the context menu on any other member for **Remove from Trip** (confirmation: "Remove {name}? They'll lose access to "{title}" right away.").
   - **Any non-owner** sees on their own row a context menu / swipe **Leave Trip**.
   - **No role changes in v1** (the contract has no endpoint). Footer for owners: "To change someone's role, remove them and send a new invite."
3. **Pending changes note** (if the trip has unsynced local changes): "Some of your changes haven't synced yet. Invitees will see them once you're online."

**States:** *Loading invite* spinner. *Error* inline red text under the button: "Couldn't create an invite. Try again." (or, for `forbidden`, "Only editors and the owner can invite people.").

**Accessibility:** the code is announced spelled out. Member rows read "Sam, editor". The remove action is a custom action.

### 3.7 Accept Invite (deep link + Join with Code)

**Entry points:**
- `wayfare://invite/<code>` opened from anywhere (Messages, Mail, Notes, Safari).
- Trips List `+` → **Join with Code**: a medium sheet with one monospaced `TextField` (8 chars, auto-uppercase, ignores spaces and hyphens, paste-friendly), and a **Join** button enabled when 8 characters are entered.

**Flow:**
1. **Signed out:** hold the code, show the Welcome screen with the invite card (section 2.1). After sign-in, continue at step 2.
2. **Signed in:** present the **Joining** sheet (medium detent) with a spinner and "Joining trip…". Call `POST /v1/invites/:code/accept`.
3. **Success (200 Trip):** the sheet transitions to a confirmation: large cover tile, "You're in!", trip title, dates, and **Open Trip** (primary). Save the returned trip locally, then sync immediately (`since` = current cursor) to pull items and members. Open Trip → dismiss, pop to root, push Trip Detail. Then run priming moment C if eligible.
   - Already a member (idempotent): same screen with "You're already on this trip".
4. **404 (unknown or expired):** icon `link.badge.plus` in `textSecondary` (or `exclamationmark.triangle`), title "This invite has expired or isn't valid", body "Ask {the sender} for a new link. Invites last 7 days." Buttons: **Enter a Code** (opens Join with Code) and **Close**.
5. **Offline:** "Joining a trip needs a connection. We'll keep this invite and try again when you're online." The code is kept and retried automatically on reconnect, with a local toast on success.

**Accessibility:** status changes are announced. The code field is labelled "Invite code, 8 characters".

### 3.8 AI Import flow

**Entry:** Trip Detail `+` → **Import from Email…**, or the empty-trip button. Owner and editors only. Presented as a large sheet with its own `NavigationStack`.

**Step 0: One-time AI consent** (required by the contract, Guideline 5.1.2)
- Shown instead of Step 1 the first time a user opens Import on this device (flag stored locally, per user id). It is also re-shown after sign-out.
- Content: `sparkles` 48pt (hierarchical, `accent`), title "Import with AI", body: "Pasted text is sent to Anthropic to extract your plans. Wayfare's server passes it to Anthropic's Claude, which returns draft plans for you to review. Only paste text you're comfortable sharing, and remove anything you don't need, like payment details." A "Learn more" link opens the Privacy Policy.
- Buttons: **Agree & Continue** (borderedProminent) → stores consent and goes to Step 1; **Not Now** → dismisses the whole sheet. No import request is ever made without this consent.
- Settings → About gains a row **AI Import Consent**: "Given" / "Not given", with **Withdraw** (clears the flag, so the next import asks again).

**Step 1: Paste**
- Title "Import Plans", Cancel leading.
- Explainer (`.subheadline`, `textSecondary`): "Paste a booking confirmation (flight, hotel, restaurant, tickets). Wayfare will draft the plans for you to review. Nothing is added until you say so."
- A SwiftUI `PasteButton` (payload `String`, so there's no paste-permission alert) labelled "Paste", above a `TextEditor` (min height 240pt, `surface` background, radius 12, `.body` font, placeholder "Or type/paste here…" drawn as an overlay).
- Character counter under the editor, trailing: "3,420 / 20,000" (`.caption.monospacedDigit`). It turns `danger` above 20,000, and Continue is disabled.
- Privacy footnote with `lock.fill`: "The text is sent to Wayfare's server and processed by Anthropic's Claude to find your plans."
- Primary bottom button (safe-area inset): **Find Plans** (`sparkles`), disabled when the text is empty, over the limit, or offline (footer "Import needs a connection").

**Step 2: Loading**
- Replaces the content in place. It shows the `sparkles` symbol with a pulsing `symbolEffect(.pulse)` (static under Reduce Motion), "Reading your confirmation…", and after 6s the second line "This can take up to 30 seconds."
- **Cancel** cancels the request and returns to Step 1 with the text intact.
- Timeout at 45s → error state.

**Step 3: Review drafts**
- Title "Review {n} Plans". Header text: "Check the details. Uncheck anything you don't want."
- `List` of draft rows. Each row: a leading checkbox (`checkmark.circle.fill` in `accent` / `circle` in `textSecondary`, 44pt hit area, default **checked**), kind chip, title, and a date/time line in the item's own zone. **Unlike the timeline, the zone abbreviation is always shown on drafts** (e.g. "Thu, Oct 1 · 22:30 EDT → Fri, Oct 2 · 09:45 WEST"), because AI extraction errors in dates and zones are the costliest mistake.
- **Warnings** under a row, in `warning` with `exclamationmark.triangle.fill`:
  - "Outside trip dates (Oct 12)" if the start falls outside the trip range in the trip zone.
  - "Possible duplicate of "{existing title}"" if an existing item has the same kind and `confirmationCode`, or the same kind with a start within 5 minutes and a matching title prefix. **Duplicates default to unchecked.**
  - "Check the time zone" if the draft's `startTimeZone` is missing or invalid (the app falls back to the trip zone and flags it).
  - "Check-out missing" for a lodging draft with no `endAt`; "Arrival time missing" for a flight draft with no `endAt`.
  - Since the API returns no confidence scores, these heuristic warnings are our "low-confidence" highlight. A warned row also tints its date/time line in `warning`.
- Tap a row → push the **Item form** (section 3.5) pre-filled with the draft, in "draft" mode. The toolbar button is "Done" instead of Save, and editing only updates the draft in memory.
- Footer: "Nothing here? Try pasting the full email, including dates."
- Bottom button: **Add {k} Plans** (disabled at k = 0). It writes the checked drafts locally with new UUIDs, the trip id, and `sortIndex` appended, schedules reminders, queues sync, dismisses with a `.success` haptic, then shows a toast in Trip Detail: "Added 3 plans". The timeline scrolls to the earliest added item.
- Back/Cancel while on Review: confirmation "Discard these drafts?".

**Error states:**
- *0 drafts returned:* `ContentUnavailableView`, symbol `doc.text.magnifyingglass`, "No plans found", "We couldn't find bookings in that text. Try pasting the whole confirmation email." Button: **Edit Text** (back to Step 1).
- *429 `rate_limited`:* "You've reached today's import limit (30). You can still add plans by hand, and imports reset tomorrow." Button: **Add Manually**.
- *403 `forbidden`:* "You have view-only access to this trip."
- *Network / 5xx / timeout:* "Import didn't finish. Your text is still here." Button: **Try Again**.

**Accessibility:** the checkbox state is exposed as the `.isSelected` trait, and the row label reads "Flight, TP 202 JFK to Lisbon, October 1, 10:30 PM Eastern, selected". Toggling is done with a double-tap on the row's checkbox or the custom action "Toggle include". The loading state is announced.

### 3.9 Settings sheet

**Opens from:** the avatar button on the Trips List. Large sheet, `NavigationStack`, title "Settings", **Done** trailing.

**Sections** (`Form`):
1. **Account**
   - Header row: 56pt avatar (initials on `accent`), display name (`.headline`), email (`.subheadline`, `textSecondary`; "Hidden by Apple" if it's a private relay address, shown as-is).
   - **Name**: tappable, pushes an edit field (`PATCH /v1/me`, needs a connection; offline disables with a footer note).
2. **Notifications**
   - If system authorization is `.denied`: a top row `bell.slash.fill` "Notifications are off for Wayfare" + **Open Settings** (opens `UIApplication.openNotificationSettingsURLString`). All toggles below are disabled and dimmed.
   - If `.notDetermined`: row **Turn On Notifications** (runs the priming card).
   - **Morning briefing** toggle. Footer: "A summary of the day's plans each morning while you're on a trip."
   - **Briefing time**: shown only when briefing is on. A `Picker` (menu) with hours 5 AM to 11 AM, formatted per locale ("7:00" / "7:00 AM"). Default 7. Note: the contract's `briefingHour` accepts 0–23, but we deliberately offer only the morning range.
   - **Plan changes by others** toggle (`collabAlertsEnabled`). Footer: "When someone on a shared trip adds or changes a plan."
   - Footer for the section: "Plan reminders are set on each plan and work even offline."
   - Every change calls `PUT /v1/devices/current` (debounced 1s). If offline, it's saved locally and sent on reconnect.
3. **Sync**
   - "Last synced" value: relative time ("2 min ago") or "Never".
   - **Sync Now** button (spinner while running). If there are unsynced local changes: "{n} changes waiting to sync".
4. **About**: Version (build), Privacy Policy, Terms of Use, Contact Support (mailto).
5. **Developer** (shown only in Debug and TestFlight builds, never in App Store builds):
   - **Server URL**: `TextField`, URL keyboard, prefilled with the current `API_BASE_URL`.
   - **Test Connection** → `GET /v1/health`. The result is shown inline: `checkmark.circle.fill` "OK · API v1" in `success`, or the error in `danger`.
   - **Reset to Default**.
   - Changing the URL and tapping **Apply** shows an alert: "Switching servers signs you out and clears local data on this device." Buttons: Switch & Sign Out / Cancel.
6. **Sign Out** (centered, `accent` text):
   - Confirmation dialog "Sign out of Wayfare?". If unsynced changes exist and you're offline, the message reads: "{n} changes haven't synced and will be lost. Connect to the internet first to keep them." Buttons: **Sign Out** (destructive) / Cancel.
   - Sign-out calls `POST /v1/auth/logout` (best effort), clears the SwiftData store, token, and scheduled local notifications, and returns to Welcome.
7. **Delete Account** (centered, `danger` text), which pushes a **Delete Account** page:
   - Symbol `person.crop.circle.badge.xmark` 56pt `danger`.
   - Copy: "Deleting your account permanently removes: your trips and all their plans, including for anyone you shared them with; and you from trips other people shared with you. Wayfare will also be disconnected from your Apple ID. This can't be undone."
   - If the user owns shared trips, a list: "These shared trips will be deleted for everyone: Lisbon & Porto (3 people)".
   - Button **Delete Account** (borderedProminent, `danger` tint) → final alert "Delete your account?" with **Delete** (destructive) / Cancel → `DELETE /v1/me` → the same cleanup as sign-out → Welcome, with a one-time toast "Your account has been deleted."
   - Needs a connection. Offline: the button is disabled with an explanation.

**Accessibility:** all toggles have labels matching the visible text. The dimmed disabled state also announces "Notifications are off in iOS Settings" via the section's accessibility hint.

---

## 4. Notifications and deep links

### 4.1 Local item reminders (scheduled on device)

Identifier: `item-<itemId>`. Rescheduled whenever an item is saved locally **or received from sync** (collaborator edits update your reminders too), cancelled on delete or tombstone. We schedule only reminders whose fire date is in the future and within the next 60 days, capped at the 64 soonest across all trips (the iOS pending-notification limit; Wayfare schedules no other local notifications). Reschedule on each app foreground and each sync.

Fire time = `startAt − reminderMinutes`. Title = item title. Body by kind. Times are in the item's own zone, with the zone abbreviation appended when it differs from the device's current zone:

| Kind | Body |
|---|---|
| flight | "Departs {time} from {fromCode or locationName}{ · Terminal T}{ · Seat S}. Confirmation {code}." |
| lodging | "Check-in {time} at {locationName}. Confirmation {code}." |
| transport | "Departs {time} from {fromName or locationName}{ · Seat S}." |
| food | "Table{ for N} at {time}{ · locationName}." |
| activity | "Starts at {time}{ · locationName}." |
| note | First line of notes, or "{time}" if notes are empty. |

Omit empty segments cleanly (no stray "·"). When `reminderMinutes == 0`, prefix the body with "Now: ". Category `ITEM_REMINDER` with actions **Directions** (foreground, opens Maps) and **Copy Code** (foreground, only when a code exists). `threadIdentifier` = tripId, so notifications group per trip.

### 4.2 Server push copy (contract-defined; this is the style guide for the backend)

- **Collaborator change:** title = trip title (e.g. "Lisbon & Porto"). Body: "{name} added "{item title}"", or "{name} changed "{item title}"". When pushes are coalesced: "{name} made 3 changes". Fallback name "A trip member".
- **Daily briefing:** title "Today in {destination city or trip title}". Body: "{n} plans · first: {title} at {time}", or "1 plan: {title} at {time}", or "No plans today. Enjoy the free day." (the backend may choose to skip that case).

### 4.3 Tap behavior (deep link routing)

| Source | Payload | Behavior |
|---|---|---|
| Local reminder | `itemId`, `tripId` in `userInfo` | Pop to root → push trip (Timeline) → push Item Detail |
| Push `itemChanged` | `tripId`, `itemId` | Trigger sync first (show the trip immediately from local data, with a subtle "Updating…" in the nav bar), then push Item Detail once the item exists. If the item is missing after sync (deleted since), stay on the timeline and toast "That plan was removed." |
| Push `briefing` | `tripId`, `date` | Pop to root → push trip → Timeline scrolled to `date`'s section |
| `wayfare://invite/<code>` | code | Accept Invite flow (section 3.7) |
| Any payload whose trip is unknown after sync | | Stay on Trips list, toast "You no longer have access to that trip." |

If a form sheet with unsaved changes is open when a deep link arrives, don't discard it silently. Show the "Discard changes?" dialog first. If the user keeps editing, the deep link is dropped.

Foreground presentation: collaborator pushes show as a banner (`.banner, .list`, no sound). Briefings and reminders show as banner with sound.

---

## 5. Edge cases

### 5.1 Time zones, midnight and the date line
- **Storage is instants.** Display is always `startAt` in `startTimeZone` and `endAt` in `endTimeZone ?? startTimeZone`. Never display an item in the device zone.
- **Grouping is by trip zone** (section 3.3.1). A JFK 22:30 EDT departure on Oct 1 is 03:30 on Oct 2 in Lisbon, so it groups under **Oct 2**. It shows "22:30" with the badge "Oct 1 · EDT", so the traveler still sees the ticket time and date. (See open question Q1.)
- **Overnight / cross-midnight flights:** shown once, on the departure's trip-zone day, with the arrival suffix "+1". There's no second row on the arrival day.
- **Date line:** eastbound (e.g. SYD → LAX) can arrive "the day before". Show "−1". Westbound LAX → SYD shows "+2" when applicable. The suffix is always computed as the difference in local calendar dates (arrival zone vs departure zone), not as elapsed hours.
- **Duration** always comes from instants, never from wall-clock subtraction.
- **DST transitions:** pickers edit wall-clock time in the item zone. A nonexistent local time (spring-forward gap) is shifted forward by the system. We show the result without an error. For ambiguous fall-back times, the first occurrence is used.
- **Trip zone differs from the device zone** (the user is at home before the trip): "Today" and the Now/Next logic use real instants, and the "Today" section is determined by today's date **in the trip zone**.
- **Zone badge threshold:** compare UTC offsets at the item's instant, not identifiers (Europe/Lisbon vs Europe/London in October: same offset, no badge).
- **All-day items:** stored with `startAt` = local midnight in `startTimeZone` (default trip zone). They're grouped by their local date in that zone (not converted), so an all-day note never drifts to another day.

### 5.2 Items outside the trip dates
- Allowed (e.g. a pre-trip airport hotel). They appear in extra sections "Before trip · Wed, Sep 30" or "After trip · Sat, Oct 10" with a `warning` header, above or below the trip days.
- The Item form shows a non-blocking footer under When: "This is outside the trip dates (Oct 1–9)." with an **Extend Trip** button (editors). It updates the trip's start or end and saves both.
- The Trip form, on shortening dates, shows: "{n} plans will be outside the new dates. They'll stay in the timeline under Before/After trip."

### 5.3 Viewers (read-only UI)
- Hidden: `+` menu, Edit buttons, swipe actions, "Add" in empty days, Duplicate/Delete menu items, Invite section, trip Edit/Delete, AI import.
- Shown: all content, Directions, Call, Copy Code, Website, Copy Details, Share sheet (members list only), Leave Trip.
- An `eye` + "View only" capsule appears in the trip header under the dates. Tapping it shows a popover: "{owner} shared this trip with you as a viewer. Ask them for edit access."
- Reminders: viewers can't write `reminderMinutes` (it's a shared field on the item). **v1 decision:** reminders set by editors **do** fire on viewers' devices too, because local scheduling reads the synced field. Item Detail shows the reminder row read-only for viewers. See Q3.
- If a role downgrades to viewer while local edits are queued, the server returns 403. Revert the local copies to server state on next sync and show a one-time banner: "You now have view-only access to {title}. {n} unsynced changes were discarded."

### 5.4 Offline edits
- All create/edit/delete work offline and show the unsynced marker until acknowledged.
- The sync queue flushes on reconnect, app foreground, pull-to-refresh, and after each local save (if online).
- An item created offline in a trip created offline is sent trip-first (the client handles ordering. No UI).
- Features needing a network show inline explanations (sign-in, invites, accept, import, location search, name change, account deletion, developer server test). No modal error alerts for offline.

### 5.5 Conflicts (last write wins)
- No merge UI in v1. The server's latest write wins, and the timeline updates silently on sync.
- **Mitigation:** if a sync delivers a newer server version of an item that the user currently has open in an **Edit** form, show an inline banner at the top of the form: "Sam just changed this plan." with **Review** (reload the form with their version, discarding your unsaved edits after confirmation) or **Keep Mine** (your save will overwrite). No banner in Item Detail, which just refreshes in place with a 0.3s crossfade.
- Item Detail footer "Updated by Sam · just now" makes silent overwrites discoverable.

### 5.6 Deleted by another member
- **Item deleted (tombstone) while viewing Item Detail:** pop back to the timeline and toast "{name or "Someone"} deleted "{title}"." (The name comes from `updatedBy` if present on the tombstone; otherwise "This plan was deleted.")
- **Item deleted while it's open in an Edit form:** alert "This plan was deleted by someone else." Buttons: **Save as New** (re-creates it with a new id from the form contents) / **Discard**.
- **Trip deleted, or user removed from trip (trip tombstone):** if inside that trip, pop to root. Toast "{title} is no longer available." The trip disappears from the list, and its local reminders are cancelled.
- **Owner deleted their account:** same as trip tombstone.

### 5.7 Other
- **Very long titles:** 2 lines in the timeline, full title in Item Detail.
- **Missing data:** a flight without codes uses the title route layout; an item without a location has no Directions button; a lodging without `endAt` has no check-out row.
- **Many items in one day (>20):** no special handling. The List virtualizes.
- **Trip with 0 days** (start == end): one section, fine.
- **Sign-in token expired (`unauthorized` on sync):** keep local data. Show a sheet "Please sign in again" with the Apple button. On success, resume sync without data loss. Only if a *different* Apple account signs in, clear local data first (with a warning).

---

## 6. Open questions for the owner

1. **Day grouping for late-night departures.** We group by the trip's time zone (as briefed), so a 22:30 JFK departure on Oct 1 appears under **Oct 2** with an "Oct 1 · EDT" badge. The alternative is to group each item by its own local date (it would appear under Oct 1, matching the ticket). Keep trip-zone grouping?
2. **Invite links.** `wayfare://invite/…` links aren't reliably tappable in all messaging apps, and do nothing for people who don't have the app. Do you want universal links (`https://wayfare.app/i/<code>`, needs a domain and a small landing page) for v1, or is "custom link + typed code" fine for launch?
3. **Reminders are shared.** `reminderMinutes` lives on the item, so if Sam sets "3 hours before", every member (viewers included) gets that reminder, and one person's change affects everyone. OK for v1, or should reminders be personal (needs a contract change: per-user reminder rows)?
4. **Role changes.** With no endpoint to change a member's role, owners must remove and re-invite. Acceptable for v1?
5. **Pasted email text retention.** Our import copy promises the text is processed to find plans. Can we also promise "not stored"? That needs the backend not to log request bodies. Confirm, and we'll add it to the copy and privacy label.
6. **Briefing hour range.** We offer 5–11 AM only. Anyone wanting an evening "tomorrow" briefing would need a different payload. Morning-only for v1?
