# Wayfare Release Checklist (App Store path)

Owner: QA & Release Lead. Work through it in order. Each step lists what it depends on. Current values in the repo:
bundle id `com.wayfare.app`, iPhone only, iOS 17.0+, version `1.0.0 (1)` in `ios/Config.xcconfig`.

## 1. Apple Developer account and App ID
- [ ] Enroll in the Apple Developer Program (paid; enrolling as an organization needs a D-U-N-S number). Note your
      **Team ID** (Membership details).
- [ ] Put the Team ID in `ios/Config.local.xcconfig` (`DEVELOPMENT_TEAM = AB12CD34EF`) or in `Config.xcconfig`, then run `xcodegen`.
- [ ] Certificates, Identifiers & Profiles → Identifiers → **App ID** `com.wayfare.app` (explicit). Capabilities:
  - [ ] **Sign in with Apple** (Enable as a primary App ID).
  - [ ] **Push Notifications**.
  - (Nothing else. The app uses no iCloud, App Groups, Associated Domains or location.)
- [ ] If you change the bundle id, change it in `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`) and in `backend/wrangler.toml`
      (`APPLE_BUNDLE_ID`, `APNS_TOPIC`).
- [ ] Xcode → Signing & Capabilities with automatic signing: confirm both capabilities appear, taken from
      `Wayfare.entitlements`.

## 2. Keys (APNs and Sign in with Apple)
- [ ] Keys → + → enable **Apple Push Notifications service (APNs)** (select *Sandbox & Production*) **and Sign in with
      Apple** (configure it with the primary App ID `com.wayfare.app`). One `.p8` file can serve both. **Download it once.**
      Note the **Key ID**.
- [ ] Keep the `.p8` somewhere safe (a password manager). Apple won't let you download it again.

## 3. Backend deploy (Cloudflare Worker)
Follow `backend/README.md`. In short:
- [ ] `cd backend && npm ci && npm test` → 103 passing.
- [ ] `npx wrangler d1 create wayfare`, then put the id into `wrangler.toml` → `database_id`.
- [ ] `npx wrangler d1 migrations apply wayfare --remote`.
- [ ] In `wrangler.toml [vars]`: `APPLE_BUNDLE_ID`, `APNS_TOPIC`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APPLE_TEAM_ID`,
      `APPLE_SIWA_KEY_ID`.
- [ ] Secrets: `npx wrangler secret put APNS_PRIVATE_KEY`, `… APPLE_SIWA_PRIVATE_KEY` (the same .p8 is fine),
      `… ANTHROPIC_API_KEY`. **Without the SIWA secrets, account deletion can't revoke Apple tokens** (a review risk).
- [ ] `npx wrangler deploy`. Confirm that `curl https://wayfare-api.<sub>.workers.dev/v1/health` returns `{"ok":true,"version":"1"}`.
- [ ] Confirm the cron trigger `0 * * * *` shows in the dashboard (Worker → Settings → Triggers).
- [ ] Set `API_BASE_URL = https:/$()/wayfare-api.<sub>.workers.dev` in `ios/Config.xcconfig` (keep the `$()` trick),
      then run `xcodegen`.

## 4. App icon (1024 PNG)
- [ ] Export "The Folded Route" (design system §8) as a **1024×1024 PNG, sRGB, opaque (no alpha), square corners**.
- [ ] Drag it into `Assets.xcassets → AppIcon` (the single universal slot). Optionally add Dark and Tinted variants.
- [ ] Archive validation fails without it. Check with Product → Archive → Validate.

## 5. Privacy policy URL (required) and support URL
- [ ] Publish a privacy policy (required for every app, and doubly so for Sign in with Apple and AI import). It must
      cover: the data in §6 below, that pasted import text is sent to **Anthropic** (Claude) for processing, Cloudflare as
      host, Apple Push, retention, in-app account deletion, and a contact.
- [ ] Publish Terms (linked from Welcome and Settings) and a **support URL** (a simple page with an email address is
      enough).
- [ ] The app currently links `https://wayfare.app/privacy`, `https://wayfare.app/terms` and `mailto:support@wayfare.app`
      (`ios/Wayfare/Networking/AppConfig.swift`). Make them resolve, or change the constants, **before** archiving.
- [ ] Enter the Privacy Policy URL and Support URL in App Store Connect → App Information / version page.

## 6. App Privacy "nutrition labels" (derived from the code)
App Store Connect → App Privacy → **Data collection: Yes**. For every type below: **Linked to the user: Yes**,
**Used for tracking: No**, purpose **App Functionality** only.

| Category | Type | Where it comes from in the code |
|---|---|---|
| Contact Info | **Name** | `displayName` from Sign in with Apple and name capture (`POST /v1/auth/apple`, `PATCH /v1/me`) |
| Contact Info | **Email Address** | Apple identity token `email` claim (often a private relay), stored in `users.email` |
| Identifiers | **User ID** | Apple `sub` and the Wayfare user id (`users`) |
| User Content | **Other User Content** | Trips, items (titles, places, addresses, coordinates of chosen places, confirmation codes, notes), and pasted confirmation text sent to `/import` (forwarded to Anthropic, not stored) |

**Not collected:** device location (MapKit search needs no permission, and the map shows your location only if you had
already granted it; nothing is sent), contacts, photos, health, financial info, browsing, search history, usage data,
diagnostics (no analytics or crash SDK), and advertising data. The APNs device token and the device time zone are used
only to deliver notifications and aren't declared as a Device ID. Mention them in the privacy policy.
**Tracking:** No. There is no ATT prompt and no third-party SDKs.
- [ ] `ios/Wayfare/Resources/PrivacyInfo.xcprivacy` (added by QA) declares the same types plus the UserDefaults
      required-reason API (`CA92.1`). After `xcodegen`, confirm it is listed under the Wayfare target → Build Phases →
      **Copy Bundle Resources**.

## 7. Export compliance
- [ ] `ITSAppUsesNonExemptEncryption: false` is **already in `project.yml`** (`info.properties`), so it goes into the
      generated Info.plist. The app uses only HTTPS (URLSession) and the system Keychain, with no custom cryptography, so
      it qualifies for the exemption. App Store Connect won't ask the encryption question for each build.

## 8. Screenshots and review notes
- [ ] Screenshots (iPhone only; no iPad because `TARGETED_DEVICE_FAMILY = 1`):
  - **6.9"**: 1320 × 2868 portrait (iPhone 16 Pro Max / 17 Pro Max simulator). Required.
  - **6.5"**: 1284 × 2778 (or 1242 × 2688) portrait (iPhone 11 Pro Max / XS Max class). Provide it too for older listings.
  - Suggested 5: the in-progress trip timeline with Now/Next · the flight detail (JFK → LIS, "+1") · the day map · the AI
    import review · the Share sheet. Use the sample "Lisbon & Porto" data. Capture light mode first.
- [ ] **Review notes / demo account strategy:** Wayfare has **only Sign in with Apple**, so there is no username or
      password to give. **The reviewer signs in with their own Apple ID**, which creates a fresh empty account. Put this
      in the review notes:
      > "Sign in with Apple is the only login. Please use your own Apple ID; a new account is created automatically.
      > To see content: tap + → New Trip, then + → Import from Email… and paste the sample text below (it creates a
      > flight, hotel and dinner), or add items by hand. Sharing: Share → Create Invite Link; the code can be joined
      > from a second device via + → Join with Code. Account deletion: Settings → Delete Account. AI import sends
      > the pasted text to Anthropic only after the in-app consent screen."
      Attach the sample confirmation email from `06-qa-report.md` §6.
- [ ] Also fill in: category Travel, age rating (no objectionable content → 4+), and a copyright line.

## 9. TestFlight
- [ ] Bump `CURRENT_PROJECT_VERSION` for every upload (in `Config.xcconfig`).
- [ ] Scheme **Wayfare**, destination *Any iOS Device (arm64)* → Product → **Archive** (the Release config reports
      `production` to the backend, and export switches `aps-environment` to production).
- [ ] Organizer → Validate → Distribute → App Store Connect → Upload.
- [ ] App Store Connect → TestFlight: fill in "What to Test", add internal testers (you and the second Apple ID).
      External testing needs a short Beta App Review.
- [ ] Run the pre-submit smoke test (§11) **on a TestFlight build** (its push path differs from Debug).

## 10. Guideline compliance status

| Guideline | Status | Evidence / to-do |
|---|---|---|
| **4.2 Minimum functionality** | ✅ Likely fine | A native SwiftUI app with an offline store, local reminders, maps, sharing, pushes and AI import. It is not a web wrapper. Make the screenshots show that depth. |
| **4.8 Login services** | ✅ | Sign in with Apple is the only login method. |
| **5.1.1(v) Account deletion** | ✅ in app, ⚠️ secrets | Settings → Delete Account → `DELETE /v1/me` (deletes owned data, tombstones shared trips, revokes the Apple token). **Requires the `APPLE_SIWA_*` secrets** (§3) so revocation actually happens. |
| **5.1.1 Data collection / privacy policy** | ⚠️ | Needs the live privacy policy URL (§5) and nutrition labels matching §6. |
| **5.1.2 Data use and sharing (third-party AI)** | ✅ | A one-time explicit consent screen ("Pasted text is sent to Anthropic to extract your plans"), no import without it (checked again in `findPlans`), consent can be withdrawn in Settings, and nothing is saved without review. Name Anthropic in the privacy policy too. |
| 2.1 App completeness | ⚠️ | The backend must be live during review, and the icon and URLs must resolve. |
| 2.5.4 / background modes | ✅ | `remote-notification` is used for collaborator sync pushes (content-available). |

## 11. Pre-submit smoke test (TestFlight build, about 15 minutes)
- [ ] Fresh install → no notification prompt at launch → Sign in with Apple → name capture → empty state.
- [ ] Create a trip → the priming card → allow → add a flight with a 5-minute-away reminder → it fires.
- [ ] Airplane Mode: add an item → turn Airplane Mode off → the unsynced marker clears.
- [ ] AI import with the sample email → the review list → add → toast.
- [ ] Invite → join from the second Apple ID → the second device edits → the first device gets the **production** push
      and tapping it opens the item.
- [ ] Settings links: Privacy Policy, Terms and Contact Support all open real pages or a mail draft.
- [ ] Sign out → Welcome, no data, no push to this device. Sign in → data returns.
- [ ] Delete Account (use a throwaway Apple ID) → Welcome. Signing in again creates an empty account.
- [ ] Check light and dark mode and the largest Dynamic Type size on the Trips list and Timeline for clipping.
- [ ] Then: App Store Connect → the version page → select the build → answer the questionnaires (encryption is already
      answered) → **Submit for Review**.
