'use client';
import { useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';

type Role = 'admin' | 'editor';

/** Login + admin check. Being able to sign in is NOT enough: the database
 *  only accepts writes from users listed in admin_users (row-level security). */
export default function AuthGate({ children }: { children: (ctx: { role: Role; email: string; signOut: () => void }) => ReactNode }) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [role, setRole] = useState<Role | null | undefined>(undefined);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let sb;
    try {
      sb = supabase();
    } catch (e) {
      setError(String((e as Error).message));
      setSession(null);
      return;
    }
    sb.auth.getSession().then(({ data }) => setSession(data.session));
    const { data: sub } = sb.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) {
      setRole(undefined);
      return;
    }
    supabase()
      .from('admin_users')
      .select('role')
      .eq('user_id', session.user.id)
      .maybeSingle()
      .then(({ data, error: e }) => {
        if (e) setError(e.message);
        setRole((data?.role as Role | undefined) ?? null);
      });
  }, [session]);

  async function login(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    const { error: err } = await supabase().auth.signInWithPassword({ email, password });
    if (err) setError(err.message);
    setBusy(false);
  }

  if (session === undefined) return <p style={{ padding: 24 }}>Loading…</p>;

  if (!session) {
    return (
      <form className="card login" onSubmit={login}>
        <h1 className="page">MetroMitra admin</h1>
        <p className="sub">Sign in with the admin account.</p>
        <label htmlFor="email">E-mail</label>
        <input id="email" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <label htmlFor="pw">Password</label>
        <input id="pw" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
        {error && <p className="err">{error}</p>}
        <p style={{ marginTop: 16 }}>
          <button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        </p>
      </form>
    );
  }

  if (role === undefined) return <p style={{ padding: 24 }}>Checking access…</p>;

  if (role === null) {
    return (
      <div className="card login">
        <h1 className="page">No access</h1>
        <p className="sub">
          {session.user.email} is signed in but is not an administrator. Ask an admin to add this account to
          <code> admin_users</code>.
        </p>
        {error && <p className="err">{error}</p>}
        <button onClick={() => supabase().auth.signOut()}>Sign out</button>
      </div>
    );
  }

  return <>{children({ role, email: session.user.email ?? '', signOut: () => void supabase().auth.signOut() })}</>;
}
