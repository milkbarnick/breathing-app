/**
 * Wayfare API: Cloudflare Worker entry point.
 *
 * You do not need to read this code to run it. See README.md for setup.
 *
 *  fetch     -> the JSON API described in docs/api-contract.md
 *  scheduled -> the hourly cron (daily briefing pushes + housekeeping)
 */
import { Router } from './router.js';
import { json, errorResponse, HttpError, API_VERSION } from './util.js';
import { authenticate } from './auth.js';
import { signInWithApple, logout, getMe, patchMe, deleteMe } from './account.js';
import { putDevice } from './devices.js';
import { getSync } from './sync.js';
import { putTrip, deleteTrip } from './trips.js';
import { putItem, deleteItem } from './items.js';
import { createInvite, acceptInvite, removeMember } from './invites.js';
import { importItems } from './importer.js';
import { runBriefings, housekeeping } from './briefing.js';

export const router = new Router()
  .add('GET', '/v1/health', async () => json({ ok: true, version: API_VERSION }), { auth: false })
  .add('POST', '/v1/auth/apple', signInWithApple, { auth: false })
  .add('POST', '/v1/auth/logout', logout)
  .add('GET', '/v1/me', getMe)
  .add('PATCH', '/v1/me', patchMe)
  .add('DELETE', '/v1/me', deleteMe)
  .add('PUT', '/v1/devices/current', putDevice)
  .add('GET', '/v1/sync', getSync)
  .add('PUT', '/v1/trips/:tripId', putTrip)
  .add('DELETE', '/v1/trips/:tripId', deleteTrip)
  .add('PUT', '/v1/trips/:tripId/items/:itemId', putItem)
  .add('DELETE', '/v1/trips/:tripId/items/:itemId', deleteItem)
  .add('POST', '/v1/trips/:tripId/invites', createInvite)
  .add('POST', '/v1/invites/:code/accept', acceptInvite)
  .add('DELETE', '/v1/trips/:tripId/members/:userId', removeMember)
  .add('POST', '/v1/trips/:tripId/import', (c) => importItems(c));

export async function handleRequest(request, env, ctx) {
  try {
    const url = new URL(request.url);
    const matched = router.match(request.method, url.pathname);
    if (!matched) throw new HttpError('not_found', 'No such endpoint.');
    const c = { request, env, ctx, params: matched.params, user: null, tokenHash: null };
    if (matched.route.auth) {
      const session = await authenticate(request, env, ctx);
      c.user = session.user;
      c.tokenHash = session.tokenHash;
    }
    return await matched.route.handler(c);
  } catch (err) {
    if (!(err instanceof HttpError)) console.error('Unhandled error', err && err.stack ? err.stack : err);
    return errorResponse(err);
  }
}

export default {
  fetch(request, env, ctx) {
    return handleRequest(request, env, ctx);
  },

  scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        try {
          const sent = await runBriefings(env, event.scheduledTime || Date.now());
          if (sent) console.log(`Daily briefing: ${sent} push(es) sent`);
        } catch (err) {
          console.error('Briefing run failed', err && err.stack ? err.stack : err);
        }
        try {
          await housekeeping(env, event.scheduledTime || Date.now());
        } catch (err) {
          console.error('Housekeeping failed', err && err.stack ? err.stack : err);
        }
      })(),
    );
  },
};
