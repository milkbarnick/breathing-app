/**
 * Row (snake_case, D1) -> API object (camelCase, per the contract) mappers.
 */

export function userJson(row) {
  return {
    id: row.id,
    displayName: row.display_name || '',
    email: row.email || null,
    createdAt: row.created_at,
  };
}

export function tripJson(row) {
  return {
    id: row.id,
    ownerId: row.owner_id,
    title: row.title,
    destination: row.destination,
    startDate: row.start_date,
    endDate: row.end_date,
    timeZone: row.time_zone,
    coverEmoji: row.cover_emoji,
    colorHex: row.color_hex,
    notes: row.notes,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at ?? null,
  };
}

function parseDetails(text) {
  try {
    const v = JSON.parse(text || '{}');
    return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
  } catch {
    return {};
  }
}

export function itemJson(row) {
  return {
    id: row.id,
    tripId: row.trip_id,
    kind: row.kind,
    title: row.title,
    startAt: row.start_at,
    endAt: row.end_at ?? null,
    startTimeZone: row.start_time_zone,
    endTimeZone: row.end_time_zone ?? null,
    allDay: Boolean(row.all_day),
    locationName: row.location_name,
    address: row.address,
    latitude: row.latitude ?? null,
    longitude: row.longitude ?? null,
    confirmationCode: row.confirmation_code,
    details: parseDetails(row.details),
    notes: row.notes,
    reminderMinutes: row.reminder_minutes ?? null,
    sortIndex: row.sort_index,
    updatedAt: row.updated_at,
    updatedBy: row.updated_by,
    deletedAt: row.deleted_at ?? null,
  };
}

export function memberJson(row) {
  return {
    tripId: row.trip_id,
    userId: row.user_id,
    displayName: row.display_name || '',
    role: row.role,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at ?? null,
  };
}
