'use client';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { CURATED } from '@/lib/schema';
import { buildExport } from '@/lib/export';

type Row = Record<string, unknown>;

export function Overview() {
  const [counts, setCounts] = useState<Record<string, { draft: number; approved: number }>>({});
  const [err, setErr] = useState('');
  useEffect(() => {
    void (async () => {
      const out: typeof counts = {};
      for (const t of CURATED) {
        const { data, error } = await supabase().from(t.table).select('status');
        if (error) return setErr(error.message);
        const rows = (data ?? []) as Row[];
        out[t.table] = {
          draft: rows.filter((r) => r.status === 'draft').length,
          approved: rows.filter((r) => r.status === 'approved').length,
        };
      }
      setCounts(out);
    })();
  }, []);
  return (
    <>
      <h1 className="page">Overview</h1>
      <p className="sub">Metro facts are saved as drafts, approved with a source, then exported into the signed dataset the app downloads.</p>
      {err && <p className="err">{err}</p>}
      <div className="grid">
        {CURATED.map((t) => (
          <a key={t.table} className="card" href={`/t/${t.table}`}>
            <div className="help">{t.label}</div>
            <div className="stat">{counts[t.table]?.approved ?? '–'}</div>
            <div className="help">approved · {counts[t.table]?.draft ?? '–'} draft</div>
          </a>
        ))}
      </div>
    </>
  );
}

export function Audit() {
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState('');
  useEffect(() => {
    supabase()
      .from('audit_log')
      .select('*')
      .order('id', { ascending: false })
      .limit(200)
      .then(({ data, error }) => (error ? setErr(error.message) : setRows((data ?? []) as Row[])));
  }, []);
  return (
    <>
      <h1 className="page">Change history</h1>
      <p className="sub">The last 200 changes to metro data, UI settings, texts and administrators. Written by the database; it cannot be edited here.</p>
      {err && <p className="err">{err}</p>}
      <div className="tablewrap">
        <table>
          <thead><tr><th>When</th><th>Table</th><th>Change</th><th>Row</th><th>By</th><th>Before → after</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={String(r.id)}>
                <td>{new Date(String(r.at)).toLocaleString()}</td>
                <td>{String(r.table_name)}</td>
                <td>{String(r.op)}</td>
                <td title={String(r.row_pk)}>{String(r.row_pk)}</td>
                <td title={String(r.by_user)}>{String(r.by_user ?? '').slice(0, 8)}</td>
                <td title={JSON.stringify({ before: r.old_row, after: r.new_row })}>{JSON.stringify(r.new_row ?? r.old_row)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

export function Admins() {
  const [rows, setRows] = useState<Row[]>([]);
  const [uid, setUid] = useState('');
  const [role, setRole] = useState('editor');
  const [msg, setMsg] = useState('');
  const load = () =>
    supabase().from('admin_users').select('*').then(({ data, error }) => (error ? setMsg(error.message) : setRows((data ?? []) as Row[])));
  useEffect(() => { void load(); }, []);
  async function add() {
    const { error } = await supabase().from('admin_users').insert({ user_id: uid.trim(), role });
    setMsg(error ? error.message : 'Added');
    setUid('');
    void load();
  }
  async function del(id: string) {
    if (!confirm('Remove this administrator?')) return;
    const { error } = await supabase().from('admin_users').delete().eq('user_id', id);
    setMsg(error ? error.message : 'Removed');
    void load();
  }
  return (
    <>
      <h1 className="page">Administrators</h1>
      <p className="sub">Only these accounts can change anything. Create the account in Supabase → Authentication, then paste its user id here.</p>
      {msg && <p className="help">{msg}</p>}
      <div className="card row">
        <input style={{ maxWidth: 360 }} placeholder="User id (uuid)" value={uid} onChange={(e) => setUid(e.target.value)} />
        <select style={{ maxWidth: 140 }} value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="editor">editor</option>
          <option value="admin">admin</option>
        </select>
        <button className="primary" onClick={add} disabled={!uid.trim()}>Add</button>
      </div>
      <div className="tablewrap">
        <table>
          <thead><tr><th>User id</th><th>Role</th><th>Since</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={String(r.user_id)}>
                <td>{String(r.user_id)}</td><td>{String(r.role)}</td><td>{new Date(String(r.created_at)).toLocaleDateString()}</td>
                <td><button className="danger" onClick={() => del(String(r.user_id))}>Remove</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

export function Export() {
  const [text, setText] = useState('');
  const [info, setInfo] = useState('');
  const [err, setErr] = useState('');
  async function run() {
    setErr('');
    const data: Record<string, Row[]> = {};
    for (const t of CURATED) {
      const { data: rows, error } = await supabase().from(t.table).select('*').eq('status', 'approved');
      if (error) return setErr(error.message);
      data[t.table] = (rows ?? []) as Row[];
    }
    const out = buildExport(data);
    setText(JSON.stringify(out, null, 2));
    setInfo(`${Object.values(out.tables).reduce((n, r) => n + r.length, 0)} approved rows` + (out.skipped.length ? `, ${out.skipped.length} skipped (see below)` : ''));
    setSkipped(out.skipped);
  }
  const [skipped, setSkipped] = useState<string[]>([]);
  function download() {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
    a.download = `metromitra-curated-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
  }
  return (
    <>
      <h1 className="page">Export approved data</h1>
      <p className="sub">
        Only <b>approved</b> rows with a source are exported. The file goes to the data pipeline, which builds, validates and signs the
        dataset the app downloads. Nothing here changes the app directly.
      </p>
      <p className="row"><button className="primary" onClick={run}>Build export</button><button onClick={download} disabled={!text}>Download JSON</button><span className="help">{info}</span></p>
      {err && <p className="err">{err}</p>}
      {skipped.length > 0 && <div className="card"><b>Skipped</b><ul>{skipped.map((s) => <li key={s}>{s}</li>)}</ul></div>}
      <textarea readOnly style={{ minHeight: 360 }} value={text} aria-label="Export preview" />
    </>
  );
}
