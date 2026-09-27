# Wayfare Backend: Setup Guide

This folder is the server for the Wayfare iPhone app. It runs on **Cloudflare Workers** (the same service as your Strava helper) with a small Cloudflare database called **D1**. It does five things:

- signs people in with **Sign in with Apple**
- keeps trips in sync between phones, and lets you share a trip with friends
- sends **push notifications** ("Sam added Dinner at Taberna", and the morning "Today in Lisbon" briefing)
- turns a pasted booking email into itinerary entries with **Claude** (AI import)
- deletes everything when someone deletes their account (Apple requires this)

You don't need to read or change any code. Setup is a one-time job of about **45 minutes**:

1. Install the Cloudflare command-line tool (5 minutes)
2. Create the database (3 minutes)
3. Set up the database tables (1 minute)
4. Apple Developer portal: turn on Sign in with Apple and Push, and create one key (10 minutes)
5. Fill in your Apple IDs (2 minutes)
6. Get an Anthropic API key (2 minutes)
7. Hand the server its secret keys (3 minutes)
8. Deploy (2 minutes)
9. Check it works (1 minute)

Do them in this order.

## Why this one needs the Terminal

Your Strava helper was a single file you could paste into the Cloudflare dashboard. This server is several files plus a database, so Cloudflare's own tool, **Wrangler**, has to upload it. That means typing about ten commands into the Mac **Terminal** app. Each one is copy and paste, and each step below says what you should see afterwards.

To open Terminal: press **⌘ Space**, type `Terminal`, press Return.

---

## 1. Install the tools

1. Install **Node.js**: go to <https://nodejs.org>, download the **LTS** version, and run the installer (click Continue until it's done).
2. In Terminal, go into this folder. Type `cd ` (with a space after it), drag the `wayfare/backend` folder from Finder into the Terminal window, and press Return.
3. Install Wrangler and the other helpers:
   ```
   npm install
   ```
   You should see `added … packages` at the end. Warnings are fine.
4. Log in to Cloudflare (a browser window opens; click **Allow**):
   ```
   npx wrangler login
   ```
   If you don't have a Cloudflare account yet, create a free one at <https://dash.cloudflare.com/sign-up> first. No credit card is needed.

## 2. Create the database

```
npx wrangler d1 create wayfare
```

The output contains a line like `database_id = "0f2c…"`. Copy that id.

Open `wrangler.toml` in this folder with TextEdit. Find `database_id = "REPLACE_WITH_YOUR_D1_DATABASE_ID"`, paste your id between the quotes in place of the placeholder, and save.

## 3. Set up the database tables

```
npx wrangler d1 migrations apply wayfare --remote
```

Type `y` if it asks you to confirm. You should see `0001_init.sql` with a ✅.

## 4. Apple Developer portal

You need a paid Apple Developer account, which you'll need anyway to put the app on the App Store. Go to <https://developer.apple.com/account>.

**a) Find your Team ID.** Click **Membership details** and copy the **Team ID** (10 characters, like `A1B2C3D4E5`).

**b) Turn on the app's capabilities.** Go to **Certificates, IDs & Profiles → Identifiers**. Click the app's identifier `com.wayfare.app`. If it isn't in the list, click **+ → App IDs → App**, enter the description "Wayfare" and the Bundle ID `com.wayfare.app`, then continue. Tick:
- **Sign in with Apple**
- **Push Notifications**

Click **Save**, then **Confirm** if asked.

**c) Create one key for the server.** Go to **Keys** and click the blue **+**.
- Key name: `Wayfare server`
- Tick **Apple Push Notifications service (APNs)**. If it asks for an environment, choose **Sandbox & Production**.
- Tick **Sign in with Apple**, click **Configure** next to it, choose `com.wayfare.app` as the Primary App ID, and click **Save**.
- Click **Continue**, then **Register**.
- Click **Download**. You get a file named like `AuthKey_ABC123DEFG.p8`. **Apple only lets you download it once**, so keep it somewhere safe, such as your password manager. Don't email it or put it in GitHub.
- Copy the **Key ID** shown on that page (10 characters, the `ABC123DEFG` part of the file name).

The same key does both jobs: sending push notifications, and letting the server cancel a user's Apple sign-in when they delete their account. (If you'd prefer two separate keys, that works too. Just use each key's own ID in step 5.)

## 5. Fill in your Apple IDs

Open `wrangler.toml` again and replace the placeholders in the `[vars]` section:

| Setting | What to put |
|---|---|
| `APNS_KEY_ID` | the Key ID from step 4c |
| `APPLE_SIWA_KEY_ID` | the same Key ID (or your second key's ID, if you made two) |
| `APNS_TEAM_ID` | your Team ID from step 4a |
| `APPLE_TEAM_ID` | your Team ID again |
| `APPLE_BUNDLE_ID` and `APNS_TOPIC` | leave as `com.wayfare.app` unless the app's bundle id changes |

Save the file. These values aren't secret, so it's fine that they live in this file.

## 6. Get an Anthropic API key (for AI import)

1. Go to <https://console.anthropic.com/> and log in (the same account as your Training Plan app is fine).
2. Go to **API Keys → Create Key**, name it "Wayfare", and copy the key (starts with `sk-ant-`).
3. Make sure the account has a little credit under **Billing**. One import costs about 2-3 cents, and each user is capped at 30 imports a day.

## 7. Hand the server its secret keys

Secrets go straight to Cloudflare and never into any file. In Terminal, still in this folder, run these three commands. In the first two, replace the path with where your `.p8` file actually is. Typing `< ` and then dragging the file into Terminal fills in the path for you.

```
npx wrangler secret put APNS_PRIVATE_KEY < ~/Downloads/AuthKey_ABC123DEFG.p8
npx wrangler secret put APPLE_SIWA_PRIVATE_KEY < ~/Downloads/AuthKey_ABC123DEFG.p8
npx wrangler secret put ANTHROPIC_API_KEY
```

The last one asks you to paste the `sk-ant-…` key, then press Return. Each command should end with `✨ Success!`. If it asks whether to create the Worker `wayfare-api`, type `y`.

## 8. Deploy

```
npx wrangler deploy
```

At the end it prints your server's address, something like `https://wayfare-api.your-name.workers.dev`. Copy it.

In the iOS project, open `ios/Config.xcconfig` and set `API_BASE_URL` to that address.

## 9. Check it works

Open your server address with `/v1/health` on the end in a browser, e.g. `https://wayfare-api.your-name.workers.dev/v1/health`. Or run this in Terminal:

```
curl https://wayfare-api.your-name.workers.dev/v1/health
```

You should see:

```
{"ok":true,"version":"1"}
```

You're done. The morning briefing job starts on its own and runs at the top of every hour. Each phone gets its briefing at the hour the user picked, in their own time zone.

---

## Everyday things

- **See what the server is doing right now** (handy while testing on your phone): `npx wrangler tail`. Press Ctrl-C to stop.
- **Deploy an updated version** after the code changes: `npm install`, then `npx wrangler d1 migrations apply wayfare --remote` (only does something if there's a new migration), then `npx wrangler deploy`.
- **Replace a secret** (e.g. a new Anthropic key): run the same `npx wrangler secret put …` command again.
- **Look at the data**: Cloudflare dashboard → **Storage & Databases → D1 → wayfare → Explore data**.

## Local development

Only needed if you (or the studio) want to run the server on your Mac.

1. Create a file named `.dev.vars` in this folder (it is git-ignored) with your secrets. For the `.p8` keys, put the whole key on one line with `\n` where the line breaks were:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGT...\n-----END PRIVATE KEY-----"
   APPLE_SIWA_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGT...\n-----END PRIVATE KEY-----"
   ```
   Any of these can be left out. The server then skips pushes, Apple token revocation or AI import, and everything else works.
2. Create the local copy of the database: `npm run db:migrate:local`
3. Start the server: `npx wrangler dev --local` (it runs at `http://localhost:8787`)
4. Check it: `curl http://localhost:8787/v1/health`
5. Run the hourly job by hand: `curl "http://localhost:8787/cdn-cgi/local/scheduled"`
6. Run the automated tests (no Cloudflare account needed): `npm test`

Point the simulator build at `http://localhost:8787` via `API_BASE_URL` to use it from the app. Sign in with Apple in the simulator still talks to the real Apple servers, which is fine.

## Troubleshooting

- **`npm install` fails with "Cannot read properties of null (reading 'edgesOut')"**: that's an npm bug. This folder's `.npmrc` already works around it. If you still see it, run `npm install --legacy-peer-deps`.
- **Sign-in fails with "identityToken is for a different app"**: `APPLE_BUNDLE_ID` in `wrangler.toml` must exactly match the app's bundle id in Xcode. Redeploy after changing it.
- **No push notifications arrive**:
  - Check `npx wrangler tail` while making a change on another phone.
  - `InvalidProviderToken` means the Key ID, Team ID or `.p8` doesn't match. Re-check steps 4-5, re-run step 7, then redeploy.
  - `DeviceTokenNotForTopic` means `APNS_TOPIC` doesn't match the app's bundle id.
  - Phones running a build from Xcode use Apple's *sandbox* push servers, and TestFlight/App Store builds use *production*. The app tells the server which one it is, so this is automatic, but the key must allow both (step 4c).
  - Collaborator alerts are limited to one per trip per person every 2 minutes, so a burst of edits only produces one notification.
- **Morning briefing didn't arrive**: it only goes out while a trip is in progress (today is between its start and end date, in the trip's time zone), at the hour chosen in the app. It's sent once per day per phone.
- **AI import says "not set up on the server yet"**: the `ANTHROPIC_API_KEY` secret is missing. Run step 7's last command, then try again (no redeploy needed).
- **AI import says "temporarily unavailable"**: check `npx wrangler tail` for the Anthropic error. It's usually billing credit, or Anthropic being briefly overloaded.
- **"Please sign in again" everywhere after a database reset**: expected. Sessions live in the database, so sign out and back in on the phone.
