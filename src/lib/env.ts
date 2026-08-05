// Central env access. `isSupabaseConfigured` gates whether the app talks to a
// real database or falls back to demo fixtures, so the dashboard is reviewable
// before any integration credentials exist.

export const env = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL,
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  supabaseServiceRole: process.env.SUPABASE_SERVICE_ROLE_KEY,
  appUrl: process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000",
  fubApiKey: process.env.FUB_API_KEY,
  fubSystemName: process.env.FUB_SYSTEM_NAME ?? "BrittsOS",
  cronSecret: process.env.CRON_SECRET,
};

export const isSupabaseConfigured = Boolean(
  env.supabaseUrl && env.supabaseAnonKey,
);

// Force demo mode with DEMO_MODE=1 even when Supabase is configured.
export const isDemoMode = process.env.DEMO_MODE === "1" || !isSupabaseConfigured;
