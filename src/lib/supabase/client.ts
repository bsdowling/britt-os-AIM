// Browser-side Supabase client for TanStack Query panels and auth (magic link).

import { createBrowserClient } from "@supabase/ssr";
import { env, isSupabaseConfigured } from "@/lib/env";

export function getBrowserSupabase() {
  if (!isSupabaseConfigured) return null;
  return createBrowserClient(env.supabaseUrl!, env.supabaseAnonKey!);
}
