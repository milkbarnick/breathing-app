# 05: Backend Notes (Backend Engineer)

Status: **v1 implemented** against `docs/api-contract.md`, including the CTO's Sign in with Apple token-revocation update. Code is in `backend/` and the owner's deploy guide is `backend/README.md`. 102 automated tests pass (`npm test`). The Worker bundles with `wrangler deploy --dry-run`, the migration applies to a real local D1, and the main flows were smoke-tested under `wrangler dev --local`.

## Architecture

One Cloudflare Worker (plain ES modules, no build step, no framework) plus one D1 database and an hourly Cron Trigger.

| File | Job |
|---|---|
| `src/index.js` | `fetch` handler (routing, auth gate, error wrapping) and `scheduled` handler (briefing + housekeeping) |
| `src/router.js` | Tiny `:param` router |
| `src/util.js` | Error type and contract error shape, JSON helpers, base64url, SHA-256, PEM parsing |
| `src/validate.js` | Validation for every write (types, lengths, enums, UUIDs, ISO instants, dates, IANA zones) |
| `src/model.js` | D1 row (snake_case) → API JSON (camelCase) |
| `src/auth.js` | Apple identity-token verification (JWKS fetched and cached per isolate, RS256 via WebCrypto, iss/aud/exp/iat), sessions, Apple client secret, code exchange, revocation |
| `src/account.js` | `/v1/auth/apple`, `/v1/auth/logout`, `/v1/me` GET/PATCH/DELETE (account erasure) |
| `src/devices.js` | `PUT /v1/devices/current` |
| `src/sync.js` | `GET /v1/sync` |
| `src/trips.js` | Trip upsert/delete, plus membership and permission helpers |
| `src/items.js` | Item upsert/delete and the coalesced collaborator push |
| `src/invites.js` | Invite codes, accept, remove member / leave |
| `src/apns.js` | Shared ES256 JWT signer, APNs provider token (cached 50 min), sending, dead-token cleanup |
| `src/briefing.js` | Hourly daily-briefing job (pure planning functions plus I/O) and housekeeping |
| `src/importer.js` | AI import: Anthropic Messages API via `fetch`, structured output, server-side sanitizing, rate limit |
| `src/time.js` | `Intl.DateTimeFormat`-based local date/hour helpers |

Request flow: router match → (auth: SHA-256 the bearer token, look up `sessions ⋈ users`) → handler → JSON. Any thrown `HttpError` becomes `{ "error": { code, message } }`. Anything else is logged with its stack and returned as a generic `500 internal`, so stack traces and SQL never reach the client.

## Tables (`migrations/0001_init.sql`)

| Table | Key | Notes |
|---|---|---|
| `users` | `id` (uuid), unique `apple_sub` | `display_name`, `email` (nullable), `apple_refresh_token` (for revocation) |
| `sessions` | `token_hash` (SHA-256 hex) | Raw tokens are never stored. FK → users, cascade |
| `devices` | `apns_token` | env, time zone, briefing prefs, `last_briefing_date` (dedup). FK → users, cascade |
| `trips` | `id` (client uuid) | `owner_id` has no FK on purpose (tombstones outlive a deleted owner). Index on `updated_at` |
| `trip_members` | (`trip_id`, `user_id`) | role, soft delete. `user_id` has no FK on purpose (member tombstones outlive the user) |
| `items` | `id` (client uuid) | `details` is JSON text. Indexes (`trip_id`, `updated_at`) and (`trip_id`, `start_at`) |
| `invites` | `code` | role, `expires_at`. Cascade from trip |
| `push_log` | (`trip_id`, `user_id`) | last collaborator push time (coalescing) |
| `import_usage` | (`user_id`, `day`) | AI import count per UTC day |

D1 enforces foreign keys by default. The test shim turns them on explicitly to match.

## How sync visibility works

For caller U and cursor S:

1. **Trips, items and members of trips where U is an active member** are returned when their own `updated_at > S`, **or when U's membership row changed after S**. The second case covers someone who just joined or re-joined: they need the whole trip, including rows last edited long before their cursor.
2. **Trips U was removed from** (U's membership tombstoned after S) come back as a trip tombstone (`deletedAt` = removal time, `notes` blanked), along with U's own member tombstone, so the client drops the trip. Items are not re-sent; the client drops them with the trip.
3. **Tombstones are always included**: deleted trips, items (cascaded on trip delete) and members.
4. **Cursor** = server clock at the start of the request **minus 5 seconds**. A write whose timestamp was taken just before our read but committed just after it is still picked up on the next sync. The cost is that the last ~5 s of rows can be delivered twice, which is harmless because clients upsert by id.
5. A display-name change bumps the user's membership rows so co-members' devices get the new name.

Last write wins in the order the server receives writes. `PUT` always overwrites, and a `PUT` on a tombstoned item revives it.

## Push coalescing

On item upsert, the handler returns immediately and `ctx.waitUntil` runs the push:
1. Find other active members of the trip who have at least one device with `collabAlertsEnabled`.
2. For each recipient, atomically claim the window with one statement: `INSERT … ON CONFLICT DO UPDATE SET last_sent_at = now WHERE last_sent_at <= now − 2 min RETURNING user_id`. A row comes back only if the claim succeeded, so two concurrent edits can't both push.
3. Send to all of the claimed recipients' collab-enabled devices, with `apns-collapse-id = trip-<id>`. Pushes that fall inside the window are dropped, not queued. The first change in each 2-minute window produces the notification, and sync delivers the actual data.
4. APNs `410`, `BadDeviceToken` (or `Unregistered`) deletes the device row. `ExpiredProviderToken` / `InvalidProviderToken` resets the cached JWT.

The daily briefing uses `devices.last_briefing_date` (the device's local date). Due devices are marked **before** sending, so an overlapping or retried cron run, or a DST fall-back repeating an hour, never double-sends.

## Cost estimate (free tiers, as of writing; check Cloudflare's pricing page)

- **Workers Free**: 100,000 requests/day, 10 ms CPU per invocation, 50 subrequests per invocation. An active user makes roughly 50-300 requests/day (sync on foreground, edits), so **hundreds of users fit in the free tier**. CPU per request is small: WebCrypto RSA verify and ECDSA sign are native and well under 1 ms.
- **D1 Free**: 5 M rows read/day, 100 k rows written/day, 5 GB. Sync queries are driven by indexes on membership, so a user with 5 trips × 50 items reads a few hundred rows per full sync and very few per delta sync.
- **Cron**: 24 runs/day, free.
- **Anthropic** (`claude-sonnet-5`, $2 in / $10 out per M tokens): a typical import is about 3-6 k input tokens (prompt + schema + email) and 1-2 k output tokens including thinking, so **about 2-3 cents per import**. The hard cap of 30/user/day bounds the worst case at about $0.75/user/day.
- **The limit to watch**: the **50-subrequest cap per cron run on the free plan**. Each briefing push is one subrequest, so past roughly 40 simultaneous briefings in one hour, the owner should move to Workers Paid ($5/month, much higher limits) or we fan out through Queues (TODO).

## Security notes

- Session tokens: 32 random bytes (base64url). Only SHA-256 is stored, so a leaked database cannot be replayed. Logout deletes the session row.
- Apple identity token: RS256 signature against Apple's JWKS (refetched on unknown `kid`, at most every 5 min), `iss`, `aud` = `APPLE_BUNDLE_ID`, `exp`/`iat` with 60 s skew, `alg` pinned to RS256 (rejects `none`).
- Apple refresh token is stored in plaintext in D1 so it can be revoked on deletion (see TODOs). The code exchange runs after the response via `waitUntil`, and a failure is logged without failing sign-in, per contract. Revocation runs before the rows are deleted and is best effort.
- Account deletion is one D1 batch (transaction). It hard-deletes solo trips (items, members and invites cascade), sessions, devices, usage and push bookkeeping, and the user row. It erases items and invites of owned shared trips and scrubs those trips into content-free tombstones so collaborators' devices drop them. The user's memberships in other people's trips become id-only tombstones.
- Every write is validated (types, lengths, enums, UUIDs, ISO instants, IANA zones, lat/long ranges), bodies are capped at 256 KB, and unknown keys are ignored.
- AI import: pasted text is wrapped in `<pasted_text>`, the system prompt tells the model to treat it as data and ignore instructions in it, output is constrained by a JSON schema, and **every draft is re-sanitized server-side** (kind enum, canonical instants, IANA zones, length caps, control characters stripped, max 50 drafts). The endpoint is editor/owner only and rate-limited, with refunds when the upstream call fails. Consent is client-side, per contract.
- Secrets (`APNS_PRIVATE_KEY`, `APPLE_SIWA_PRIVATE_KEY`, `ANTHROPIC_API_KEY`) are Wrangler secrets. `.dev.vars` and `*.p8` are git-ignored.
- Invite codes are 8 characters from a 31-symbol alphabet (about 8.5 × 10¹¹ combinations), expire after 7 days, and are case-insensitive.

## Contract issues

Where the contract was silent or ambiguous, this is what I implemented. Items marked **(proposal)** would need a contract change.

1. **UUID case.** The contract says lowercase, but Swift's `UUID().uuidString` is **uppercase**. The server accepts either and stores and returns lowercase. The iOS client should lowercase ids itself, or it will see different ids echoed back and may create local duplicates.
2. **Sync returns rows with `updatedAt <= since` in two cases.** (a) When the caller joined or re-joined a trip after `since`, they get the whole trip. (b) The cursor has a 5 s safety margin, so recent rows can be sent twice. Both are needed for correctness. The contract text "rows with `updatedAt > since`" should become "at least these rows; clients must upsert idempotently".
3. **Cursor semantics.** The contract doesn't define how `cursor` is chosen. Ours is server time minus 5 s, not the max `updatedAt` returned.
4. **No sync pagination.** A very large account returns everything in one response. Fine for v1 sizes. **(proposal)** add `limit` + `hasMore` later.
5. **Tombstone retention / full resync.** Tombstones are kept forever for now. If we ever purge them, clients with old cursors would keep ghost rows. **(proposal)** add a `reset: true` flag telling the client to wipe and full-sync.
6. **Deleted trips can't be revived.** `PUT` on a deleted trip (or on an item in one) returns `409 conflict`, while `PUT` on a deleted *item* in a live trip revives it (last write wins). The contract doesn't say either way.
7. **Account deletion and collaborators.** "Delete all data the user owns" and "tombstones" pull against each other. Owned trips that are shared get their content erased but keep a tombstone row so collaborators' devices drop them. Items the user wrote in *other people's* trips stay (they belong to that trip), with `updatedBy` pointing to a user that no longer exists. A deleted member appears with `displayName: ""`.
8. **Logout doesn't unregister the device.** After `/v1/auth/logout` the phone keeps getting that user's pushes until another account registers the same APNs token. **(proposal)** `DELETE /v1/devices/current` with `{ apnsToken }`, or include `apnsToken` in the logout body.
9. **Briefing wording and edge cases.**
   - The title uses `destination`, falling back to `title`, so the contract's own example trip (destination "Portugal") would say "Today in Portugal", not "Today in Lisbon".
   - With zero plans today we still send "No plans yet today. Tap to add some."
   - Several in-progress trips mean one push per trip.
   - "Today's plans" are items whose `startAt` falls on that date in the item's own `startTimeZone`. A multi-night lodging only counts on check-in day.
   - Times are 24-hour ("8:30", "20:05") because the server doesn't know the user's locale. **(proposal)** add `locale` / `uses24HourClock` to the device.
10. **All-day items.** The contract doesn't say what `startAt` means for `allDay: true`. The AI import uses local midnight in `startTimeZone`, converted to UTC. iOS should do the same.
11. **Required fields.** The contract lists writable fields but not which are required. Enforced: Trip `title`, `startDate`, `endDate` (end ≥ start), `timeZone`. Item `kind`, `title`, `startAt`, `startTimeZone`, and `endAt` ≥ `startAt` when present. Everything else has a default.
12. **`User.email` can be null.** Apple doesn't always include an email. The contract example shows a string.
13. **Error statuses.** AI upstream failures return HTTP **502** with code `internal`, since the contract lists codes, not statuses. The owner trying to leave returns `403 forbidden`.
14. **Invites.** Codes are multi-use until expiry. Editors can create editor invites, as the contract allows. Accepting never changes an existing member's role. There's no endpoint to change a member's role (a gap for later).
15. **Push on delete.** The contract only mentions create/edit, so deletes don't push.
16. **Dead tokens.** Besides `410` / `BadDeviceToken` we also drop on reason `Unregistered` (Apple sends it with 410 anyway).

## Known limitations / TODOs

- **APNs over HTTP/2 from Workers.** Workers' `fetch` negotiates HTTP/2 with `api.push.apple.com`, but we haven't sent a real push in this environment. First real-device test: watch `wrangler tail` for the APNs status.
- Cron fan-out is sequential inside one invocation. Past about 40 briefings per hour (free plan subrequest cap), move to Queues or Workers Paid.
- Sessions never expire (only logout / account deletion ends them). TODO: expire after ~180 days idle (`last_used_at` is already tracked daily).
- Apple refresh token stored unencrypted. TODO: encrypt with an AES-GCM key held as a Worker secret.
- The Apple identity-token `nonce` isn't checked (the contract doesn't send one). **(proposal)** the client sends a nonce and its SHA-256 goes into the Apple request, which blocks token replay.
- No rate limit on `POST /v1/invites/:code/accept` (the code space is large, but a per-user limit would be cheap to add).
- No tombstone purge (see Contract issue 5).
- Local tests use a small `node:sqlite` D1 stand-in (`test/helpers/d1.js`). It runs the real migration and SQL, but it isn't Miniflare. The same SQL was also smoke-tested on real local D1 via `wrangler dev`.
