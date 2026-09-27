/**
 * End-to-end tests of the Worker's fetch handler against the real migration SQL
 * (in-memory SQLite standing in for D1). Apple, APNs and Anthropic are mocked
 * at the fetch() boundary.
 */
import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from 'vitest';
import { handleRequest } from '../src/index.js';
import { runBriefings } from '../src/briefing.js';
import { FakeD1 } from './helpers/d1.js';
import { makeAppleKeys, makeP8, BUNDLE } from './helpers/keys.js';

const T1 = '11111111-1111-4111-8111-111111111111';
const T2 = '22222222-2222-4222-8222-222222222222';
const I1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const I2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const TOKEN_A = 'a1'.repeat(32);
const TOKEN_B = 'b2'.repeat(32);

const TRIP = { title: 'Lisbon & Porto', destination: 'Lisbon', startDate: '2026-10-01', endDate: '2026-10-09', timeZone: 'Europe/Lisbon', coverEmoji: '🇵🇹', colorHex: '#2F6FEB', notes: 'secret notes' };
const ITEM = {
  kind: 'food', title: 'Dinner at Taberna', startAt: '2026-10-02T19:00:00Z', endAt: null, startTimeZone: 'Europe/Lisbon',
  endTimeZone: null, allDay: false, locationName: 'Taberna', address: '', latitude: null, longitude: null,
  confirmationCode: '', details: { partySize: '2' }, notes: '', reminderMinutes: null, sortIndex: 0,
};

let apple;
let p8;
let env;
let pending;
let clock;
let log; // outbound fetches
let deadTokens;
let anthropicReply;

const ctx = { waitUntil: (p) => pending.push(p) };

async function call(method, path, { token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await handleRequest(
    new Request(`https://api.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }),
    env,
    ctx,
  );
  await Promise.all(pending.splice(0));
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

async function signIn(sub, displayName = null, authorizationCode = null) {
  const nowS = Math.floor(clock / 1000);
  const identityToken = await apple.sign({ iss: 'https://appleid.apple.com', aud: BUNDLE, sub, iat: nowS, exp: nowS + 600, email: `${sub}@privaterelay.appleid.com` });
  const r = await call('POST', '/v1/auth/apple', { body: { identityToken, displayName, authorizationCode } });
  expect(r.status).toBe(200);
  return r.body;
}

const pushes = () => log.filter((c) => c.url.includes('push.apple.com'));
const advance = (ms) => {
  clock += ms;
};

beforeAll(async () => {
  apple = await makeAppleKeys();
  p8 = (await makeP8()).pem;
});

beforeEach(() => {
  pending = [];
  log = [];
  deadTokens = new Set();
  clock = Date.UTC(2026, 9, 2, 5, 0, 0); // 06:00 in Lisbon, during the trip
  vi.spyOn(Date, 'now').mockImplementation(() => clock);
  anthropicReply = { stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify({ items: [] }) }] };
  env = {
    DB: new FakeD1(),
    APPLE_BUNDLE_ID: BUNDLE,
    APNS_TOPIC: BUNDLE,
    APNS_KEY_ID: 'APNSKEY',
    APNS_TEAM_ID: 'TEAM',
    APNS_PRIVATE_KEY: p8,
    APPLE_TEAM_ID: 'TEAM',
    APPLE_SIWA_KEY_ID: 'SIWAKEY',
    APPLE_SIWA_PRIVATE_KEY: p8,
    ANTHROPIC_API_KEY: 'sk-ant-test',
  };
  vi.stubGlobal('fetch', async (url, init = {}) => {
    url = String(url);
    log.push({ url, init });
    if (url === 'https://appleid.apple.com/auth/keys') return apple.fetch();
    if (url === 'https://appleid.apple.com/auth/token') return new Response(JSON.stringify({ refresh_token: 'apple-refresh-1', access_token: 'x' }));
    if (url === 'https://appleid.apple.com/auth/revoke') return new Response('', { status: 200 });
    if (url.includes('push.apple.com/3/device/')) {
      const tok = url.split('/').pop();
      return deadTokens.has(tok) ? new Response(JSON.stringify({ reason: 'Unregistered' }), { status: 410 }) : new Response('', { status: 200 });
    }
    if (url === 'https://api.anthropic.com/v1/messages') return new Response(JSON.stringify(anthropicReply));
    throw new Error(`unexpected fetch ${url}`);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

/** Owner A with trip T1 and item I1, editor B joined via invite, both with devices. */
async function sharedTrip({ role = 'editor' } = {}) {
  const a = await signIn('apple-a', 'Nick', 'code-a');
  const b = await signIn('apple-b', 'Sam');
  expect((await call('PUT', `/v1/trips/${T1}`, { token: a.token, body: TRIP })).status).toBe(200);
  expect((await call('PUT', `/v1/trips/${T1}/items/${I1}`, { token: a.token, body: ITEM })).status).toBe(200);
  const inv = await call('POST', `/v1/trips/${T1}/invites`, { token: a.token, body: { role } });
  expect(inv.status).toBe(200);
  expect((await call('POST', `/v1/invites/${inv.body.code}/accept`, { token: b.token })).status).toBe(200);
  for (const [who, tok] of [[a, TOKEN_A], [b, TOKEN_B]]) {
    const r = await call('PUT', '/v1/devices/current', {
      token: who.token,
      body: { apnsToken: tok, environment: 'production', timeZone: 'Europe/Lisbon', briefingEnabled: true, briefingHour: 7, collabAlertsEnabled: true },
    });
    expect(r).toEqual({ status: 200, body: { ok: true } });
  }
  log.length = 0;
  advance(10_000);
  return { a, b, code: inv.body.code };
}

describe('basics', () => {
  it('health is public', async () => {
    expect(await call('GET', '/v1/health')).toEqual({ status: 200, body: { ok: true, version: '1' } });
  });
  it('everything else needs a valid bearer token', async () => {
    const r = await call('GET', '/v1/me');
    expect(r.status).toBe(401);
    expect(r.body.error.code).toBe('unauthorized');
    expect((await call('GET', '/v1/me', { token: 'x'.repeat(43) })).status).toBe(401);
  });
  it('unknown routes are 404 in the contract shape', async () => {
    const r = await call('GET', '/v1/nope');
    expect(r).toEqual({ status: 404, body: { error: { code: 'not_found', message: 'No such endpoint.' } } });
  });
});

describe('auth and account', () => {
  it('signs in, keeps displayName when Apple omits it, and stores the refresh token', async () => {
    const first = await signIn('apple-a', 'Nick', 'code-1');
    expect(first.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(first.user).toMatchObject({ displayName: 'Nick', email: 'apple-a@privaterelay.appleid.com', createdAt: clock });
    const second = await signIn('apple-a', null);
    expect(second.user.id).toBe(first.user.id);
    expect(second.user.displayName).toBe('Nick');
    const row = await env.DB.prepare('SELECT apple_refresh_token FROM users WHERE id = ?').bind(first.user.id).first();
    expect(row.apple_refresh_token).toBe('apple-refresh-1');
    const exchange = log.find((c) => c.url.endsWith('/auth/token'));
    const form = new URLSearchParams(exchange.init.body);
    expect(form.get('grant_type')).toBe('authorization_code');
    expect(form.get('client_id')).toBe(BUNDLE);
    expect(form.get('code')).toBe('code-1');
    expect(form.get('client_secret').split('.')).toHaveLength(3);
    // only the hash of the session token is stored
    const s = await env.DB.prepare('SELECT token_hash FROM sessions').all();
    expect(s.results.map((r) => r.token_hash)).not.toContain(first.token);
  });

  it('a failed code exchange does not fail sign-in', async () => {
    vi.stubGlobal('fetch', async (url) => {
      if (String(url).endsWith('/auth/keys')) return apple.fetch();
      return new Response('{"error":"invalid_grant"}', { status: 400 });
    });
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const r = await signIn('apple-z', 'Zed', 'bad-code');
    expect(r.user.displayName).toBe('Zed');
  });

  it('rejects a bad identity token', async () => {
    const r = await call('POST', '/v1/auth/apple', { body: { identityToken: 'a.b.c' } });
    expect(r.status).toBe(401);
  });

  it('PATCH /v1/me and logout', async () => {
    const a = await signIn('apple-a', 'Nick');
    expect((await call('PATCH', '/v1/me', { token: a.token, body: { displayName: '  Nicky ' } })).body.displayName).toBe('Nicky');
    expect((await call('PATCH', '/v1/me', { token: a.token, body: { displayName: 7 } })).status).toBe(400);
    expect((await call('GET', '/v1/me', { token: a.token })).body.displayName).toBe('Nicky');
    expect((await call('POST', '/v1/auth/logout', { token: a.token })).status).toBe(204);
    expect((await call('GET', '/v1/me', { token: a.token })).status).toBe(401);
  });

  it('logout with apnsToken unregisters only that device of that user', async () => {
    const { a, b } = await sharedTrip();
    expect((await call('POST', '/v1/auth/logout', { token: b.token, body: { apnsToken: TOKEN_A } })).status).toBe(204);
    expect(await env.DB.prepare('SELECT * FROM devices WHERE apns_token = ?').bind(TOKEN_A).first()).not.toBeNull();
    expect((await call('POST', '/v1/auth/logout', { token: a.token, body: { apnsToken: TOKEN_A } })).status).toBe(204);
    expect(await env.DB.prepare('SELECT * FROM devices WHERE apns_token = ?').bind(TOKEN_A).first()).toBeNull();
  });
});

describe('trips and items', () => {
  it('creates, updates and validates trips; accepts uppercase UUIDs', async () => {
    const a = await signIn('apple-a', 'Nick');
    const r = await call('PUT', `/v1/trips/${T1.toUpperCase()}`, { token: a.token, body: TRIP });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ id: T1, ownerId: a.user.id, ...TRIP, updatedAt: clock, deletedAt: null });
    advance(1000);
    const u = await call('PUT', `/v1/trips/${T1}`, { token: a.token, body: { ...TRIP, title: 'Portugal!' } });
    expect(u.body).toMatchObject({ title: 'Portugal!', updatedAt: clock });
    expect((await call('PUT', '/v1/trips/not-a-uuid', { token: a.token, body: TRIP })).status).toBe(400);
    const bad = await call('PUT', `/v1/trips/${T2}`, { token: a.token, body: { ...TRIP, endDate: '2026-09-01' } });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe('bad_request');
  });

  it('upserts items and returns the contract shape', async () => {
    const a = await signIn('apple-a', 'Nick');
    await call('PUT', `/v1/trips/${T1}`, { token: a.token, body: TRIP });
    const r = await call('PUT', `/v1/trips/${T1}/items/${I1}`, { token: a.token, body: ITEM });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ id: I1, tripId: T1, ...ITEM, updatedAt: clock, updatedBy: a.user.id, deletedAt: null });
    expect((await call('PUT', `/v1/trips/${T2}/items/${I1}`, { token: a.token, body: ITEM })).status).toBe(404);
    await call('PUT', `/v1/trips/${T2}`, { token: a.token, body: TRIP });
    expect((await call('PUT', `/v1/trips/${T2}/items/${I1}`, { token: a.token, body: ITEM })).status).toBe(409);
    expect((await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: a.token, body: { ...ITEM, kind: 'boat' } })).status).toBe(400);
  });

  it('delete item is soft and idempotent; delete trip is owner-only and cascades', async () => {
    const { a, b } = await sharedTrip();
    expect((await call('DELETE', `/v1/trips/${T1}/items/${I1}`, { token: b.token })).status).toBe(204);
    expect((await call('DELETE', `/v1/trips/${T1}/items/${I1}`, { token: b.token })).status).toBe(204);
    expect((await call('DELETE', `/v1/trips/${T1}/items/${I2}`, { token: b.token })).status).toBe(404);
    await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: a.token, body: ITEM });
    expect((await call('DELETE', `/v1/trips/${T1}`, { token: b.token })).status).toBe(403);
    expect((await call('DELETE', `/v1/trips/${T1}`, { token: a.token })).status).toBe(204);
    const s = await call('GET', '/v1/sync', { token: b.token });
    expect(s.body.trips[0]).toMatchObject({ id: T1, deletedAt: clock });
    expect(s.body.items.every((i) => i.deletedAt !== null)).toBe(true);
    // A deleted trip can't be edited back to life.
    expect((await call('PUT', `/v1/trips/${T1}`, { token: a.token, body: TRIP })).status).toBe(409);
    expect((await call('PUT', `/v1/trips/${T1}/items/${I1}`, { token: a.token, body: ITEM })).status).toBe(409);
  });
});

describe('permissions', () => {
  it('viewers cannot write; outsiders get 403', async () => {
    const { b } = await sharedTrip({ role: 'viewer' });
    const c = await signIn('apple-c', 'Cat');
    for (const tok of [b.token, c.token]) {
      expect((await call('PUT', `/v1/trips/${T1}`, { token: tok, body: TRIP })).status).toBe(403);
      expect((await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: tok, body: ITEM })).status).toBe(403);
      expect((await call('POST', `/v1/trips/${T1}/invites`, { token: tok, body: { role: 'viewer' } })).status).toBe(403);
      expect((await call('POST', `/v1/trips/${T1}/import`, { token: tok, body: { text: 'x' } })).status).toBe(403);
    }
    // Outsider sees nothing in sync.
    expect((await call('GET', '/v1/sync', { token: c.token })).body).toMatchObject({ trips: [], items: [], members: [] });
  });
});

describe('invites and members', () => {
  it('creates codes and accepts them idempotently and case-insensitively', async () => {
    const { a, b, code } = await sharedTrip();
    expect(code).toMatch(/^[A-HJKMNP-Z2-9]{8}$/);
    const again = await call('POST', `/v1/invites/${code.toLowerCase()}/accept`, { token: b.token });
    expect(again.status).toBe(200);
    expect(again.body.id).toBe(T1);
    // Owner accepting a viewer invite stays owner.
    const v = await call('POST', `/v1/trips/${T1}/invites`, { token: b.token, body: { role: 'viewer' } });
    expect(v.body.url).toBe(`wayfare://invite/${v.body.code}`);
    expect(v.body.expiresAt).toBe(new Date(clock + 7 * 86400000).toISOString().replace('.000Z', 'Z'));
    await call('POST', `/v1/invites/${v.body.code}/accept`, { token: a.token });
    const m = await env.DB.prepare('SELECT role FROM trip_members WHERE user_id = ?').bind(a.user.id).first();
    expect(m.role).toBe('owner');
    expect((await call('POST', '/v1/invites/ZZZZZZZZ/accept', { token: b.token })).status).toBe(404);
    expect((await call('POST', `/v1/trips/${T1}/invites`, { token: a.token, body: { role: 'owner' } })).status).toBe(400);
  });

  it('expired codes are 404', async () => {
    const { code } = await sharedTrip();
    const c = await signIn('apple-c', 'Cat');
    advance(7 * 86400000 + 1);
    expect((await call('POST', `/v1/invites/${code}/accept`, { token: c.token })).status).toBe(404);
  });

  it('removing a member sends them a trip tombstone; rejoining resends everything', async () => {
    const { a, b, code } = await sharedTrip();
    const before = await call('GET', '/v1/sync', { token: b.token });
    expect(before.body.trips.map((t) => t.id)).toEqual([T1]);
    const cursor = before.body.cursor;
    advance(10_000);

    expect((await call('DELETE', `/v1/trips/${T1}/members/${a.user.id}`, { token: a.token })).status).toBe(403); // owner can't leave
    expect((await call('DELETE', `/v1/trips/${T1}/members/${b.user.id}`, { token: a.token })).status).toBe(204);
    const removedAt = clock;
    const after = await call('GET', `/v1/sync?since=${cursor}`, { token: b.token });
    expect(after.body.trips).toHaveLength(1);
    expect(after.body.trips[0]).toMatchObject({ id: T1, deletedAt: removedAt, notes: '' });
    expect(after.body.items).toEqual([]);
    expect(after.body.members).toEqual([expect.objectContaining({ userId: b.user.id, deletedAt: removedAt })]);
    expect((await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: b.token, body: ITEM })).status).toBe(403);

    // Owner's view shows B's member tombstone.
    const ownerSync = await call('GET', `/v1/sync?since=${cursor}`, { token: a.token });
    expect(ownerSync.body.members).toEqual([expect.objectContaining({ userId: b.user.id, displayName: 'Sam', deletedAt: removedAt })]);

    advance(10_000);
    const rejoinCursor = after.body.cursor;
    await call('POST', `/v1/invites/${code}/accept`, { token: b.token });
    const back = await call('GET', `/v1/sync?since=${rejoinCursor}`, { token: b.token });
    expect(back.body.trips).toEqual([expect.objectContaining({ id: T1, deletedAt: null, notes: 'secret notes' })]);
    expect(back.body.items.map((i) => i.id)).toEqual([I1]);
    expect(back.body.members).toHaveLength(2);
  });

  it('members can leave; non-owners cannot remove others', async () => {
    const { a, b } = await sharedTrip();
    expect((await call('DELETE', `/v1/trips/${T1}/members/${a.user.id}`, { token: b.token })).status).toBe(403);
    expect((await call('DELETE', `/v1/trips/${T1}/members/${b.user.id}`, { token: b.token })).status).toBe(204);
    expect((await call('DELETE', `/v1/trips/${T1}/members/${b.user.id}`, { token: b.token })).status).toBe(403);
  });
});

describe('sync', () => {
  it('returns everything on first sync and only changes after the cursor', async () => {
    const { a } = await sharedTrip();
    const full = await call('GET', '/v1/sync', { token: a.token });
    expect(full.body.trips).toHaveLength(1);
    expect(full.body.items).toHaveLength(1);
    expect(full.body.members.map((m) => m.role).sort()).toEqual(['editor', 'owner']);
    expect(full.body.cursor).toBe(clock - 5000);
    advance(10_000);
    const none = await call('GET', `/v1/sync?since=${full.body.cursor}`, { token: a.token });
    expect(none.body).toMatchObject({ trips: [], items: [], members: [] });
    await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: a.token, body: ITEM });
    const delta = await call('GET', `/v1/sync?since=${none.body.cursor}`, { token: a.token });
    expect(delta.body.items.map((i) => i.id)).toEqual([I2]);
    expect(delta.body.trips).toEqual([]);
    expect((await call('GET', '/v1/sync?since=abc', { token: a.token })).status).toBe(400);
  });

  it('a display-name change reaches other members', async () => {
    const { a, b } = await sharedTrip();
    const c0 = (await call('GET', '/v1/sync', { token: a.token })).body.cursor;
    advance(10_000);
    await call('PATCH', '/v1/me', { token: b.token, body: { displayName: 'Samantha' } });
    const d = await call('GET', `/v1/sync?since=${c0}`, { token: a.token });
    expect(d.body.members).toEqual([expect.objectContaining({ userId: b.user.id, displayName: 'Samantha' })]);
  });
});

describe('collaborator push', () => {
  it('pushes to other members, coalesced to 1 per trip per recipient per 2 minutes', async () => {
    const { b } = await sharedTrip();
    await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: b.token, body: { ...ITEM, title: 'Pastéis' } });
    expect(pushes()).toHaveLength(1);
    const p = pushes()[0];
    expect(p.url).toBe(`https://api.push.apple.com/3/device/${TOKEN_A}`);
    expect(JSON.parse(p.init.body)).toEqual({
      aps: { alert: { title: 'Lisbon & Porto', body: 'Sam added “Pastéis” to Lisbon & Porto' }, sound: 'default', 'content-available': 1 },
      type: 'itemChanged', tripId: T1, itemId: I2,
    });
    advance(60_000);
    await call('PUT', `/v1/trips/${T1}/items/${I1}`, { token: b.token, body: ITEM });
    expect(pushes()).toHaveLength(1); // coalesced
    advance(61_000);
    await call('PUT', `/v1/trips/${T1}/items/${I1}`, { token: b.token, body: { ...ITEM, title: 'Dinner moved' } });
    expect(pushes()).toHaveLength(2);
    expect(JSON.parse(pushes()[1].init.body).aps.alert.body).toBe('Sam updated “Dinner moved” in Lisbon & Porto');
  });

  it('never pushes to the author or to members with collab alerts off, and drops dead tokens', async () => {
    const { a, b } = await sharedTrip();
    await call('PUT', '/v1/devices/current', {
      token: a.token,
      body: { apnsToken: TOKEN_A, environment: 'sandbox', timeZone: 'Europe/Lisbon', briefingEnabled: true, briefingHour: 7, collabAlertsEnabled: false },
    });
    await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: b.token, body: ITEM });
    expect(pushes()).toHaveLength(0);
    deadTokens.add(TOKEN_B);
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: a.token, body: ITEM });
    expect(pushes().map((p) => p.url)).toEqual([`https://api.push.apple.com/3/device/${TOKEN_B}`]);
    expect(await env.DB.prepare('SELECT * FROM devices WHERE apns_token = ?').bind(TOKEN_B).first()).toBeNull();
  });
});

describe('daily briefing', () => {
  it('sends once at the device-local briefing hour for in-progress trips', async () => {
    const { a } = await sharedTrip();
    await call('PUT', `/v1/trips/${T1}/items/${I2}`, { token: a.token, body: { ...ITEM, title: 'Breakfast', startAt: '2026-10-02T07:30:00Z' } });
    log.length = 0;
    // 05:00Z = 06:00 Lisbon: not yet.
    expect(await runBriefings(env, Date.UTC(2026, 9, 2, 5, 0, 0))).toBe(0);
    // 06:00Z = 07:00 Lisbon: both devices briefed.
    expect(await runBriefings(env, Date.UTC(2026, 9, 2, 6, 0, 0))).toBe(2);
    const body = JSON.parse(pushes()[0].init.body);
    expect(body).toEqual({
      aps: { alert: { title: 'Today in Lisbon', body: '2 plans · first: Breakfast at 8:30' }, sound: 'default', 'content-available': 1 },
      type: 'briefing', tripId: T1, date: '2026-10-02',
    });
    // A second run in the same hour doesn't repeat it.
    expect(await runBriefings(env, Date.UTC(2026, 9, 2, 6, 30, 0))).toBe(0);
    // Outside the trip: nothing.
    expect(await runBriefings(env, Date.UTC(2026, 9, 20, 6, 0, 0))).toBe(0);
  });
});

describe('AI import', () => {
  it('returns sanitized drafts and saves nothing', async () => {
    const a = await signIn('apple-a', 'Nick');
    await call('PUT', `/v1/trips/${T1}`, { token: a.token, body: TRIP });
    anthropicReply = {
      stop_reason: 'end_turn',
      content: [{ type: 'text', text: JSON.stringify({ items: [{
        kind: 'lodging', title: 'Hotel Avenida Palace', startAt: '2026-10-02T14:00:00Z', endAt: '2026-10-05T11:00:00Z',
        startTimeZone: 'Europe/Lisbon', endTimeZone: null, allDay: false, locationName: 'Hotel Avenida Palace',
        address: 'R. 1º de Dezembro 123, Lisboa', latitude: 38.7148, longitude: -9.1413, confirmationCode: 'HX77',
        details: [{ key: 'roomType', value: 'Double' }], notes: '', reminderMinutes: null,
      }, { kind: 'note', title: 'no date', startAt: 'soon' }] }) }],
    };
    const r = await call('POST', `/v1/trips/${T1}/import`, { token: a.token, body: { text: 'Your booking HX77 ...' } });
    expect(r.status).toBe(200);
    expect(r.body.items).toEqual([expect.objectContaining({ kind: 'lodging', confirmationCode: 'HX77', details: { roomType: 'Double' } })]);
    const req = log.find((c) => c.url.includes('anthropic'));
    expect(req.init.headers).toMatchObject({ 'x-api-key': 'sk-ant-test', 'anthropic-version': '2023-06-01' });
    expect(JSON.parse(req.init.body).messages[0].content).toContain('Your booking HX77');
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM items').first()).n).toBe(0);
    expect((await call('POST', `/v1/trips/${T1}/import`, { token: a.token, body: { text: 'x'.repeat(20001) } })).status).toBe(400);
  });

  it('rate-limits to 30 per user per day and refunds upstream failures', async () => {
    const a = await signIn('apple-a', 'Nick');
    await call('PUT', `/v1/trips/${T1}`, { token: a.token, body: TRIP });
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.stubGlobal('fetch', async () => new Response('{"error":{"type":"overloaded_error","message":"x"}}', { status: 529 }));
    const fail = await call('POST', `/v1/trips/${T1}/import`, { token: a.token, body: { text: 'hi' } });
    expect(fail.status).toBe(502);
    expect(fail.body.error.code).toBe('internal');
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify(anthropicReply)));
    for (let i = 0; i < 30; i++) {
      expect((await call('POST', `/v1/trips/${T1}/import`, { token: a.token, body: { text: 'hi' } })).status).toBe(200);
    }
    const limited = await call('POST', `/v1/trips/${T1}/import`, { token: a.token, body: { text: 'hi' } });
    expect(limited.status).toBe(429);
    expect(limited.body.error.code).toBe('rate_limited');
    advance(86400000);
    expect((await call('POST', `/v1/trips/${T1}/import`, { token: a.token, body: { text: 'hi' } })).status).toBe(200);
  });
});

describe('account deletion', () => {
  it('revokes with Apple, deletes owned data, tombstones shared trips and memberships', async () => {
    const { a, b } = await sharedTrip();
    // A also has a solo trip; B owns a trip A is a member of.
    await call('PUT', `/v1/trips/${T2}`, { token: a.token, body: { ...TRIP, title: 'Solo' } });
    const T3 = '33333333-3333-4333-8333-333333333333';
    await call('PUT', `/v1/trips/${T3}`, { token: b.token, body: { ...TRIP, title: 'Sam trip' } });
    const inv = await call('POST', `/v1/trips/${T3}/invites`, { token: b.token, body: { role: 'editor' } });
    await call('POST', `/v1/invites/${inv.body.code}/accept`, { token: a.token });
    advance(10_000); // step past the 5-second cursor safety window
    const cursor = (await call('GET', '/v1/sync', { token: b.token })).body.cursor;
    advance(10_000);
    log.length = 0;

    expect((await call('DELETE', '/v1/me', { token: a.token })).status).toBe(204);
    const revoke = log.find((c) => c.url.endsWith('/auth/revoke'));
    const form = new URLSearchParams(revoke.init.body);
    expect(form.get('token')).toBe('apple-refresh-1');
    expect(form.get('token_type_hint')).toBe('refresh_token');

    expect((await call('GET', '/v1/me', { token: a.token })).status).toBe(401);
    const db = env.DB;
    const count = async (sql, ...args) => (await db.prepare(sql).bind(...args).first()).n;
    expect(await count('SELECT COUNT(*) AS n FROM users WHERE id = ?', a.user.id)).toBe(0);
    expect(await count('SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?', a.user.id)).toBe(0);
    expect(await count('SELECT COUNT(*) AS n FROM devices WHERE user_id = ?', a.user.id)).toBe(0);
    expect(await count('SELECT COUNT(*) AS n FROM trips WHERE id = ?', T2)).toBe(0); // solo trip gone entirely
    expect(await count('SELECT COUNT(*) AS n FROM items WHERE trip_id = ?', T1)).toBe(0); // shared trip's items erased
    const shared = await db.prepare('SELECT * FROM trips WHERE id = ?').bind(T1).first();
    expect(shared).toMatchObject({ title: '', notes: '', destination: '' });

    // B's next sync: T1 tombstone, and A's membership in T3 tombstoned.
    const s = await call('GET', `/v1/sync?since=${cursor}`, { token: b.token });
    expect(s.body.trips).toEqual([expect.objectContaining({ id: T1, deletedAt: clock, title: '' })]);
    expect(s.body.members).toEqual([expect.objectContaining({ tripId: T3, userId: a.user.id, deletedAt: clock, displayName: '' })]);
    // B can keep using their own trip.
    expect((await call('PUT', `/v1/trips/${T3}/items/${I2}`, { token: b.token, body: ITEM })).status).toBe(200);
  });
});
