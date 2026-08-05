// Shared cron plumbing (PRD §10). Every cron route checks CRON_SECRET, records
// start/finish to sync_state, and reports failures to the caller (Sentry hook).

import { NextResponse } from "next/server";
import { env } from "@/lib/env";
import { getServiceSupabase } from "@/lib/supabase/server";

// Vercel Cron sends `Authorization: Bearer <CRON_SECRET>`.
export function authorizeCron(req: Request): NextResponse | null {
  if (!env.cronSecret) {
    // In demo/dev with no secret set, allow so routes are exercisable.
    return null;
  }
  const header = req.headers.get("authorization");
  if (header !== `Bearer ${env.cronSecret}`) {
    return NextResponse.json({ ok: false, error: "Unauthorized" }, { status: 401 });
  }
  return null;
}

// Vercel Cron runs in UTC; schedules are set for Central. Jobs that must fire at
// a specific local hour call this to bail when the Central hour is wrong, so the
// twice-a-year DST shift never needs a file edit (PRD §10).
export function isCentralHour(target: number, now = new Date()): boolean {
  const hour = Number(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Chicago",
      hour: "numeric",
      hour12: false,
    }).format(now),
  );
  return hour === target;
}

export async function recordSyncRun(
  integration: string,
  fn: () => Promise<{ cursor?: string; note?: string }>,
): Promise<{ ok: boolean; note?: string; error?: string }> {
  const supabase = getServiceSupabase();
  const startedAt = new Date().toISOString();
  if (supabase) {
    await supabase
      .from("sync_state")
      .upsert({ integration, last_run_at: startedAt }, { onConflict: "integration" });
  }
  try {
    const { cursor, note } = await fn();
    if (supabase) {
      await supabase
        .from("sync_state")
        .update({
          last_success_at: new Date().toISOString(),
          cursor: cursor ?? undefined,
          error_count: 0,
          last_error: null,
        })
        .eq("integration", integration);
    }
    return { ok: true, note };
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (supabase) {
      await supabase.rpc("noop").catch(() => {});
      await supabase
        .from("sync_state")
        .update({ last_error: message })
        .eq("integration", integration);
    }
    // TODO: report to Sentry (env.SENTRY_DSN)
    return { ok: false, error: message };
  }
}
