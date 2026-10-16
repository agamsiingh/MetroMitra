'use client';
import { use } from 'react';
import TableEditor from '@/components/TableEditor';
import { tableDef } from '@/lib/schema';

export default function Page({ params }: { params: Promise<{ table: string }> }) {
  const { table } = use(params);
  const def = tableDef(table);
  if (!def) return <p className="err">Unknown table.</p>;
  return <TableEditor def={def} key={def.table} />;
}
