/**
 * Strava proxy for the Training Plan app.
 *
 * Why this file exists: browsers are not allowed to call Strava's API
 * directly (Strava does not send the CORS headers a browser requires,
 * and the OAuth token exchange needs your Client Secret, which must never
 * be shipped inside a public web page). This tiny Cloudflare Worker sits
 * in between: the app talks to this Worker, and this Worker talks to
 * Strava on its behalf, adding the CORS headers the browser needs and
 * keeping your Client Secret out of the page entirely.
 *
 * You do not need to write or understand this code. Deploy it by pasting
 * it into the Cloudflare dashboard (see TRAINING_PLAN_SETUP.md) and set
 * two environment variables on the Worker: STRAVA_CLIENT_ID and
 * STRAVA_CLIENT_SECRET. That's it.
 */

const STRAVA_API = 'https://www.strava.com/api/v3';
const STRAVA_TOKEN_URL = 'https://www.strava.com/oauth/token';

function withCors(resp, origin) {
  const headers = new Headers(resp.headers);
  headers.set('Access-Control-Allow-Origin', origin || '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  headers.set('Access-Control-Max-Age', '86400');
  return new Response(resp.body, { status: resp.status, headers });
}

async function handleTokenExchange(request, env, origin) {
  const body = await request.json();
  const params = new URLSearchParams({
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
  });

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
      return withCors(new Response('Not found', { status: 404 }), origin);
    } catch (err) {
      return withCors(new Response('Proxy error: ' + err.message, { status: 500 }), origin);
    }
  },
};
