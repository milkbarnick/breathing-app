/**
 * Strava + Whoop proxy, plus cross-device sync store, for the Training Plan app.
 *
 * Why this file exists: browsers are not allowed to call Strava's or
 * Whoop's APIs directly (neither sends the CORS headers a browser
 * requires, and both OAuth token exchanges need a Client Secret, which
 * must never be shipped inside a public web page). This tiny Cloudflare
 * Worker sits in between: the app talks to this Worker, and this Worker
 * talks to Strava/Whoop on its behalf, adding the CORS headers the
 * browser needs and keeping your Client Secrets out of the page entirely.
 *
 * It also doubles as a tiny sync store: the app pushes its full local
 * state (settings, plans, logs) here after every change and pulls it on
 * load, so opening the app on a second device picks up the same data
 * instead of starting from an empty localStorage.
 *
 * You do not need to write or understand this code. Deploy it by pasting
 * it into the Cloudflare dashboard (see TRAINING_PLAN_SETUP.md) and set:
 *   - STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET (environment variables)
 *   - WHOOP_CLIENT_ID / WHOOP_CLIENT_SECRET (environment variables, only
 *     needed if you're connecting Whoop)
 *   - SYNC_SECRET (an environment variable — a passphrase you make up;
 *     mark it "Encrypt". Enter the same passphrase in the app's Settings
 *     on every device you use.)
 *   - a KV namespace binding named DATA_KV (Settings -> Bindings -> KV
 *     Namespace on the Worker)
 * See TRAINING_PLAN_SETUP.md for exact steps.
 */

const STRAVA_API = 'https://www.strava.com/api/v3';
const STRAVA_TOKEN_URL = 'https://www.strava.com/oauth/token';
const WHOOP_API = 'https://api.prod.whoop.com/developer';
const WHOOP_TOKEN_URL = 'https://api.prod.whoop.com/oauth/oauth2/token';
const SYNC_KV_KEY = 'training-plan-data';

function withCors(resp, origin) {
  const headers = new Headers(resp.headers);
  headers.set('Access-Control-Allow-Origin', origin || '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Sync-Secret');
  headers.set('Access-Control-Max-Age', '86400');
  return new Response(resp.body, { status: resp.status, headers });
}

function checkSyncAuth(request, env, origin) {
  if (!env.SYNC_SECRET) {
    return withCors(new Response(JSON.stringify({ error: 'Worker has no SYNC_SECRET configured' }), { status: 500, headers: { 'Content-Type': 'application/json' } }), origin);
  }
  const provided = request.headers.get('X-Sync-Secret') || '';
  if (provided !== env.SYNC_SECRET) {
    return withCors(new Response(JSON.stringify({ error: 'Invalid sync secret' }), { status: 401, headers: { 'Content-Type': 'application/json' } }), origin);
  }
  return null;
}

async function handleSyncGet(request, env, origin) {
  const authFail = checkSyncAuth(request, env, origin);
  if (authFail) return authFail;
  if (!env.DATA_KV) {
    return withCors(new Response(JSON.stringify({ error: 'Worker has no DATA_KV binding configured' }), { status: 500, headers: { 'Content-Type': 'application/json' } }), origin);
  }
  const stored = await env.DATA_KV.get(SYNC_KV_KEY);
  return withCors(new Response(stored || '{}', { status: 200, headers: { 'Content-Type': 'application/json' } }), origin);
}

async function handleSyncPut(request, env, origin) {
  const authFail = checkSyncAuth(request, env, origin);
  if (authFail) return authFail;
  if (!env.DATA_KV) {
    return withCors(new Response(JSON.stringify({ error: 'Worker has no DATA_KV binding configured' }), { status: 500, headers: { 'Content-Type': 'application/json' } }), origin);
  }
  const body = await request.text();
  try { JSON.parse(body); } catch {
    return withCors(new Response(JSON.stringify({ error: 'Body is not valid JSON' }), { status: 400, headers: { 'Content-Type': 'application/json' } }), origin);
  }
  await env.DATA_KV.put(SYNC_KV_KEY, body);
  return withCors(new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } }), origin);
}

async function handleTokenExchange(request, env, origin) {
  const body = await request.json();
  // .trim() guards against a stray trailing space/newline from copy-pasting
  // the Client ID/Secret into the Cloudflare dashboard — a common invisible
  // cause of Strava rejecting an otherwise-correct client_id.
  const clientId = (env.STRAVA_CLIENT_ID || '').trim();
  const clientSecret = (env.STRAVA_CLIENT_SECRET || '').trim();
  const params = new URLSearchParams({ client_id: clientId, client_secret: clientSecret });

  if (body.grant_type === 'refresh_token') {
    params.set('grant_type', 'refresh_token');
    params.set('refresh_token', body.refresh_token);
  } else {
    params.set('grant_type', 'authorization_code');
    params.set('code', body.code);
  }

  const stravaResp = await fetch(STRAVA_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });

  if (!stravaResp.ok) {
    // On failure, attach non-secret debug info (never the secret itself)
    // so a setup problem can be diagnosed from the app's error toast alone.
    const text = await stravaResp.text();
    let parsed;
    try { parsed = JSON.parse(text); } catch { parsed = { message: text }; }
    parsed._debug = {
      clientIdSet: clientId.length > 0,
      clientIdLength: clientId.length,
      clientIdPreview: clientId ? `${clientId.slice(0, 2)}…${clientId.slice(-2)}` : null,
      clientSecretSet: clientSecret.length > 0,
      clientSecretLength: clientSecret.length,
      grantType: params.get('grant_type'),
    };
    return withCors(new Response(JSON.stringify(parsed), {
      status: stravaResp.status,
      headers: { 'Content-Type': 'application/json' },
    }), origin);
  }

  return withCors(stravaResp, origin);
}

async function handleApiProxy(request, env, origin, pathname) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return withCors(new Response('Missing Authorization header', { status: 401 }), origin);
  }
  const url = new URL(request.url);
  const target = STRAVA_API + pathname.replace(/^\/api/, '') + url.search;
  const stravaResp = await fetch(target, {
    method: 'GET',
    headers: { Authorization: authHeader },
  });
  return withCors(stravaResp, origin);
}

async function handleWhoopTokenExchange(request, env, origin) {
  const body = await request.json();
  const clientId = (env.WHOOP_CLIENT_ID || '').trim();
  const clientSecret = (env.WHOOP_CLIENT_SECRET || '').trim();
  const params = new URLSearchParams({ client_id: clientId, client_secret: clientSecret });

  if (body.grant_type === 'refresh_token') {
    params.set('grant_type', 'refresh_token');
    params.set('refresh_token', body.refresh_token);
    params.set('scope', 'offline read:recovery read:cycles read:sleep read:profile read:workout');
  } else {
    params.set('grant_type', 'authorization_code');
    params.set('code', body.code);
    // Whoop, unlike Strava, requires redirect_uri again on the token
    // exchange — it must match what was sent to the authorize step.
    params.set('redirect_uri', body.redirect_uri || '');
  }

  const whoopResp = await fetch(WHOOP_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });

  if (!whoopResp.ok) {
    const text = await whoopResp.text();
    let parsed;
    try { parsed = JSON.parse(text); } catch { parsed = { message: text }; }
    parsed._debug = {
      clientIdSet: clientId.length > 0,
      clientIdLength: clientId.length,
      clientIdPreview: clientId ? `${clientId.slice(0, 2)}…${clientId.slice(-2)}` : null,
      clientSecretSet: clientSecret.length > 0,
      clientSecretLength: clientSecret.length,
      grantType: params.get('grant_type'),
      redirectUriSent: params.get('redirect_uri') || null,
    };
    return withCors(new Response(JSON.stringify(parsed), {
      status: whoopResp.status,
      headers: { 'Content-Type': 'application/json' },
    }), origin);
  }

  return withCors(whoopResp, origin);
}

async function handleWhoopApiProxy(request, env, origin, pathname) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return withCors(new Response('Missing Authorization header', { status: 401 }), origin);
  }
  const url = new URL(request.url);
  const target = WHOOP_API + pathname.replace(/^\/whoop\/api/, '') + url.search;
  const whoopResp = await fetch(target, {
    method: 'GET',
    headers: { Authorization: authHeader },
  });
  return withCors(whoopResp, origin);
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '*';
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return withCors(new Response(null, { status: 204 }), origin);
    }

    try {
      if (url.pathname === '/token' && request.method === 'POST') {
        return await handleTokenExchange(request, env, origin);
      }
      if (url.pathname.startsWith('/api/') && request.method === 'GET') {
        return await handleApiProxy(request, env, origin, url.pathname);
      }
      if (url.pathname === '/whoop/token' && request.method === 'POST') {
        return await handleWhoopTokenExchange(request, env, origin);
      }
      if (url.pathname.startsWith('/whoop/api/') && request.method === 'GET') {
        return await handleWhoopApiProxy(request, env, origin, url.pathname);
      }
      if (url.pathname === '/sync' && request.method === 'GET') {
        return await handleSyncGet(request, env, origin);
      }
      if (url.pathname === '/sync' && request.method === 'PUT') {
        return await handleSyncPut(request, env, origin);
      }
      return withCors(new Response('Not found', { status: 404 }), origin);
    } catch (err) {
      return withCors(new Response('Proxy error: ' + err.message, { status: 500 }), origin);
    }
  },
};
