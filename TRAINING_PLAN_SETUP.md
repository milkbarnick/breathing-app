# Training Plan — Setup Guide

This app is a single web page (`training-plan.html`) that runs entirely in your browser. There's no software to install and nothing to code. You do need to do three one-time things, each just clicking through a website:

1. Put the app somewhere you can open it (2 minutes)
2. Create a free Strava "API app" so the page is allowed to read your activities (5 minutes)
3. Deploy one small helper file to Cloudflare so your browser is allowed to talk to Strava (10 minutes)
4. Get a free Anthropic API key so the app can write your weekly plan and read gym photos/notes (2 minutes)

Do them in this order. Everything you paste in only lives in your own browser (localStorage) — nothing is sent to any server except Strava and Anthropic directly.

## Why step 3 exists

Browsers aren't allowed to call Strava's servers directly for security reasons (Strava doesn't send back the permission headers a browser requires), and your Strava "Client Secret" must never be pasted into a public web page where anyone could read it. The fix is a tiny piece of glue — a **Cloudflare Worker** — that sits between the app and Strava. You paste in one file, Cloudflare hosts it for free, and it keeps your secret safe while letting the page work.

---

## 1. Host the page

Pick whichever is easiest for you:

- **GitHub Pages (recommended, gives you a stable URL you can bookmark or add to your phone's home screen):**
  In this repository on GitHub: **Settings → Pages → Build and deployment → Source: "Deploy from a branch"** → pick the `main` branch, `/ (root)` folder → Save. After a minute or two your page is live at `https://<your-username>.github.io/breathing-app/training-plan.html`.
- **Just open the file locally:** download `training-plan.html` and double-click it. Works fine, but Strava's login step needs a real web address to redirect back to (see step 2), so GitHub Pages is the smoother option.

## 2. Create your Strava API app

1. Go to <https://www.strava.com/settings/api> (log in to Strava first).
2. Fill in the form:
   - **Application Name:** anything, e.g. "My Training Plan"
   - **Category:** Training
   - **Website:** the URL from step 1 (e.g. `https://your-username.github.io/breathing-app/`)
   - **Authorization Callback Domain:** just the domain part, e.g. `your-username.github.io`
3. Click Create. You'll get a **Client ID** and a **Client Secret** — copy both somewhere, you'll need them in a minute.

## 3. Deploy the Strava helper (Cloudflare Worker)

1. Go to <https://dash.cloudflare.com/sign-up> and create a free account (no credit card needed).
2. In the dashboard, go to **Workers & Pages → Create → Create Worker**. Give it any name (e.g. `strava-proxy`) and click **Deploy** to create it with the default placeholder code.
3. Click **Edit code**. Delete everything in the editor and paste in the entire contents of `strava-worker.js` from this repository. Click **Deploy** (or **Save and deploy**).
4. Go to the Worker's **Settings → Variables and Secrets**. Add two variables:
   - `STRAVA_CLIENT_ID` = the Client ID from step 2
   - `STRAVA_CLIENT_SECRET` = the Client Secret from step 2 (tick "Encrypt" if offered)
   Save/deploy again if prompted.
5. Copy your Worker's URL — it's shown at the top of the Worker page, something like `https://strava-proxy.your-subdomain.workers.dev`.

## 4. Get an Anthropic API key

1. Go to <https://console.anthropic.com/> and sign up / log in.
2. Go to **API Keys → Create Key**. Copy the key (starts with `sk-ant-...`).
3. Add a small amount of credit under **Billing** — this app's usage (a weekly plan + occasional photo/text analysis) costs a few cents a week at most.

## 5. Connect everything in the app

Open `training-plan.html` (your GitHub Pages URL, or the local file) and go to the **Settings** tab:

- Paste your **Strava Client ID** and your **Worker URL** (from steps 2 and 3), then tap **Save settings**, then **Connect Strava** and approve access.
- Paste your **Anthropic API key** (from step 4).
- Fill in your equipment list, bodyweight (optional), and any notes for your coach (injuries, preferences, etc.).
- Save settings.

You're set up. Go to **Today** or **Week** and tap **Generate This Week's Plan**.

---

## Using it week to week

- The app follows a fixed weekly shape: **Mon/Fri gym, Tue/Thu/Sun run** (Tue is always your easy trail run with Bob, Thu is the quality session, Sun is the long run) — everything else about the plan is written fresh each week by Claude, based on your recent Strava runs and logged gym sessions.
- Log gym sessions by typing them in, snapping a photo of your notes/whiteboard, or jotting free text — Claude reads it into structured sets/reps/weight for you to confirm.
- Runs sync automatically from Strava and match themselves to the right day.
- Do a quick daily check-in (sleep/soreness/energy) on the Today tab — the plan generator uses it to back off when you're run down.
- Tap **Regenerate** on the Week tab any time you want a fresh plan (e.g. after a bad night's sleep or a missed session) — you can add a note like "sore knee" or "short on time this week" and it'll adjust.

## Troubleshooting

- **"Strava connect failed"**: double check the Worker URL has no typo and that you added both environment variables in Cloudflare, then redeployed.
- **Strava login redirects but nothing happens**: your Strava app's "Authorization Callback Domain" (step 2) must exactly match the domain you're opening the page from.
- **Claude errors mentioning your API key**: check the key was copied in full and that your Anthropic account has billing/credit set up.
- Nothing here ever needs a terminal, `git`, or installing software — if a step is asking you to do that, something's gone off track.
