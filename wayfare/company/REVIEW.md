# Owner Review: Iteration 1

**Status:** a complete first build of the iOS app, backend, and studio docs is written and pushed.
**Not yet done:** compiling in Xcode, deploying the backend, testing on a device.
**Your job this round:** get it running once (steps below), then answer the questions in section 3.
Short answers are fine ("3a, 5 no, name = Onward").

---

## 1. What exists

| Area | What | Where | Verified how |
|---|---|---|---|
| Strategy | MVP scope, roadmap, pricing, App Store positioning | `01-product-brief.md` | Owner review (you) |
| UX | Every screen, state, edge case, notification copy | `02-ux-spec.md` | Owner review |
| Design | Color tokens (all WCAG AA, light + dark), type, SF Symbols, icon brief | `03-design-system.md` | Contrast ratios computed |
| iOS app | ~12k lines SwiftUI, iOS 17, SwiftData, MapKit, offline sync, reminders, push, sharing, AI import | `../ios/` | Hand-reviewed twice (engineer + QA); **never compiled**, since there's no Swift toolchain in this sandbox |
| Backend | Cloudflare Worker + D1, Sign in with Apple, sync, invites, APNs, briefing cron, Claude-powered import | `../backend/` | 103 automated tests pass; ran under `wrangler dev` with real local D1 |
| QA | Contract check across every endpoint, compile review, a 39-step device test plan | `06-qa-report.md` | n/a |
| Release | Ordered App Store path, privacy labels derived from the code | `07-release-checklist.md` | n/a |

## 2. Get it running (about 45 min, once)

1. **Backend:** follow `backend/README.md` (Cloudflare D1, secrets, APNs key, Anthropic key). Check it with `curl <worker>/v1/health`.
2. **App:** follow `ios/README.md`:
   - `brew install xcodegen && cd wayfare/ios && xcodegen`
   - open `Wayfare.xcodeproj`, pick your Team, set `API_BASE_URL` in `Config.xcconfig`
   - run on your iPhone with the **Debug** scheme
3. **If Xcode shows compile errors:** paste them to me. `06-qa-report.md` lists the four spots most likely to need a tweak, with a fallback for each. Expect zero to a handful.
4. Walk the device test plan in `06-qa-report.md` (or just plan a real trip in it).
5. **Before TestFlight:** add a 1024×1024 app icon (brief in `03-design-system.md` §8).

## 3. Decisions we need from you

**Identity and business**
1. **Name.** "Wayfare" is close to *Wayfair* (the retailer), which is a trademark risk. Options: keep it, or pick Onward / Daybound / Tripsheet / Itinero / Nextstop, or your own.
2. **Public or personal?** If public and paid, we plan In-App Purchases now. The proposal is free with 5 AI imports/mo, and Plus at $19.99/yr. If personal-only, we skip monetization entirely.

**Scope for v1 / v1.1**
3. **Which pain is worst:** (a) getting bookings *in*, (b) finding things *on the road*, (c) keeping companions *in sync*? That decides what v1.1 builds first.
4. **Is paste-to-import enough,** or do you want the Share Extension ("Share → Wayfare" from Mail) in v1?
5. **Live Activity for your next flight** (Lock Screen / Dynamic Island): must-have for v1, or v1.2 as planned?
6. **Out of v1 by default:** packing lists, expenses, document vault, widgets, flight-status tracking. Pull any in?

**Behaviour**
7. **Daily briefing:** a 7:00 morning briefing only? Or also/instead an evening "tomorrow" preview?
8. **A late-night flight (e.g. departing 00:30):** file it under the trip-zone day or the ticket's local day?
9. **Reminders on shared trips** fire for every member, because the reminder is stored on the plan. OK, or should reminders be per-person?
10. **Member roles** can't be changed after inviting (remove and re-invite instead). Fine for v1?
11. **Solo or group-first?** Mostly alone, or co-planning with a partner/friends?

## 4. Decisions the studio made; overrule any

- There is no tab bar. Trips list → trip (Timeline | Map | Info) → item. Everything else is a sheet.
- The notification permission is asked after your first trip or reminder, never on first launch.
- Invite links are `wayfare://` links (they only work where the app is installed). Web links (universal links) come in v1.1.
- AI import uses Claude Sonnet server-side, and you review every draft before it's saved. It asks for a one-time consent first (App Store 5.1.2).
- Account deletion also revokes your Sign in with Apple token (App Store 5.1.1(v)).
- The default trip color is the design system's Lagoon teal.

## 5. Known risks we're carrying

1. **First compile:** a few errors are possible (see section 2, step 3).
2. **APNs from Cloudflare Workers is unproven** until your first real device test. Watch `wrangler tail`.
3. **Privacy policy, terms, and support URLs** are placeholders and must be live before App Store review.
4. **Free-tier scale:** the briefing cron handles about 40 devices per run. That's fine for you, not for a public launch.
5. **Sessions never expire, and the Apple refresh token is stored unencrypted.** Acceptable for personal use; to harden before a public launch.

## 6. How to give feedback

Reply with your answers and any "I don't like X" / "I want Y". I route each item to the right role and ship iteration 2 with a new `REVIEW.md`.
