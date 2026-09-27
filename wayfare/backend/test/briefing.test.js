import { describe, it, expect } from 'vitest';
import { localParts, formatClock } from '../src/time.js';
import { dueDevices, tripToday, itemsOnDate, composeBriefing, planBriefings, chunk } from '../src/briefing.js';

const at = (iso) => new Date(iso);

describe('time helpers', () => {
  it('computes local date and hour in a time zone', () => {
    // 2026-10-01T06:30Z is 07:30 in Lisbon (WEST, UTC+1) and 02:30 in New York (EDT).
    expect(localParts(at('2026-10-01T06:30:00Z'), 'Europe/Lisbon')).toEqual({ date: '2026-10-01', hour: 7, minute: 30 });
    expect(localParts(at('2026-10-01T06:30:00Z'), 'America/New_York')).toEqual({ date: '2026-10-01', hour: 2, minute: 30 });
    expect(localParts(at('2026-10-01T23:30:00Z'), 'Asia/Tokyo')).toEqual({ date: '2026-10-02', hour: 8, minute: 30 });
  });
  it('reports midnight as hour 0, not 24', () => {
    expect(localParts(at('2026-10-01T00:00:00Z'), 'UTC').hour).toBe(0);
  });
  it('handles half-hour zones and DST', () => {
    expect(localParts(at('2026-10-01T02:00:00Z'), 'Asia/Kolkata').hour).toBe(7); // +05:30
    // Lisbon leaves DST on 2026-10-25: 06:30Z is 07:30 before, 06:30 after.
    expect(localParts(at('2026-10-24T06:30:00Z'), 'Europe/Lisbon').hour).toBe(7);
    expect(localParts(at('2026-10-26T06:30:00Z'), 'Europe/Lisbon').hour).toBe(6);
  });
  it('formats clock times', () => {
    expect(formatClock('2026-10-02T07:30:00Z', 'Europe/Lisbon')).toBe('8:30');
    expect(formatClock('2026-10-02T19:05:00Z', 'Europe/Lisbon')).toBe('20:05');
  });
});

describe('briefing selection', () => {
  const dev = (o) => ({ apns_token: 't', environment: 'sandbox', user_id: 'u1', time_zone: 'America/New_York', briefing_hour: 7, last_briefing_date: null, ...o });

  it('is due only when the local hour equals briefingHour', () => {
    const now = at('2026-10-01T11:00:00Z'); // 07:00 New York
    expect(dueDevices([dev()], now)).toHaveLength(1);
    expect(dueDevices([dev({ briefing_hour: 8 })], now)).toHaveLength(0);
    expect(dueDevices([dev({ time_zone: 'Europe/Lisbon' })], now)).toHaveLength(0); // 12:00 there
    expect(dueDevices([dev()], now)[0].localDate).toBe('2026-10-01');
  });
  it('skips devices already briefed today and survives bad time zones', () => {
    const now = at('2026-10-01T11:00:00Z');
    expect(dueDevices([dev({ last_briefing_date: '2026-10-01' })], now)).toHaveLength(0);
    expect(dueDevices([dev({ last_briefing_date: '2026-09-30' })], now)).toHaveLength(1);
    expect(dueDevices([dev({ time_zone: 'Bad/Zone' })], now)).toHaveLength(0);
  });
  it('uses the TRIP time zone for "today"', () => {
    const trip = { start_date: '2026-10-02', end_date: '2026-10-09', time_zone: 'Asia/Tokyo' };
    // 2026-10-01T20:00Z is already Oct 2 in Tokyo, still Oct 1 in UTC.
    expect(tripToday(trip, at('2026-10-01T20:00:00Z'))).toBe('2026-10-02');
    expect(tripToday({ ...trip, time_zone: 'UTC' }, at('2026-10-01T20:00:00Z'))).toBeNull();
    expect(tripToday(trip, at('2026-10-09T14:59:00Z'))).toBe('2026-10-09');
    expect(tripToday(trip, at('2026-10-09T15:00:00Z'))).toBeNull(); // Oct 10 in Tokyo
  });
  it('picks items on the date in their own time zone, in time order', () => {
    const items = [
      { title: 'Dinner', start_at: '2026-10-02T19:00:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0, sort_index: 0 },
      { title: 'Breakfast', start_at: '2026-10-02T07:30:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0, sort_index: 0 },
      { title: 'Late', start_at: '2026-10-02T23:30:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0, sort_index: 0 }, // Oct 3 local
    ];
    expect(itemsOnDate(items, '2026-10-02').map((i) => i.title)).toEqual(['Breakfast', 'Dinner']);
  });
  it('composes the contract wording', () => {
    const trip = { title: 'Lisbon & Porto', destination: 'Lisbon' };
    const items = [
      { title: 'Breakfast at Manteigaria', start_at: '2026-10-02T07:30:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0 },
      { title: 'Tram 28', start_at: '2026-10-02T10:00:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0 },
      { title: 'Dinner', start_at: '2026-10-02T19:00:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0 },
    ];
    expect(composeBriefing(trip, items)).toEqual({ title: 'Today in Lisbon', body: '3 plans · first: Breakfast at Manteigaria at 8:30' });
    expect(composeBriefing({ title: 'Japan', destination: '' }, []).title).toBe('Today in Japan');
    expect(composeBriefing(trip, [items[0]]).body).toMatch(/^1 plan · /);
    const allDay = { title: 'Museum day', start_at: '2026-10-01T23:00:00Z', start_time_zone: 'Europe/Lisbon', all_day: 1 };
    expect(composeBriefing(trip, [allDay]).body).toBe('1 plan · first: Museum day');
    expect(composeBriefing(trip, [allDay, items[1]]).body).toBe('2 plans · first: Tram 28 at 11:00');
  });
  it('plans one briefing per due device per in-progress trip', () => {
    const now = at('2026-10-02T06:00:00Z'); // 07:00 Lisbon
    const devices = [dev({ user_id: 'u1', time_zone: 'Europe/Lisbon', localDate: '2026-10-02' })];
    const trips = [
      { id: 't1', user_id: 'u1', title: 'Portugal', destination: 'Lisbon', start_date: '2026-10-01', end_date: '2026-10-09', time_zone: 'Europe/Lisbon' },
      { id: 't2', user_id: 'u1', title: 'Later', destination: '', start_date: '2026-11-01', end_date: '2026-11-09', time_zone: 'Europe/Lisbon' },
      { id: 't3', user_id: 'u2', title: 'Other user', destination: '', start_date: '2026-10-01', end_date: '2026-10-09', time_zone: 'Europe/Lisbon' },
    ];
    const items = [{ id: 'i1', trip_id: 't1', title: 'Tram', start_at: '2026-10-02T09:00:00Z', start_time_zone: 'Europe/Lisbon', all_day: 0, sort_index: 0 }];
    const plan = planBriefings({ devices, trips, items, now });
    expect(plan).toHaveLength(1);
    expect(plan[0]).toMatchObject({ date: '2026-10-02', title: 'Today in Lisbon', body: '1 plan · first: Tram at 10:00' });
    expect(plan[0].trip.id).toBe('t1');
  });
  it('chunks lists for D1 parameter limits', () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });
});
