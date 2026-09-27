import { describe, it, expect } from 'vitest';
import {
  bytesToBase64Url, base64UrlToBytes, stringToBase64Url, base64UrlToString, isoInstant, errorResponse,
  HttpError, newSessionToken, sha256Hex, pemToDer, readJson,
} from '../src/util.js';
import { Router } from '../src/router.js';

describe('base64url', () => {
  it('round-trips bytes of every length without padding or +/', () => {
    for (let n = 0; n < 40; n++) {
      const bytes = new Uint8Array(n).map((_, i) => (i * 37 + 250) & 255);
      const enc = bytesToBase64Url(bytes);
      expect(enc).not.toMatch(/[+/=]/);
      expect([...base64UrlToBytes(enc)]).toEqual([...bytes]);
    }
  });
  it('round-trips unicode strings', () => {
    expect(base64UrlToString(stringToBase64Url('Lisbon → Porto 🇵🇹'))).toBe('Lisbon → Porto 🇵🇹');
  });
  it('rejects non-base64url input', () => {
    expect(() => base64UrlToBytes('ab+c')).toThrow();
  });
});

describe('tokens and hashing', () => {
  it('session tokens are 32 random bytes in base64url (43 chars) and unique', () => {
    const a = newSessionToken();
    const b = newSessionToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(base64UrlToBytes(a).length).toBe(32);
    expect(a).not.toBe(b);
  });
  it('sha256Hex matches a known vector', async () => {
    expect(await sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
  it('pemToDer tolerates escaped newlines', () => {
    const der = pemToDer('-----BEGIN PRIVATE KEY-----\\nAAEC\\nAw==\\n-----END PRIVATE KEY-----');
    expect([...der]).toEqual([0, 1, 2, 3]);
  });
});

describe('isoInstant', () => {
  it('drops fractional seconds', () => {
    expect(isoInstant(Date.UTC(2026, 9, 1, 14, 30, 0, 123))).toBe('2026-10-01T14:30:00Z');
  });
});

describe('errors', () => {
  it('uses the contract error shape', async () => {
    const r = errorResponse(new HttpError('forbidden', 'Nope'));
    expect(r.status).toBe(403);
    expect(await r.json()).toEqual({ error: { code: 'forbidden', message: 'Nope' } });
  });
  it('never leaks internal error details', async () => {
    const r = errorResponse(new Error('SQLITE_ERROR: no such table: secrets at line 42'));
    expect(r.status).toBe(500);
    const body = await r.json();
    expect(body.error.code).toBe('internal');
    expect(JSON.stringify(body)).not.toContain('SQLITE');
  });
  it('readJson rejects non-objects and bad JSON with 400', async () => {
    const mk = (b) => new Request('https://x/', { method: 'POST', body: b });
    await expect(readJson(mk('[1]'))).rejects.toMatchObject({ status: 400 });
    await expect(readJson(mk('{bad'))).rejects.toMatchObject({ status: 400 });
    await expect(readJson(mk(''))).rejects.toMatchObject({ status: 400 });
    expect(await readJson(mk('{"a":1}'))).toEqual({ a: 1 });
  });
});

describe('router', () => {
  const r = new Router().add('GET', '/v1/health', 'h').add('PUT', '/v1/trips/:tripId/items/:itemId', 'item');
  it('matches params', () => {
    const m = r.match('PUT', '/v1/trips/abc/items/def');
    expect(m.route.handler).toBe('item');
    expect(m.params).toEqual({ tripId: 'abc', itemId: 'def' });
  });
  it('is method- and length-sensitive', () => {
    expect(r.match('GET', '/v1/trips/abc/items/def')).toBeNull();
    expect(r.match('PUT', '/v1/trips/abc/items')).toBeNull();
    expect(r.match('GET', '/v1/health/')).not.toBeNull();
  });
  it('treats bad percent-encoding as no match', () => {
    expect(r.match('PUT', '/v1/trips/%E0%A4%A/items/x')).toBeNull();
  });
});
