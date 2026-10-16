import test from 'node:test';
import assert from 'node:assert/strict';
import { tableDef, ALL_TABLES } from '../lib/schema.ts';
import { toRow, canApprove } from '../lib/validate.ts';
import { buildExport } from '../lib/export.ts';
import { validateConfig, withDefaults, DEFAULTS } from '../lib/uiconfig.ts';

const gates = tableDef('curated_gates')!;
const stations = tableDef('curated_stations')!;
const fares = tableDef('curated_fares')!;

test('empty fields become null: unknown stays unknown, nothing is invented', () => {
  const r = toRow(gates, { station_id: 'rajiv-chowk', gate_no: '4', step_free: '', name_en: '  ', lat: '' });
  assert.equal(r.ok, true);
  assert.equal(r.row.step_free, null, 'unknown is not false');
  assert.equal(r.row.name_en, null);
  assert.equal(r.row.lat, null);
});

test('bool: only an explicit yes/no is stored', () => {
  assert.equal(toRow(gates, { station_id: 'a', gate_no: '1', step_free: 'true' }).row.step_free, true);
  assert.equal(toRow(gates, { station_id: 'a', gate_no: '1', step_free: 'false' }).row.step_free, false);
});

test('required fields, numbers, dates, json and enums are checked', () => {
  const bad = toRow(stations, { station_id: '', lat: 'abc', verified_on: '12/10/2026', aliases: '{not json', confidence: 'maybe' });
  assert.equal(bad.ok, false);
  for (const k of ['station_id', 'lat', 'verified_on', 'aliases', 'confidence']) assert.ok(bad.errors[k], k);
});

test('coordinates are range checked', () => {
  assert.ok(toRow(stations, { station_id: 'a', lat: '95', lng: '77' }).errors.lat);
  assert.ok(toRow(stations, { station_id: 'a', lat: '28', lng: '190' }).errors.lng);
  assert.equal(toRow(stations, { station_id: 'a', lat: '28.6', lng: '77.2' }).ok, true);
});

test('an official or verified fact must name its source', () => {
  assert.ok(toRow(gates, { station_id: 'a', gate_no: '1', confidence: 'official' }).errors.source);
  assert.equal(toRow(gates, { station_id: 'a', gate_no: '1', confidence: 'official', source: 'DMRC notice 12' }).ok, true);
  assert.equal(toRow(gates, { station_id: 'a', gate_no: '1', confidence: 'community' }).ok, true);
});

test('fares: whole paise, ranges ordered', () => {
  assert.ok(toRow(fares, { fare_system: 'x', fare_paise: '43.5' }).errors.fare_paise);
  assert.ok(toRow(fares, { fare_system: 'x', from_km: '5', to_km: '2' }).errors.to_km);
  assert.equal(toRow(fares, { fare_system: 'x', fare_paise: '4300', from_km: '2', to_km: '5' }).ok, true);
});

test('times are 24-hour', () => {
  const t = tableDef('curated_timings')!;
  assert.ok(toRow(t, { station_id: 'a', first_train: '25:00' }).errors.first_train);
  assert.equal(toRow(t, { station_id: 'a', first_train: '05:30', last_train: '23:45' }).ok, true);
});

test('text overrides are capped', () => {
  const s = tableDef('ui_strings')!;
  assert.ok(toRow(s, { key: 'homeHeading', lang: 'en', text: 'x'.repeat(501) }).errors.text);
  assert.ok(toRow(s, { key: 'homeHeading', lang: 'fr', text: 'x' }).errors.lang);
  assert.ok(toRow(s, { key: 'fareTable', lang: 'en', text: 'x' }).errors.key, 'a key the app ignores is refused');
  assert.equal(toRow(s, { key: 'askIntro', lang: 'hi', text: 'नमस्ते' }).ok, true);
});

test('approval needs provenance', () => {
  assert.ok(canApprove({ source: null, verified_on: '2026-10-01', confidence: 'official' }));
  assert.ok(canApprove({ source: 's', verified_on: null, confidence: 'official' }));
  assert.ok(canApprove({ source: 's', verified_on: '2026-10-01', confidence: null }));
  assert.equal(canApprove({ source: 's', verified_on: '2026-10-01', confidence: 'official' }), null);
});

test('export: drafts and rows without provenance never leave', () => {
  const ok = { id: '1', station_id: 'a', gate_no: '1', status: 'approved', source: 's', verified_on: '2026-10-01', confidence: 'official', updated_at: 'x' };
  const draft = { ...ok, id: '2', gate_no: '2', status: 'draft' };
  const noSource = { ...ok, id: '3', gate_no: '3', source: null };
  const out = buildExport({ curated_gates: [draft, ok, noSource] }, new Date('2026-10-16T00:00:00Z'));
  assert.equal(out.tables.curated_gates.length, 1);
  assert.equal(out.tables.curated_gates[0].gate_no, '1');
  assert.equal('id' in out.tables.curated_gates[0], false);
  assert.equal('status' in out.tables.curated_gates[0], false);
  assert.equal(out.skipped.length, 1);
  assert.equal(out.exported_at, '2026-10-16T00:00:00.000Z');
});

test('export is deterministic regardless of row order', () => {
  const a = { station_id: 'a', status: 'approved', source: 's', verified_on: '2026-10-01', confidence: 'official' };
  const b = { ...a, station_id: 'b' };
  const d = new Date(0);
  assert.deepEqual(buildExport({ curated_stations: [a, b] }, d), buildExport({ curated_stations: [b, a] }, d));
});

test('UI config: known keys validate, unknown keys are refused', () => {
  assert.equal(validateConfig('flags', DEFAULTS.flags), null);
  assert.ok(validateConfig('flags', { online_ai: 'yes' }));
  assert.ok(validateConfig('announcement', { enabled: true, text_en: '', text_hi: '', severity: 'info' }));
  assert.equal(validateConfig('announcement', { enabled: true, text_en: 'Service change', text_hi: '', severity: 'warning' }), null);
  assert.ok(validateConfig('announcement', { enabled: false, text_en: 'x'.repeat(281), text_hi: '', severity: 'info' }));
  assert.ok(validateConfig('theme', { seed_color: 'red' }));
  assert.equal(validateConfig('theme', { seed_color: '#0B3D91' }), null);
  assert.equal(validateConfig('theme', { seed_color: '' }), null);
  assert.ok(validateConfig('fares_override', {}));
  assert.ok(validateConfig('flags', [] as unknown as object));
});

test('UI config: missing keys fall back to defaults', () => {
  assert.equal(withDefaults('flags', { online_ai: false }).show_overview_map, true);
  assert.deepEqual(withDefaults('theme', null), DEFAULTS.theme);
});

test('every table has typed, unique columns', () => {
  for (const t of ALL_TABLES) {
    assert.ok(t.columns.length > 0, t.table);
    assert.equal(new Set(t.columns.map((c) => c.name)).size, t.columns.length, `${t.table} duplicate column`);
    for (const c of t.columns) if (c.type === 'enum') assert.ok(c.options?.length, `${t.table}.${c.name}`);
  }
});
