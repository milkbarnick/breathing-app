import { describe, it, expect, beforeEach } from 'vitest';
import { verifyAppleIdentityToken, _resetJwksCache, appleClientSecret, _resetClientSecretCache } from '../src/auth.js';
import { signEs256Jwt, getApnsJwt, _resetApnsCache, isDeadTokenResponse, sendPush } from '../src/apns.js';
import { stringToBase64Url, base64UrlToBytes, base64UrlToString } from '../src/util.js';
import { makeAppleKeys, makeP8, BUNDLE } from './helpers/keys.js';

describe('Sign in with Apple identity token', () => {
  let apple;
  beforeEach(async () => {
    _resetJwksCache();
    apple = await makeAppleKeys();
  });
  const nowMs = Date.UTC(2026, 9, 1, 12, 0, 0);
  const nowS = nowMs / 1000;
  const good = () => ({ iss: 'https://appleid.apple.com', aud: BUNDLE, sub: '001234.abc', iat: nowS - 10, exp: nowS + 600, email: 'x@privaterelay.appleid.com' });

  it('accepts a valid token', async () => {
    const claims = await verifyAppleIdentityToken(await apple.sign(good()), { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch });
    expect(claims.sub).toBe('001234.abc');
  });
  it('caches the JWKS', async () => {
    await verifyAppleIdentityToken(await apple.sign(good()), { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch });
    await verifyAppleIdentityToken(await apple.sign(good()), { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch });
    expect(apple.fetchCount()).toBe(1);
  });
  it.each([
    ['wrong audience', { aud: 'com.other.app' }, /different app/],
    ['wrong issuer', { iss: 'https://evil.example' }, /issuer/],
    ['expired', { exp: nowS - 3600 }, /expired/],
    ['no subject', { sub: '' }, /subject/],
  ])('rejects %s', async (_n, patch, msg) => {
    await expect(
      verifyAppleIdentityToken(await apple.sign({ ...good(), ...patch }), { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch }),
    ).rejects.toMatchObject({ status: 401, message: expect.stringMatching(msg) });
  });
  it('rejects a tampered payload', async () => {
    const [h, , s] = (await apple.sign(good())).split('.');
    const forged = `${h}.${stringToBase64Url(JSON.stringify({ ...good(), sub: 'someone-else' }))}.${s}`;
    await expect(verifyAppleIdentityToken(forged, { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch })).rejects.toMatchObject({ status: 401 });
  });
  it('rejects a token signed by an unknown key', async () => {
    const other = await makeAppleKeys('other-kid');
    await expect(
      verifyAppleIdentityToken(await other.sign(good()), { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch }),
    ).rejects.toMatchObject({ status: 401 });
  });
  it('rejects alg=none and garbage', async () => {
    const none = `${stringToBase64Url('{"alg":"none","kid":"k"}')}.${stringToBase64Url(JSON.stringify(good()))}.`;
    await expect(verifyAppleIdentityToken(none, { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch })).rejects.toMatchObject({ status: 401 });
    await expect(verifyAppleIdentityToken('abc', { bundleId: BUNDLE, nowMs, fetchImpl: apple.fetch })).rejects.toMatchObject({ status: 401 });
  });
});

describe('ES256 signing (APNs + Apple client secret)', () => {
  beforeEach(() => {
    _resetApnsCache();
    _resetClientSecretCache();
  });

  it('produces a JWT verifiable with the public key (raw r||s signature)', async () => {
    const { pem, publicKey } = await makeP8();
    const jwt = await signEs256Jwt({ kid: 'KEY123' }, { iss: 'TEAM', iat: 1 }, pem);
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(base64UrlToString(h))).toEqual({ kid: 'KEY123', alg: 'ES256' });
    expect(base64UrlToBytes(s).length).toBe(64);
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, base64UrlToBytes(s), new TextEncoder().encode(`${h}.${p}`));
    expect(ok).toBe(true);
  });

  it('caches the APNs provider token for ~50 minutes', async () => {
    const { pem } = await makeP8();
    const env = { APNS_PRIVATE_KEY: pem, APNS_KEY_ID: 'K', APNS_TEAM_ID: 'T' };
    const t0 = Date.UTC(2026, 0, 1);
    const a = await getApnsJwt(env, t0);
    expect(await getApnsJwt(env, t0 + 49 * 60000)).toBe(a);
    expect(await getApnsJwt(env, t0 + 51 * 60000)).not.toBe(a);
    expect(JSON.parse(base64UrlToString(a.split('.')[1]))).toEqual({ iss: 'T', iat: t0 / 1000 });
  });

  it('builds the Sign in with Apple client secret with the right claims', async () => {
    const { pem } = await makeP8();
    const nowMs = Date.UTC(2026, 0, 1);
    const env = { APPLE_SIWA_PRIVATE_KEY: pem, APPLE_SIWA_KEY_ID: 'SIWAKEY', APPLE_TEAM_ID: 'TEAM', APPLE_BUNDLE_ID: BUNDLE };
    const jwt = await appleClientSecret(env, nowMs);
    const [h, p] = jwt.split('.');
    expect(JSON.parse(base64UrlToString(h))).toEqual({ kid: 'SIWAKEY', alg: 'ES256' });
    const claims = JSON.parse(base64UrlToString(p));
    expect(claims).toMatchObject({ iss: 'TEAM', sub: BUNDLE, aud: 'https://appleid.apple.com', iat: nowMs / 1000 });
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(180 * 86400);
  });

  it('sends pushes with the right host and headers', async () => {
    const { pem } = await makeP8();
    const env = { APNS_PRIVATE_KEY: pem, APNS_KEY_ID: 'K', APNS_TEAM_ID: 'T', APNS_TOPIC: BUNDLE };
    const calls = [];
    const fetchImpl = async (url, init) => {
      calls.push({ url, init });
      return new Response(JSON.stringify({ reason: 'BadDeviceToken' }), { status: 400 });
    };
    const r = await sendPush(env, { apns_token: 'ab'.repeat(32), environment: 'sandbox' }, { aps: {} }, { fetchImpl, collapseId: 'c' });
    expect(calls[0].url).toBe(`https://api.sandbox.push.apple.com/3/device/${'ab'.repeat(32)}`);
    expect(calls[0].init.headers).toMatchObject({ 'apns-topic': BUNDLE, 'apns-push-type': 'alert', 'apns-collapse-id': 'c' });
    expect(calls[0].init.headers.authorization).toMatch(/^bearer ey/);
    expect(r).toEqual({ ok: false, status: 400, reason: 'BadDeviceToken' });
    expect(isDeadTokenResponse(r.status, r.reason)).toBe(true);
    expect(isDeadTokenResponse(410, 'Unregistered')).toBe(true);
    expect(isDeadTokenResponse(429, 'TooManyRequests')).toBe(false);
  });
});

