import './globals.css';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import Shell from '@/components/Shell';

export const metadata: Metadata = {
  title: 'MetroMitra admin',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Shell>{children}</Shell>
      </body>
    </html>
  );
}
