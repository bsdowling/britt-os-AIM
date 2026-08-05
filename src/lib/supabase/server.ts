// Server-side Supabase client (App Router). Uses @supabase/ssr with cookie
// bridging so RLS-aware auth works when a session exists. Returns null in demo
// mode so callers can fall back to fixtures.

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { env, isSupabaseConfigured } from "@/lib/env";

export async function getServerSupabase() {
  if (!isSupabaseConfigured) return null;
  const cookieStore = await cookies();

  return createServerClient(env.supabaseUrl!, env.supabaseAnonKey!, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet: { name: string; value: string; options?: Record<string, unknown> }[]) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Called from a Server Component — safe to ignore; middleware refreshes.
        }
      },
    },
  });
}

// Service-role client for cron jobs and webhook receivers (server only).
export function getServiceSupabase() {
  if (!env.supabaseUrl || !env.supabaseServiceRole) return null;
  const { createClient } = require("@supabase/supabase-js");
  return createClient(env.supabaseUrl, env.supabaseServiceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
