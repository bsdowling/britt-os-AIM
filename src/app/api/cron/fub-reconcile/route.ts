import { NextResponse } from "next/server";
import { authorizeCron, recordSyncRun } from "@/lib/cron";
import { getServiceSupabase } from "@/lib/supabase/server";
import { listPeople, mapPersonToContact } from "@/lib/integrations/fub";
import { isDemoMode, env } from "@/lib/env";

// Nightly FUB reconciliation (PRD §7.1). Webhooks get missed; this pulls all
// people modified since the stored cursor and upserts the mirror.
export async function GET(req: Request) {
  const unauth = authorizeCron(req);
  if (unauth) return unauth;

  if (isDemoMode || !env.fubApiKey) {
    return NextResponse.json({ ok: true, skipped: true, reason: "FUB not configured" });
  }

  const result = await recordSyncRun("fub", async () => {
    const supabase = getServiceSupabase();
    if (!supabase) return { note: "no service client" };

    const { data: state } = await supabase
      .from("sync_state")
      .select("cursor")
      .eq("integration", "fub")
      .maybeSingle();

    const updatedAfter = state?.cursor ?? undefined;
    let offset = 0;
    let synced = 0;
    let newestCursor = updatedAfter ?? new Date().toISOString();

    for (;;) {
      const { people, next } = await listPeople({ updatedAfter, limit: 100, offset });
      if (people.length === 0) break;
      for (const p of people) {
        const row = mapPersonToContact(p);
        await supabase.from("contacts").upsert(row, { onConflict: "fub_person_id" });
        synced += 1;
      }
      newestCursor = new Date().toISOString();
      if (!next) break;
      offset += people.length;
      if (offset > 5000) break; // safety valve
    }

    return { cursor: newestCursor, note: `reconciled ${synced} people` };
  });

  return NextResponse.json(result, { status: result.ok ? 200 : 500 });
}
