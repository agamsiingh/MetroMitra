'use client';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { DEFAULTS, FLAG_LABELS, validateConfig, withDefaults, type Announcement, type Flags, type Theme } from '@/lib/uiconfig';

/** Typed editors for the UI/UX settings the app understands. */
export default function UiSettings() {
  const [ann, setAnn] = useState<Announcement>(DEFAULTS.announcement);
  const [flags, setFlags] = useState<Flags>(DEFAULTS.flags);
  const [theme, setTheme] = useState<Theme>(DEFAULTS.theme);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  useEffect(() => {
    supabase()
      .from('ui_config')
      .select('key,value')
      .then(({ data, error }) => {
        if (error) return setErr(error.message);
        const by = Object.fromEntries((data ?? []).map((r) => [r.key as string, r.value]));
        setAnn(withDefaults('announcement', by.announcement));
        setFlags(withDefaults('flags', by.flags));
        setTheme(withDefaults('theme', by.theme));
      });
  }, []);

  async function save(key: string, value: unknown) {
    setMsg('');
    setErr('');
    const bad = validateConfig(key, value);
    if (bad) return setErr(`${key}: ${bad}`);
    const { error } = await supabase().from('ui_config').upsert({ key, value }, { onConflict: 'key' });
    if (error) setErr(error.message);
    else setMsg(`${key} saved. The app picks it up the next time it starts.`);
  }

  return (
    <>
      <h1 className="page">UI settings</h1>
      <p className="sub">
        What the app shows and which buttons it offers. Changes reach phones the next time the app starts with a connection;
        without one the app keeps its last settings. Layout changes and new screens need an app update.
      </p>
      {msg && <p style={{ color: 'var(--ok)' }}>{msg}</p>}
      {err && <p className="err">{err}</p>}

      <section className="card">
        <h2 style={{ marginTop: 0 }}>Announcement banner</h2>
        <p className="help">A short notice at the top of the Go tab (e.g. a service change). Never use it for fares or timings.</p>
        <label><input type="checkbox" style={{ width: 'auto' }} checked={ann.enabled} onChange={(e) => setAnn({ ...ann, enabled: e.target.checked })} /> Show the banner</label>
        <label htmlFor="a-en">Text (English)</label>
        <input id="a-en" maxLength={280} value={ann.text_en} onChange={(e) => setAnn({ ...ann, text_en: e.target.value })} />
        <label htmlFor="a-hi">Text (Hindi)</label>
        <input id="a-hi" maxLength={280} value={ann.text_hi} onChange={(e) => setAnn({ ...ann, text_hi: e.target.value })} />
        <label htmlFor="a-sev">Style</label>
        <select id="a-sev" value={ann.severity} onChange={(e) => setAnn({ ...ann, severity: e.target.value as Announcement['severity'] })}>
          <option value="info">Information</option>
          <option value="warning">Warning</option>
        </select>
        <p><button className="primary" onClick={() => save('announcement', ann)}>Save banner</button></p>
      </section>

      <section className="card">
        <h2 style={{ marginTop: 0 }}>Features</h2>
        {(Object.keys(FLAG_LABELS) as (keyof Flags)[]).map((k) => (
          <label key={k} style={{ fontWeight: 400 }}>
            <input type="checkbox" style={{ width: 'auto' }} checked={flags[k]} onChange={(e) => setFlags({ ...flags, [k]: e.target.checked })} /> {FLAG_LABELS[k]}
          </label>
        ))}
        <p><button className="primary" onClick={() => save('flags', flags)}>Save features</button></p>
      </section>

      <section className="card">
        <h2 style={{ marginTop: 0 }}>Brand colour</h2>
        <p className="help">The app builds its whole palette (light and dark) from this one colour. Empty = built-in colour.</p>
        <div className="row">
          <input aria-label="Colour" type="color" style={{ width: 56, padding: 2 }} value={/^#[0-9a-f]{6}$/i.test(theme.seed_color) ? theme.seed_color : '#0b3d91'} onChange={(e) => setTheme({ seed_color: e.target.value })} />
          <input aria-label="Hex" style={{ maxWidth: 140 }} placeholder="#0B3D91" value={theme.seed_color} onChange={(e) => setTheme({ seed_color: e.target.value })} />
        </div>
        <p><button className="primary" onClick={() => save('theme', theme)}>Save colour</button></p>
      </section>
    </>
  );
}
