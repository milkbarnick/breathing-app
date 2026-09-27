/** Test key material: a fake Apple JWKS signer and a generated .p8. */
import { bytesToBase64Url, stringToBase64Url } from '../../src/util.js';

export const BUNDLE = 'com.wayfare.app';

export async function makeAppleKeys(kid = 'test-kid') {
  const { privateKey, publicKey } = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const jwk = await crypto.subtle.exportKey('jwk', publicKey);
  let count = 0;
  return {
    kid,
    async sign(claims) {
      const input = `${stringToBase64Url(JSON.stringify({ alg: 'RS256', kid }))}.${stringToBase64Url(JSON.stringify(claims))}`;
      const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(input));
      return `${input}.${bytesToBase64Url(sig)}`;
    },
    fetch: async () => {
      count++;
      return new Response(JSON.stringify({ keys: [{ kty: 'RSA', kid, use: 'sig', alg: 'RS256', n: jwk.n, e: jwk.e }] }));
    },
    fetchCount: () => count,
  };
}

export async function makeP8() {
  const { privateKey, publicKey } = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', privateKey));
  const b64 = btoa(String.fromCharCode(...der));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return { pem, publicKey };
}
