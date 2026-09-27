# Wayfare for iPhone

A native SwiftUI travel itinerary app: day-by-day timeline in local time, day maps, local reminders,
sharing, and AI import of confirmation emails. Offline-first (SwiftData), synced with the Wayfare
Cloudflare Worker described in [`../docs/api-contract.md`](../docs/api-contract.md).

- iOS 17.0+, iPhone only, Swift 5 language mode, no third-party dependencies.
- The Xcode project is **generated** from `project.yml` by XcodeGen. Don't edit `Wayfare.xcodeproj` by hand;
  edit `project.yml` and run `xcodegen` again.
- Architecture, sync design and known risks: [`../company/04-ios-notes.md`](../company/04-ios-notes.md).

## 1. One-time setup on your Mac

1. Install **Xcode 16 or newer** from the Mac App Store, open it once, and let it install components.
2. Install Homebrew if you don't have it (https://brew.sh), then XcodeGen:
   ```sh
   brew install xcodegen
   ```
3. Sign in to Xcode with your Apple ID: **Xcode → Settings → Accounts → +**. For devices, push and
   TestFlight you need a paid Apple Developer Program membership.

## 2. Generate and open the project

```sh
cd wayfare/ios
xcodegen
open Wayfare.xcodeproj
```

Run `xcodegen` again whenever you pull changes that touch `project.yml` or add/remove files.

## 3. Configure

Edit `Config.xcconfig` (or create a git-ignored `Config.local.xcconfig` next to it with the same keys):

```
API_BASE_URL = https:/$()/wayfare-api.<your-subdomain>.workers.dev
DEVELOPMENT_TEAM = AB12CD34EF
```

- **`API_BASE_URL`**: your Worker's URL, no trailing slash. Keep the odd `https:/$()/` spelling: in
  `.xcconfig` files `//` starts a comment, and `$()` (an empty variable) splits the slashes. The app reads
  the value from the Info.plist key `APIBaseURL`.
- **`DEVELOPMENT_TEAM`**: your 10-character Team ID (developer.apple.com → Account → Membership).
  You can also leave it empty and pick the team in Xcode: target **Wayfare → Signing & Capabilities → Team**.
- The bundle id is `com.wayfare.app` (decision D1). If it's taken for your team, change
  `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, re-run `xcodegen`, and set the backend's
  `APPLE_BUNDLE_ID` to the same value (Sign in with Apple tokens are checked against it).

In **Debug** builds you can also switch servers at runtime: Settings → Developer → Server URL
(switching signs you out and clears local data).

## 4. Run

- **Simulator:** pick an iPhone simulator and press **⌘R**. Sign in with Apple works in the Simulator
  when the simulator is signed in to an Apple ID (Settings app → Sign in).
- **Device:** plug in your iPhone, enable Developer Mode (Settings → Privacy & Security → Developer Mode),
  pick it as the run destination, press **⌘R**. The first time, Xcode registers the device and creates a
  provisioning profile with the Sign in with Apple and Push Notifications capabilities (they come from
  `Wayfare/Wayfare.entitlements`).
- **Push notifications need a real device.** The Simulator can't get an APNs token (you'll see
  "APNs registration failed" in the console; local reminders still work). Debug builds register the
  device as `sandbox`, Release/TestFlight builds as `production`.
- **Tests:** **⌘U** runs `WayfareTests` (DTO coding, day grouping across zones, reminders, the 60-reminder
  cap, sync upserts).
- **Previews:** most screens have `#Preview` blocks that use an in-memory store with a sample
  "Lisbon & Porto" trip (`Wayfare/Models/SampleData.swift`).

## 5. Before the first TestFlight build

In **App Store Connect** (https://appstoreconnect.apple.com) and the developer portal:

1. **App ID** `com.wayfare.app` with **Sign in with Apple** and **Push Notifications** enabled
   (Xcode's automatic signing does this when you first run on a device; check it in
   Certificates, Identifiers & Profiles → Identifiers).
2. **APNs key** for the backend: Keys → + → Apple Push Notifications service. Give the `.p8`,
   Key ID and Team ID to the backend (see `company/05-backend-notes.md`).
3. **Sign in with Apple key** for token revocation on account deletion: Keys → + → Sign in with Apple,
   primary App ID `com.wayfare.app`. The backend needs it as `APPLE_SIWA_KEY_ID` / `APPLE_SIWA_PRIVATE_KEY`.
4. **New app** in App Store Connect → My Apps → + → New App: iOS, name (must be unique on the store;
   see D1), primary language, bundle id `com.wayfare.app`, SKU (any string).
5. **App icon**: add a 1024×1024 PNG (no transparency) to `Wayfare/Resources/Assets.xcassets/AppIcon.appiconset`
   in Xcode. **Uploads are rejected without it.** The brief is in `company/03-design-system.md` §8.
6. **Privacy policy URL** (required) and the **App Privacy** questionnaire. Use the nutrition label in
   `company/01-product-brief.md` §7 (no tracking; contact info, identifiers and user content linked to
   the user for app functionality; pasted import text is processed by Anthropic).
7. Export compliance: the Info.plist sets `ITSAppUsesNonExemptEncryption = NO` (HTTPS only), so no
   questionnaire per build.

## 6. Upload to TestFlight

1. In `Config.xcconfig`, bump `CURRENT_PROJECT_VERSION` (every upload needs a new build number;
   bump `MARKETING_VERSION` for a new version). Run `xcodegen` if you changed `project.yml`.
2. Set the run destination to **Any iOS Device (arm64)**.
3. **Product → Archive**. When the Organizer opens, select the archive → **Distribute App** →
   **App Store Connect** → **Upload**. Keep automatic signing. Xcode switches `aps-environment` to
   `production` for the distribution profile.
4. Wait for processing (5–30 min, you'll get an email). In App Store Connect → your app → **TestFlight**,
   answer the export-compliance prompt if asked, add yourself under **Internal Testing**, and install the
   **TestFlight** app on your iPhone to get the build.
5. For external testers or App Review, fill in **Test Information** and **App Review Information**:
   reviewers can't use your Apple ID, so explain that sign-in is Sign in with Apple only, describe how
   to try the app (create a trip, paste a sample confirmation email), and mention that account deletion is
   in Settings → Delete Account (Guideline 5.1.1(v)).

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| "Signing for Wayfare requires a development team" | Set `DEVELOPMENT_TEAM` or pick a team in Signing & Capabilities. |
| Sign-in fails with "Can't reach Wayfare" | Check `API_BASE_URL` (the `https:/$()/` trick) and that the Worker is deployed; try Settings → Developer → Test Connection in a Debug build. |
| Sign-in fails with "didn't complete" | The backend's `APPLE_BUNDLE_ID` must equal the app's bundle id. |
| No pushes | Real device only; allow notifications in the app; backend needs the APNs key and must use the sandbox host for Debug builds. |
| New files don't show up in Xcode | Run `xcodegen` again. |
