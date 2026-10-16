'use client';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

let client: SupabaseClient | null = null;

/** Browser client with the public (publishable) key only. What it may do is
 *  decided by row-level security in the database, not by this key. */
export function supabase(): SupabaseClient {
  if (!url || !key) {
    throw new Error('Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in admin/.env.local');
  }
  if (key.startsWith('sb_secret_') || key.includes('service_role')) {
    throw new Error('A secret / service-role key must never be used in the browser');
  }
  client ??= createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
  return client;
}
