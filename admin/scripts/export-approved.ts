// Pulls approved curated rows for the data pipeline.
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npm run export
// The service-role key lives only in the environment of the machine that runs
// this (CI secret store). It is never written to a file, never printed, and
// never used by the browser app.
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { buildExport } from '../lib/export.ts';
import { CURATED } from '../lib/schema.ts';

const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.');
  process.exit(64);
}

const data: Record<string, Record<string, unknown>[]> = {};
for (const t of CURATED) {
  const res = await fetch(`${url}/rest/v1/${t.table}?status=eq.approved&select=*`, {
    headers: { apikey: key, authorization: `Bearer ${key}` },
  });
  if (!res.ok) {
    console.error(`${t.table}: HTTP ${res.status}`);
    process.exit(1);
  }
  data[t.table] = (await res.json()) as Record<string, unknown>[];
}
const out = buildExport(data);
// default: where the data pipeline looks for it (build --admin-export)
const file = process.argv[2] ?? '../data/curated/admin-approved.json';
mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, JSON.stringify(out, null, 2) + '\n');
const rows = Object.values(out.tables).reduce((n, r) => n + r.length, 0);
console.log(`${file}: ${rows} approved rows, ${out.skipped.length} skipped`);
for (const s of out.skipped) console.log(`  skipped ${s}`);
