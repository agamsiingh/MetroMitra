// Builds the file the data pipeline reads. Only approved rows that carry
// provenance are exported; anything else is reported, never silently included.
import { canApprove } from './validate.ts';

type Row = Record<string, unknown>;

export interface Export {
  format: 'metromitra-curated/1';
  exported_at: string;
  tables: Record<string, Row[]>;
  skipped: string[];
}

const DROP = ['id', 'updated_at'];

export function buildExport(data: Record<string, Row[]>, now: Date = new Date()): Export {
  const tables: Record<string, Row[]> = {};
  const skipped: string[] = [];
  for (const [table, rows] of Object.entries(data)) {
    tables[table] = [];
    for (const r of rows) {
      if (r.status !== 'approved') continue; // drafts never leave the admin
      const why = canApprove(r);
      if (why) {
        skipped.push(`${table} ${String(r.station_id ?? r.fare_system ?? r.id)}: ${why}`);
        continue;
      }
      const clean: Row = {};
      for (const [k, v] of Object.entries(r)) if (!DROP.includes(k) && k !== 'status') clean[k] = v;
      tables[table].push(clean);
    }
    tables[table].sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))); // stable output
  }
  return { format: 'metromitra-curated/1', exported_at: now.toISOString(), tables, skipped };
}
