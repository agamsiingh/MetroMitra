'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import type { Column, TableDef } from '@/lib/schema';
import { canApprove, show, toRow, type FormValues } from '@/lib/validate';

type Row = Record<string, unknown>;

function initial(def: TableDef, row?: Row): FormValues {
  const f: FormValues = {};
  for (const c of def.columns) {
    const v = row?.[c.name];
    if (c.type === 'bool') f[c.name] = v === true ? 'true' : v === false ? 'false' : '';
    else if (c.type === 'json') f[c.name] = v == null ? '' : JSON.stringify(v, null, 2);
    else f[c.name] = v == null ? '' : String(v);
  }
  return f;
}

/** List + add/edit/delete + approve for any table described in lib/schema.ts. */
export default function TableEditor({ def }: { def: TableDef }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [q, setQ] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [editing, setEditing] = useState<{ row?: Row } | null>(null);
  const [toast, setToast] = useState('');

  const flash = (m: string) => {
    setToast(m);
    setTimeout(() => setToast(''), 2500);
  };

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error: e } = await supabase().from(def.table).select('*').order(def.orderBy, { ascending: true }).limit(2000);
    if (e) setError(e.message);
    else {
      setError('');
      setRows((data ?? []) as Row[]);
    }
    setLoading(false);
  }, [def]);

  useEffect(() => {
    void load();
  }, [load]);

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return rows.filter(
      (r) =>
        (!statusFilter || r.status === statusFilter) &&
        (!needle || def.columns.some((c) => show(r[c.name]).toLowerCase().includes(needle))),
    );
  }, [rows, q, statusFilter, def]);

  async function remove(r: Row) {
    if (!confirm('Delete this row? This is recorded in the change history.')) return;
    const { error: e } = await supabase().from(def.table).delete().eq(def.pk, r[def.pk] as string);
    if (e) flash(e.message);
    else {
      flash('Deleted');
      void load();
    }
  }

  async function setStatus(r: Row, status: 'draft' | 'approved') {
    if (status === 'approved') {
      const why = canApprove(r);
      if (why) return flash(`Cannot approve: ${why}`);
    }
    const { error: e } = await supabase().from(def.table).update({ status }).eq(def.pk, r[def.pk] as string);
    if (e) flash(e.message);
    else {
      flash(status === 'approved' ? 'Approved' : 'Moved back to draft');
      void load();
    }
  }

  const listCols = def.columns.filter((c) => !c.hideInList);
  return (
    <>
      <h1 className="page">{def.label}</h1>
      <p className="sub">{def.help}</p>
      <div className="row" style={{ marginBottom: 12 }}>
        <input style={{ maxWidth: 280 }} placeholder="Search…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Search" />
        {def.workflow && (
          <select style={{ maxWidth: 160 }} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="Status">
            <option value="">All</option>
            <option value="draft">Draft</option>
            <option value="approved">Approved</option>
          </select>
        )}
        <span className="spacer" />
        <span className="help">{shown.length} of {rows.length}</span>
        <button className="primary" onClick={() => setEditing({})}>Add</button>
      </div>
      {error && <p className="err">{error}</p>}
      <div className="tablewrap">
        <table>
          <thead>
            <tr>
              {listCols.map((c) => <th key={c.name}>{c.label}</th>)}
              {def.workflow && <th>Status</th>}
              <th />
            </tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={listCols.length + 2}>Loading…</td></tr>}
            {!loading && shown.length === 0 && <tr><td colSpan={listCols.length + 2}>Nothing here yet.</td></tr>}
            {shown.map((r) => (
              <tr key={String(r[def.pk]) + String(r.lang ?? '')}>
                {listCols.map((c) => <td key={c.name} title={show(r[c.name])}>{show(r[c.name])}</td>)}
                {def.workflow && <td><span className={`pill ${String(r.status)}`}>{String(r.status)}</span></td>}
                <td style={{ whiteSpace: 'nowrap' }}>
                  <button onClick={() => setEditing({ row: r })}>Edit</button>{' '}
                  {def.workflow && (r.status === 'approved'
                    ? <button onClick={() => setStatus(r, 'draft')}>Unapprove</button>
                    : <button onClick={() => setStatus(r, 'approved')}>Approve</button>)}{' '}
                  <button className="danger" onClick={() => remove(r)}>Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {editing && (
        <RowForm
          def={def}
          row={editing.row}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            flash('Saved');
            void load();
          }}
        />
      )}
      {toast && <div className="toast" role="status">{toast}</div>}
    </>
  );
}

function Field({ col, value, error, onChange }: { col: Column; value: string; error?: string; onChange: (v: string) => void }) {
  const id = `f-${col.name}`;
  let input;
  if (col.type === 'longtext' || col.type === 'json') {
    input = <textarea id={id} value={value} onChange={(e) => onChange(e.target.value)} />;
  } else if (col.type === 'bool') {
    input = (
      <select id={id} value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">Unknown (not verified)</option>
        <option value="true">Yes</option>
        <option value="false">No</option>
      </select>
    );
  } else if (col.type === 'enum') {
    input = (
      <select id={id} value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">{col.required ? 'Choose…' : '— none —'}</option>
        {col.options?.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
    );
  } else {
    const type = col.type === 'number' || col.type === 'int' ? 'number' : col.type === 'date' ? 'date' : col.type === 'time' ? 'time' : 'text';
    input = <input id={id} type={type} step={col.type === 'number' ? 'any' : undefined} value={value} onChange={(e) => onChange(e.target.value)} />;
  }
  return (
    <div>
      <label htmlFor={id}>{col.label}{col.required ? ' *' : ''}</label>
      {input}
      {col.help && <div className="help">{col.help}</div>}
      {error && <div className="err">{error}</div>}
    </div>
  );
}

function RowForm({ def, row, onClose, onSaved }: { def: TableDef; row?: Row; onClose: () => void; onSaved: () => void }) {
  const [form, setForm] = useState<FormValues>(() => initial(def, row));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [fail, setFail] = useState('');

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const r = toRow(def, form);
    setErrors(r.errors);
    if (!r.ok) return;
    setSaving(true);
    setFail('');
    const sb = supabase();
    const payload = row ? r.row : { ...r.row, ...(def.workflow ? { status: 'draft' } : {}) };
    const q = row
      ? def.table === 'ui_strings'
        ? sb.from(def.table).update(payload).eq('key', row.key as string).eq('lang', row.lang as string)
        : sb.from(def.table).update(payload).eq(def.pk, row[def.pk] as string)
      : sb.from(def.table).insert(payload);
    const { error } = await q;
    setSaving(false);
    if (error) setFail(error.message);
    else onSaved();
  }

  return (
    <div className="modal" onClick={onClose}>
      <form className="drawer" onClick={(e) => e.stopPropagation()} onSubmit={save}>
        <h2 style={{ marginTop: 0 }}>{row ? 'Edit' : 'Add'} — {def.label}</h2>
        {def.workflow && <p className="help">Saved changes become <b>draft</b> again until approved.</p>}
        {def.columns.map((c) => (
          <Field key={c.name} col={c} value={String(form[c.name] ?? '')} error={errors[c.name]} onChange={(v) => setForm({ ...form, [c.name]: v })} />
        ))}
        {fail && <p className="err">{fail}</p>}
        <div className="row" style={{ marginTop: 18 }}>
          <button className="primary" disabled={saving}>{saving ? 'Saving…' : 'Save'}</button>
          <button type="button" onClick={onClose}>Cancel</button>
        </div>
      </form>
    </div>
  );
}
