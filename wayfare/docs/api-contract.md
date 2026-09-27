# Wayfare API Contract v1

Source of truth for the iOS app (`ios/`) and the Cloudflare Worker (`backend/`).
Change this file first, then the code.

## Conventions

- Base URL: `https://<worker>.workers.dev` (configurable in the app: `API_BASE_URL` in `Config.xcconfig`).
- All bodies are JSON (`Content-Type: application/json`). Keys are **camelCase**.
- IDs are lowercase UUID strings. **The client generates IDs** for trips and items (this enables offline creation).
- Instants: ISO-8601 UTC **without fractional seconds**, e.g. `"2026-10-01T14:30:00Z"`.
- Calendar dates: `"YYYY-MM-DD"`.
- `updatedAt` / `deletedAt` / `cursor`: integer **milliseconds since epoch**, assigned by the server.
- Time zones: IANA identifiers (`"Europe/Lisbon"`).
- Auth: `Authorization: Bearer <sessionToken>` on every endpoint except `/v1/health` and `/v1/auth/apple`.
- Errors: HTTP 4xx/5xx with body `{ "error": { "code": "string", "message": "human readable" } }`.
  Codes: `unauthorized`, `forbidden`, `not_found`, `bad_request`, `conflict`, `rate_limited`, `internal`.
- Deletes are soft. Deleted rows come back from `/v1/sync` with a non-null `deletedAt` (tombstones).
- Conflict policy: last write wins, ordered by the time the server receives the write.

## Objects

### User
```json
{ "id": "uuid", "displayName": "Nick", "email": "x@privaterelay.appleid.com", "createdAt": 1727000000000 }
```

### Trip
```json
{
  "id": "uuid",
  "ownerId": "uuid",
  "title": "Lisbon & Porto",
  "destination": "Portugal",
  "startDate": "2026-10-01",
  "endDate": "2026-10-09",
  "timeZone": "Europe/Lisbon",
  "coverEmoji": "🇵🇹",
  "colorHex": "#2F6FEB",
  "notes": "",
  "updatedAt": 1727000000000,
  "deletedAt": null
}
```
Client-writable fields: `title, destination, startDate, endDate, timeZone, coverEmoji, colorHex, notes`.

### Item (an itinerary entry)
```json
{
  "id": "uuid",
  "tripId": "uuid",
  "kind": "flight",
  "title": "TP 202 JFK → LIS",
  "startAt": "2026-10-01T22:30:00Z",
  "endAt":   "2026-10-02T09:45:00Z",
  "startTimeZone": "America/New_York",
  "endTimeZone": "Europe/Lisbon",
  "allDay": false,
  "locationName": "JFK Terminal 1",
  "address": "",
  "latitude": 40.6413,
  "longitude": -73.7781,
  "confirmationCode": "ABC123",
  "details": { "airline": "TAP", "flightNumber": "TP202", "fromCode": "JFK", "toCode": "LIS", "seat": "14A" },
  "notes": "",
  "reminderMinutes": 180,
  "sortIndex": 0,
  "updatedAt": 1727000000000,
  "updatedBy": "uuid",
  "deletedAt": null
}
```
- `kind` ∈ `flight | lodging | activity | food | transport | note`.
- `startAt` is required. `endAt` may be null.
- `endTimeZone` may be null. When null, it defaults to `startTimeZone`.
- `details` is a free-form string→string map. Suggested keys:
  - flight: `airline, flightNumber, fromCode, toCode, terminal, gate, seat`
  - lodging: `phone, checkInTime, checkOutTime, roomType`
  - transport: `mode (train|bus|car|ferry|rideshare|other), operator, fromName, toName, seat`
  - activity/food: `phone, website, bookingUrl, partySize`
- Lodging uses `startAt` = check-in and `endAt` = check-out.
- `reminderMinutes`: null means no reminder. The **device** schedules this as a local notification.
- Client-writable fields: every field except `updatedAt`, `updatedBy`, `deletedAt`.

### Member
```json
{ "tripId": "uuid", "userId": "uuid", "displayName": "Sam", "role": "editor", "updatedAt": 1727000000000, "deletedAt": null }
```
`role` ∈ `owner | editor | viewer`. Viewers may not write items or trips.

## Endpoints

### `GET /v1/health` → `200 { "ok": true, "version": "1" }`

### `POST /v1/auth/apple`
Request: `{ "identityToken": "<JWT from Sign in with Apple>", "displayName": "Nick" | null }`
The server verifies the JWT against Apple's JWKS (`iss` = `https://appleid.apple.com`, `aud` = env `APPLE_BUNDLE_ID`, not expired).
It upserts the user by Apple `sub`. `displayName` is only saved when provided (Apple sends the name only on first sign-in).
Response `200`: `{ "token": "opaque-session-token", "user": User }`

### `GET /v1/me` → `200 User`
### `PATCH /v1/me` body `{ "displayName": "..." }` → `200 User`
### `DELETE /v1/me` → `204`
Deletes the account and all data the user owns, and removes them from shared trips. **Required by App Store Review Guideline 5.1.1(v).**

### `POST /v1/auth/logout` → `204` (revokes the current session token)

### `PUT /v1/devices/current`
Request: `{ "apnsToken": "hex", "environment": "sandbox" | "production", "timeZone": "America/New_York", "briefingEnabled": true, "briefingHour": 7, "collabAlertsEnabled": true }`
Upserts the device, keyed by `apnsToken`. Response `200 { "ok": true }`.

### `GET /v1/sync?since=<cursor>`
`since` is optional (0 or omitted means everything). Returns every trip, item, and member row visible to the user with `updatedAt > since`, tombstones included.
When the user has been removed from a trip, that trip is returned as a tombstone (`deletedAt` set) so the client drops it.
Response `200`:
```json
{ "trips": [Trip], "items": [Item], "members": [Member], "cursor": 1727000000000 }
```
The client stores `cursor` and sends it next time.

### `PUT /v1/trips/:tripId`
Upsert. Body: the writable Trip fields. If the trip doesn't exist, it is created with the caller as `owner`.
Response `200 Trip`. `403` if the caller is a viewer or not a member of an existing trip.

### `DELETE /v1/trips/:tripId` → `204`. Owner only. Soft-deletes the trip and all its items.

### `PUT /v1/trips/:tripId/items/:itemId`
Upsert. Body: the writable Item fields. Response `200 Item`.
Side effect: sends a push to the trip's **other** members' devices that have `collabAlertsEnabled`, e.g. "Sam added “Dinner at Taberna” to Lisbon & Porto". Pushes are coalesced: at most 1 per trip per recipient per 2 minutes.

### `DELETE /v1/trips/:tripId/items/:itemId` → `204`

### `POST /v1/trips/:tripId/invites`
Request: `{ "role": "editor" | "viewer" }`. Owner/editor only.
Response `200 { "code": "8-char code", "url": "wayfare://invite/<code>", "expiresAt": "ISO instant" }`. Codes expire after 7 days.

### `POST /v1/invites/:code/accept` → `200 Trip` (idempotent if already a member). `404` if the code is unknown or expired.

### `DELETE /v1/trips/:tripId/members/:userId` → `204`
The owner can remove anyone except themselves. Any member can remove themselves (leave).

### `POST /v1/trips/:tripId/import`
AI import. Request: `{ "text": "pasted confirmation email or notes, ≤ 20,000 chars" }`.
The server calls the Anthropic API (key in env `ANTHROPIC_API_KEY`) and returns **draft** items. Nothing is saved. The client shows them for review, then PUTs the ones the user accepts.
Response `200 { "items": [ItemDraft] }`, where `ItemDraft` = the Item writable fields minus `id`, `tripId`, `sortIndex`.
Rate limit: 30 imports per user per day → `429 rate_limited`.

## Server-initiated push notifications (APNs)

| Type | Trigger | `aps` payload | Custom keys |
|---|---|---|---|
| Collaborator change | Another member creates or edits an item | alert title = trip title, body = "Sam added …" | `type: "itemChanged", tripId, itemId` |
| Daily briefing | Hourly cron. For each device with `briefingEnabled`, when the local hour == `briefingHour` and the user has a trip where today (in the trip's time zone) is between `startDate` and `endDate` | title "Today in Lisbon", body "3 plans · first: Breakfast at 8:30" | `type: "briefing", tripId, date` |

The app deep-links on tap: `tripId` opens the trip, `itemId` opens the item.
When APNs returns `410` or `BadDeviceToken`, the server deletes that device row.
