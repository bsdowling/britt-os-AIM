import { NextResponse } from "next/server";
import { authorizeCron, recordSyncRun } from "@/lib/cron";
import { getServiceSupabase } from "@/lib/supabase/server";
import { computeLeadScore } from "@/lib/scoring";
import { isDemoMode } from "@/lib/env";

// Nightly full lead-score recalculation (PRD §4.4, cron 3am Central).
export async function GET(req: Request) {
  const unauth = authorizeCron(req);
  if (unauth) return unauth;

  if (isDemoMode) {
    return NextResponse.json({ ok: true, demo: true, note: "scores computed on read in demo mode" });
  }

  const result = await recordSyncRun("recalc-scores", async () => {
    const supabase = getServiceSupabase();
    if (!supabase) return { note: "no service client" };

    const { data: contacts } = await supabase
      .from("contacts")
      .select("id, stage, source, last_inbound_at, last_outbound_at, needs_response")
      .eq("is_archived", false);

    let updated = 0;
    for (const c of contacts ?? []) {
      // Engagement volume would come from a FUB events count; use a placeholder
      // until the events table is wired (Phase 5).
      const { score } = computeLeadScore(c, { eventsLast14d: c.needs_response ? 3 : 1 });
      await supabase.from("contacts").update({ lead_score: score }).eq("id", c.id);
      updated += 1;
    }
    return { note: `recalculated ${updated} scores` };
  });

  return NextResponse.json(result, { status: result.ok ? 200 : 500 });
}
