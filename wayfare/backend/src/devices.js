/**
 * PUT /v1/devices/current: register / update this iPhone's push settings.
 * Keyed by APNs token. If the same phone signs into another account, the row
 * moves to the new user.
 */
import { json, readJson } from './util.js';
import { validateDeviceInput } from './validate.js';

export async function putDevice({ request, env, user }) {
  const d = validateDeviceInput(await readJson(request));
  await env.DB.prepare(
    `INSERT INTO devices (apns_token, user_id, environment, time_zone, briefing_enabled, briefing_hour,
                          collab_alerts_enabled, last_briefing_date, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, ?8)
     ON CONFLICT (apns_token) DO UPDATE SET
       user_id = excluded.user_id,
       environment = excluded.environment,
       time_zone = excluded.time_zone,
       briefing_enabled = excluded.briefing_enabled,
       briefing_hour = excluded.briefing_hour,
       collab_alerts_enabled = excluded.collab_alerts_enabled,
       last_briefing_date = CASE WHEN devices.user_id = excluded.user_id THEN devices.last_briefing_date ELSE NULL END,
       updated_at = excluded.updated_at`,
  )
    .bind(d.apnsToken, user.id, d.environment, d.timeZone, d.briefingEnabled ? 1 : 0, d.briefingHour,
      d.collabAlertsEnabled ? 1 : 0, Date.now())
    .run();
  return json({ ok: true });
}
