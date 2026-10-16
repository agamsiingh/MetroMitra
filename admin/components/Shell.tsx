'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import AuthGate from './AuthGate';
import { CURATED } from '@/lib/schema';

export default function Shell({ children }: { children: ReactNode }) {
  const path = usePathname();
  const item = (href: string, label: string) => (
    <Link key={href} href={href} className={path === href ? 'on' : ''}>
      {label}
    </Link>
  );
  return (
    <AuthGate>
      {({ role, email, signOut }) => (
        <div className="shell">
          <aside className="side">
            <h1>MetroMitra admin</h1>
            <nav>
              {item('/', 'Overview')}
              <h2>App look &amp; behaviour</h2>
              {item('/ui', 'UI settings')}
              {item('/t/ui_strings', 'Text overrides')}
              <h2>Metro data</h2>
              {CURATED.map((t) => item(`/t/${t.table}`, t.label))}
              <h2>Publish</h2>
              {item('/export', 'Export approved data')}
              <h2>Safety</h2>
              {item('/audit', 'Change history')}
              {role === 'admin' && item('/admins', 'Administrators')}
            </nav>
            <p className="help" style={{ marginTop: 20 }}>
              {email}
              <br />
              role: {role}
            </p>
            <button onClick={signOut}>Sign out</button>
          </aside>
          <main>{children}</main>
        </div>
      )}
    </AuthGate>
  );
}
