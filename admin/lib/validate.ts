// Turns what the form holds into what the database accepts, and refuses
// anything that would invent data. Pure functions: covered by tests/.
import type { Column, TableDef } from './schema.ts';

export type FormValues = Record<string, string | boolean | null | undefined>;

export interface Result {
  ok: boolean;
  row: Record<string, unknown>;
  errors: Record<string, string>;
}

/** empty -> null (unknown stays unknown); never a made-up default */
function convert(col: Column, raw: string | boolean | null | undefined): { value: unknown; error?: string } {
  if (col.type === 'bool') {
    // 'unknown' / '' / null -> null, so "not verified" is never stored as false
    if (raw === true || raw === 'true') return { value: true };
    if (raw === false || raw === 'false') return { value: false };
    return { value: null };
  }
  const s = typeof raw === 'string' ? raw.trim() : raw == null ? '' : String(raw);
  if (s === '') return { value: null };
  switch (col.type) {
    case 'number': {
      const n = Number(s);
      return Number.isFinite(n) ? { value: n } : { value: null, error: 'must be a number' };
    }
    case 'int': {
      const n = Number(s);
      return Number.isInteger(n) && n >= 0 ? { value: n } : { value: null, error: 'must be a whole number, 0 or more' };
    }
    case 'date':
      return /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s))
        ? { value: s }
        : { value: null, error: 'use YYYY-MM-DD' };
    case 'time':
      return /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(s)
        ? { value: s }
        : { value: null, error: 'use HH:MM (24 h)' };
    case 'json':
      try {
        return { value: JSON.parse(s) };
      } catch {
        return { value: null, error: 'not valid JSON' };
      }
    case 'enum':
      return col.options?.includes(s) ? { value: s } : { value: null, error: `one of ${col.options?.join(', ')}` };
    default:
      return { value: s };
  }
}

export function toRow(def: TableDef, form: FormValues): Result {
  const row: Record<string, unknown> = {};
  const errors: Record<string, string> = {};
  for (const col of def.columns) {
    const { value, error } = convert(col, form[col.name]);
    if (error) errors[col.name] = error;
    else if (col.required && value === null) errors[col.name] = 'required';
    else row[col.name] = value;
  }
  if (typeof row.lat === 'number' && (row.lat < -90 || row.lat > 90)) errors.lat = 'between -90 and 90';
  if (typeof row.lng === 'number' && (row.lng < -180 || row.lng > 180)) errors.lng = 'between -180 and 180';
  if (typeof row.from_km === 'number' && typeof row.to_km === 'number' && row.to_km < row.from_km) {
    errors.to_km = 'must not be below "from km"';
  }
  if (def.table === 'ui_strings' && typeof row.text === 'string' && row.text.length > 500) {
    errors.text = 'at most 500 characters';
  }
  // a verified/official fact must say where it comes from
  if (def.workflow && (row.confidence === 'official' || row.confidence === 'verified') && !row.source) {
    errors.source = 'required for official or verified facts';
  }
  return { ok: Object.keys(errors).length === 0, row, errors };
}

/** a row may only be approved when it carries provenance */
export function canApprove(row: Record<string, unknown>): string | null {
  if (!row.source) return 'add a source first';
  if (!row.verified_on) return 'add the verification date first';
  if (!row.confidence) return 'set the confidence first';
  return null;
}

/** the text of a cell for the list view */
export function show(v: unknown): string {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}
