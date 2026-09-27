# Wayfare Design System v1

Owner: Visual / Brand Designer. Consumed by: iOS Engineer (tokens go into the asset catalog as named Color Sets with Any/Dark appearances), UX spec `company/02-ux-spec.md`.

All hex values below are final. Copy them verbatim. Contrast ratios were computed with the WCAG 2.1 relative-luminance formula.

---

## 1. Brand personality

**Calm · Capable · Warm**

- **Calm:** travel is stressful, and the app is the one quiet thing in your pocket. Warm off-white paper backgrounds, generous spacing, one accent color, no gradients on content, no confetti.
- **Capable:** it looks like a well-made boarding pass. Codes and times are set big, monospaced and precise. Information density goes up only where it helps at a counter (item detail), never in lists.
- **Warm:** rounded SF for headings, emoji trip covers, friendly plain-language copy ("Nothing planned", "You're in!").

**Rationale.** We stay close to stock iOS (system fonts, inset grouped lists, materials) so the app feels native, respects every accessibility setting for free, and ages well with iOS updates. Brand character comes from three things only: the **Lagoon teal accent**, the **warm paper background**, and the **six kind colors** that make a day scannable at a glance. The kind colors are chosen as distinct hues (blue, violet, green, vermilion, amber, slate) so they stay distinguishable for the common color-vision deficiencies. Every kind also has its own symbol, so color is never the only signal.

---

## 2. Color tokens

Create each as a Color Set in `Assets.xcassets/Colors/` with the exact token name. "Any" = light, "Dark" = dark appearance. Don't use opacity on text colors. The tint tokens are pre-blended solid colors, so contrast stays predictable.

### 2.1 Core

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#F6F4EF` | `#0F1115` | Screen background, grouped list background |
| `surface` | `#FFFFFF` | `#1A1D23` | Cards, list rows, sheets' content rows |
| `surface2` | `#EFECE5` | `#252932` | Secondary fills: badges, text editor, placeholders, offline banner |
| `textPrimary` | `#1A1D21` | `#F2F0EB` | Titles, body |
| `textSecondary` | `#5B626C` | `#A2A8B2` | Subtitles, metadata, captions |
| `accent` | `#0A6B7C` | `#4EC3D4` | Tint color (app `AccentColor`), links, selected states, Now pill |
| `accentTint` | `#E2EDEF` | `#233B43` | Next pill background, selected chip fills |
| `onAccent` | `#FFFFFF` | `#0F1115` | Text/icons placed on `accent` |
| `separator` | `#E3DED6` | `#2E333B` | Hairlines, timeline rail (decorative, not text) |
| `success` | `#0D7550` | `#4FCB93` | Confirmations, "OK" states |
| `warning` | `#8F5A00` | `#EDB24C` | Out-of-range dates, draft warnings |
| `danger` | `#C0282D` | `#FF6B6B` | Destructive labels, errors |

Set the asset catalog's `AccentColor` to the `accent` values. Destructive buttons use `role: .destructive` (system red). `danger` is for our own error text and icons.

### 2.2 Item kinds

Each kind has a foreground color (symbols, labels, "+1" suffix, map pins) and a tint (chip and band backgrounds). The foreground on its tint passes AA (≥4.5:1) in both modes.

| Token | Light | Dark | Tint token | Tint light | Tint dark |
|---|---|---|---|---|---|
| `kindFlight` | `#1E5FCC` | `#77A6FF` | `kindFlightTint` | `#E4ECF9` | `#2B364B` |
| `kindLodging` | `#7045B8` | `#B895F6` | `kindLodgingTint` | `#EEE9F6` | `#363349` |
| `kindActivity` | `#0D7550` | `#4FCB93` | `kindActivityTint` | `#E2EEEA` | `#243C37` |
| `kindFood` | `#B8431A` | `#FF8F66` | `kindFoodTint` | `#F6E8E4` | `#43322F` |
| `kindTransport` | `#935400` | `#EDB24C` | `kindTransportTint` | `#F2EAE0` | `#40382A` |
| `kindNote` | `#5C6675` | `#A7B1BF` | `kindNoteTint` | `#EBEDEE` | `#33383F` |

**Map pins** use the kind color as the fill with a **white** symbol in both modes, since pins sit on map tiles, not on our backgrounds. White on the light kind colors is ≥5.4:1. In dark mode, still use the *light* kind hex for pin fills so white symbols stay legible.

### 2.3 Contrast verification (WCAG 2.1)

Minimum ratios measured (AA body text = 4.5:1):

| Foreground | on `background` | on `surface` | on `surface2` |
|---|---|---|---|
| Light `textPrimary` | 15.39 | 16.91 | 14.34 |
| Light `textSecondary` | 5.61 | 6.16 | 5.22 |
| Light `accent` | 5.61 | 6.16 | 5.22 |
| Light kinds (lowest = `kindFood`) | 4.95 | 5.45 | 4.62 |
| Light `success` / `warning` / `danger` | 5.20 / 5.26 / 5.33 | 5.71 / 5.78 / 5.86 | 4.84 / 4.90 / 4.97 |
| Dark `textPrimary` | 16.59 | 14.82 | 12.79 |
| Dark `textSecondary` | 7.90 | 7.06 | 6.09 |
| Dark `accent` | 9.07 | 8.10 | 6.99 |
| Dark kinds (lowest = `kindLodging`/`kindFlight`) | 7.80 | 6.97 | 6.01 |
| Dark `danger` | 6.81 | 6.08 | 5.25 |

Kind color on its own tint: light 4.56 (food) to 5.45 (lodging); dark 5.01 (flight) to 6.09 (transport). `onAccent` on `accent`: light 6.16, dark 9.07.

**Increase Contrast:** add High Contrast variants in the asset catalog for `textSecondary` (light `#454B53`, dark `#C4C9D0`) and `separator` (light `#C9C3B8`, dark `#4A505A`). All other tokens already exceed AA.

---

## 3. Typography

System fonts only (SF Pro, SF Pro Rounded, SF Mono through `.monospaced`). **Always use Dynamic Type text styles**. No fixed point sizes for text. Never cap Dynamic Type below `.accessibility3`. Allow layouts to reflow (the UX spec defines the accessibility-size layouts).

| Element | Text style | Design / weight | Notes |
|---|---|---|---|
| Screen large titles ("Trips", trip name) | `.largeTitle` | `.rounded`, `.bold` | Set via navigation bar appearance (rounded large-title font descriptor) |
| Hero card trip title | `.title2` | `.rounded`, `.bold` | |
| Sheet / priming titles | `.title2` | default, `.bold` | |
| Item Detail title (non-flight) | `.title2` | default, `.bold` | |
| Flight route codes (JFK / LIS) | `.largeTitle` | `.monospaced`, `.bold` | `.kerning(1)` |
| Confirmation code (detail) | `.title2` | `.monospaced`, `.bold` | `.tracking(2)`, `.textSelection(.enabled)` |
| Invite code | `.title` | `.monospaced`, `.bold` | Display as "AB12 CD34" |
| Detail big times (departs / check-in) | `.title3` | `.semibold`, `.monospacedDigit()` | |
| Day section header date | `.headline` | default | "Thu, Oct 1" |
| Day section "Day N" | `.subheadline` | default, `textSecondary` | |
| Timeline row title | `.body` | `.semibold` | 2 lines max |
| Timeline row subtitle | `.subheadline` | default, `textSecondary` | 1 line |
| Timeline start time | `.subheadline` | `.semibold`, `.monospacedDigit()` | |
| Timeline end time | `.caption` | `.monospacedDigit()`, `textSecondary` | |
| Zone badge / day offset | `.caption2` | `.monospacedDigit()` (offset: `.bold`) | |
| Pills (Now / Next / Today) | `.caption` | `.bold` | Uppercase **not** used, sentence case |
| Kind label in detail header ("FLIGHT") | `.caption` | `.bold`, `.textCase(.uppercase)`, `.tracking(0.8)` | The only uppercase text in the app |
| Trip row title | `.headline` | default | |
| Countdown chip ("in 12 days") | `.caption` | `.semibold`, `.monospacedDigit()` | |
| Form labels, list body | `.body` | default | |
| Footers, meta ("Updated by Sam") | `.footnote` | default, `textSecondary` | |
| Character counter | `.caption` | `.monospacedDigit()` | |
| Empty-state title | system (`ContentUnavailableView`) | | |

**Rules**
- **Every** time, date number, duration, count, countdown and code uses `.monospacedDigit()` (or `.monospaced` for codes) so columns don't jitter as times update.
- `.rounded` is reserved for brand moments: large titles, the hero trip title, and the Welcome wordmark. Body copy stays default SF Pro for legibility.
- Line limits: titles 2, subtitles 1, everything in detail views unlimited.
- Time formatting is locale-driven (12/24h). Never hard-code "HH:mm".

---

## 4. SF Symbols (SF Symbols 5, iOS 17)

Default rendering: `.symbolRenderingMode(.monochrome)`, `.fontWeight(.semibold)` inside chips. Use `.hierarchical` only for 48pt+ empty-state and priming illustrations.

### 4.1 Item kinds

| Kind | Symbol | Filled variant used in chips/pins |
|---|---|---|
| flight | `airplane` | `airplane` (no fill variant; it's already solid) |
| lodging | `bed.double` | `bed.double.fill` |
| activity | `ticket` | `ticket.fill` |
| food | `fork.knife` | `fork.knife` |
| transport | `tram` | `tram.fill` (default; see modes) |
| note | `note.text` | `note.text` |

Transport modes (`details.mode`): train `tram.fill`, bus `bus.fill`, car `car.fill`, ferry `ferry.fill`, rideshare `car.side.fill`, other `arrow.left.arrow.right`.
Flight detail extras: `airplane.departure`, `airplane.arrival`.

### 4.2 Actions and UI

| Purpose | Symbol |
|---|---|
| Add (menus, empty day) | `plus`, `plus.circle` |
| New trip empty state | `suitcase.rolling.fill` |
| Empty timeline | `calendar.badge.plus` |
| Welcome value rows | `calendar.day.timeline.left`, `wifi.slash`, `person.2.fill` |
| Share / members button | `person.2.fill` |
| Share sheet (system) | `square.and.arrow.up` |
| Invite link | `link` |
| Invite (sign-in card) | `envelope.open.fill` |
| Invalid invite | `exclamationmark.triangle` |
| Roles: owner / editor / viewer | `crown.fill` / `pencil` / `eye` |
| Edit | `pencil` |
| Delete | `trash` |
| Leave trip | `rectangle.portrait.and.arrow.right` |
| More menu | `ellipsis.circle` |
| Duplicate | `plus.square.on.square` |
| Directions | `arrow.triangle.turn.up.right.diamond.fill` |
| Call | `phone.fill` |
| Copy code | `doc.on.doc` |
| Website / booking | `safari` |
| Location placeholder | `mappin.and.ellipse` |
| Map tab list fallback | `list.bullet` |
| AI import | `sparkles` |
| Import — no results | `doc.text.magnifyingglass` |
| Privacy note | `lock.fill` |
| Checkbox on / off | `checkmark.circle.fill` / `circle` |
| Reminder set | `bell.fill` |
| Notifications priming | `bell.badge.fill` |
| Notifications off | `bell.slash`, `bell.slash.fill` |
| Offline | `wifi.slash` |
| Unsynced / sync | `arrow.triangle.2.circlepath` |
| Warning | `exclamationmark.triangle.fill` |
| Success | `checkmark.circle.fill` |
| Time zone row | `globe` |
| Clear field | `xmark.circle.fill` |
| Settings (inside sheet header) | `gearshape` |
| Delete account | `person.crop.circle.badge.xmark` |
| Selected swatch | `checkmark` |

---

## 5. Layout, spacing, shape

### 5.1 Spacing scale (pt)

`xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 20 · xxl 24 · xxxl 32 · huge 48`

- Screen horizontal margins: rely on system list insets. Custom scroll views use **20**.
- Card inner padding: **16** (rows), **20** (detail header card).
- Vertical gap between cards/sections in custom scroll views: **16**.
- Timeline row: vertical padding **10**, gap between chip and content **12**, time column to rail gap **8**.
- Minimum hit target: **44×44** everywhere (checkboxes, swatches, chips).
- Use `@ScaledMetric` for chip sizes (32pt base), cover tiles, and avatar sizes so they grow with Dynamic Type.

### 5.2 Corner radii (all `RoundedRectangle(cornerRadius:style: .continuous)`)

| Radius | Use |
|---|---|
| 6 | Zone badge, tiny tags |
| 10 | Staying band, text fields in custom views |
| 12 | Buttons (Sign in, primary full-width), text editor |
| 14 | Action row buttons |
| 16 | Cards, cover tiles ≤ 64pt, map snapshot |
| 20 | Detail header card, map selection card |
| 22 | App-icon-like artwork on Welcome (96pt) |
| Capsule | Pills, chips, countdown, Today button, day selector |

### 5.3 Cards

- Fill `surface`. Border: none in light mode, 1pt `separator` stroke in dark mode (dark surfaces need edge definition).
- Shadow (light mode only): `color: #1A1D21 @ 6% opacity, radius 12, x 0, y 4`. No shadow in dark mode.
- No nested cards. A card inside a card becomes a `surface2` fill section instead.

### 5.4 Lists

- `List` with `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)` over `background`, and rows on `surface` (`.listRowBackground`).
- Timeline uses `.listStyle(.plain)` with section headers on `background` (sticky), and `.listRowSeparator(.hidden)` since the rail replaces separators. Row insets: leading 16, trailing 16.
- Swipe action tints: Edit `accent`, Delete via `role: .destructive`, Leave via `role: .destructive`.

### 5.5 Pills and badges

| Pill | Background | Text |
|---|---|---|
| Now | `accent` | `onAccent` |
| Next | `accentTint` | `accent` |
| Today (section header) | `accent` | `onAccent` |
| Zone badge | `surface2` | `textSecondary` |
| View only | `surface2` | `textSecondary` + `eye` |
| Countdown | `accentTint` | `accent` |
| Outside trip dates header | none | `warning` |

Padding: horizontal 8, vertical 3.

### 5.6 Haptics (`.sensoryFeedback`, iOS 17)

| Event | Feedback |
|---|---|
| Kind tile tapped, segment change, day chip, swatch, checkbox toggle | `.selection` |
| Item / trip saved, import added, invite created, joined trip, notifications granted | `.success` |
| Code copied | `.impact(weight: .light)` |
| Destructive confirmation shown (delete/leave) | `.warning` |
| Any failed request surfaced inline | `.error` |
| Pull-to-refresh | none (system) |

No haptics on scroll, on appearing Now/Next, or on background sync.

---

## 6. Motion

- **Default curve:** `.snappy` (duration 0.3) for state changes; `.smooth` (0.35) for layout changes. No bounce except the map pin selection (`.bouncy`, extraBounce 0).
- **Allowed motion:** segment transitions (crossfade 0.2s), map camera moves (0.5s), pin select scale 30→36pt, new-item highlight flash (kind tint background fades out over 1.0s), `sparkles` `.symbolEffect(.pulse)` during import, `.contentTransition(.numericText())` on countdowns and character counters, checkbox `.symbolEffect(.bounce)` on toggle.
- **Never:** parallax, auto-playing loops outside loading, animated gradients, full-screen transitions other than system push/sheet.
- **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): map camera changes jump without animation; pin scale and checkbox bounce off; pulse replaced with a static symbol + `ProgressView`; new-item flash replaced by a static 2pt `accent` leading bar for 2s; crossfades remain (≤0.2s opacity only is acceptable).
- **Reduce Transparency:** replace `.regularMaterial` overlays (map chips, map card) with solid `surface`.

---

## 7. Trip cover system

A cover = **one emoji** (`coverEmoji`) on **one color** (`colorHex`). It's rendered as a rounded-square tile: the color fill, the emoji centered at 55% of tile height, no border. Sizes: 44 (row), 64 (hero), 88 (form preview), 36 (member avatars use the color only, with white initials).

### 7.1 Cover palette (stored in `colorHex`; identical in light and dark)

All pass ≥5.3:1 against white, so white initials and text overlaid on a cover are AA.

| Name | Hex |
|---|---|
| Lagoon (default) | `#0A6B7C` |
| Sky | `#1E5FCC` |
| Indigo | `#4B47C4` |
| Violet | `#7045B8` |
| Bougainvillea | `#A8326E` |
| Chili | `#C0282D` |
| Terracotta | `#B8431A` |
| Saffron | `#8A5A00` |
| Olive | `#2F7A36` |
| Jade | `#0D7550` |
| Slate | `#3C4A5C` |
| Cocoa | `#6B4F3A` |

Picker order is the table order (6 per row, 2 rows). If a synced trip has a `colorHex` outside this palette (another client or the backend), render it as-is. If the hex is unparsable, fall back to Lagoon.

### 7.2 Emoji rules

- Default emoji: ✈️.
- When a destination is picked from search and the placemark has an `isoCountryCode`, suggest that country's flag emoji (built from regional indicator symbols) unless the user already chose one.
- Quick-pick row above the emoji field (tap to set): ✈️ 🏖️ 🏔️ 🏙️ 🗺️ 🎒 🚆 🚗 ⛺️ 🍷 🎿 ❤️.
- Exactly one grapheme cluster. Reject text.
- In dark mode the tile keeps its color. Emoji needs no treatment.

### 7.3 Where the trip color appears
Cover tiles, member avatars, the hero card progress bar, and a 3pt top edge on the Trip Detail header on iPad-width layouts. **Never** for text, and never replacing `accent` for interactive controls.

---

## 8. App icon brief

**For:** a human illustrator or an image-generation model. Deliver a 1024×1024 master, no transparency, no text. Follow iOS 18 icon guidance: provide Any, Dark and Tinted variants.

**Concept, "The Folded Route":** a single stylized route line, drawn as a smooth S-curve path that ends in a small location dot. It sits on a warm Lagoon teal field, and the path reads simultaneously as a road on a map, a flight path, and a gentle "W". The curve is made of one thick stroke (about 9% of the icon width) in warm off-white `#F6F4EF`, with round caps. The start of the path has a small hollow circle (origin) and the end has a solid circle (destination) in Saffron-light `#EDB24C`. The background is a subtle vertical gradient from `#0E7F92` (top) to `#0A6B7C` (bottom). That gradient is the only one in the brand. Flat, geometric, no shadows except a very soft inner vignette. It must read at 29pt: path and dot only, no extra detail.

- **Dark variant:** background `#0F1115` to `#1A1D23`, path `#4EC3D4`, destination dot `#EDB24C`.
- **Tinted variant:** a grayscale path on black, so the system tints it.

**Alternate A, "Boarding Stub":** a rounded ticket stub rotated −12°, in off-white `#F6F4EF` on a Lagoon background. It has a perforated edge on the left (5 punched circles) and a small `airplane` silhouette plus a dotted line printed on the stub in Lagoon `#0A6B7C`. It feels more literal and travel-agency.

**Alternate B, "Sunrise Pin":** a map pin shape whose round head is a half sun rising over a horizon line. The pin is Terracotta `#B8431A`, the sun is Saffron `#EDB24C`, and the background is warm paper `#F6F4EF` with a thin Lagoon horizon. It's warmer, lighter, and stands out on dark home screens, but weaker in tinted mode.

Designer recommendation: primary concept. It owns our accent color, is abstract enough to trademark, and survives tinting.

**Don'ts:** no globe (overused), no suitcase, no text or letters beyond the implied W, no photographic textures, no more than 3 colors.

---

## 9. Component quick reference (for the engineer)

| Component | Spec |
|---|---|
| Kind chip | Circle, `@ScaledMetric` 32pt, fill `kind…Tint`, symbol 15pt semibold in `kind…` |
| Timeline rail | 2pt wide, `separator`; segment leading into Now/Next item is `accent` |
| Staying band | Height ≥36pt, radius 10, `kindLodgingTint` fill, `bed.double.fill` + `.footnote` text in `kindLodging` (text in `textPrimary`) |
| Hero card | `surface` card, radius 20, padding 20, cover 64, progress bar 4pt capsule in trip color on `surface2` |
| Action button (detail) | Vertical stack, symbol 20pt `accent`, `.caption` label `textPrimary`, fill `surface`, radius 14, min height 64 |
| Primary button | `.borderedProminent`, `.controlSize(.large)`, full width, tint `accent` |
| Toast | Capsule on `.regularMaterial` (solid `surface` with Reduce Transparency), symbol + `.subheadline`, top of screen below nav bar, auto-dismiss 2.5s, announced via VoiceOver |
| Offline banner | Full-width bar, `surface2`, `wifi.slash` + `.footnote` `textSecondary`, height ≥32 |
| Avatar | Circle, trip color (or `accent` in Settings), white initials `.subheadline.bold`, 36pt (`@ScaledMetric`) |
