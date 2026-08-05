import { NextResponse } from "next/server";
import { getServerSupabase } from "@/lib/supabase/server";
import { isDemoMode } from "@/lib/env";

// Complete a task. One tap, no modal (PRD §4.1). No-op in demo mode so the
// optimistic client UI still works without a database.
export async function POST(
  _req: Request,
  ctx: { params: Promise<{ id: string }> },
) {
  const { id } = await ctx.params;

  if (isDemoMode) {
    return NextResponse.json({ ok: true, demo: true });
  }

  const supabase = await getServerSupabase();
  if (!supabase) return NextResponse.json({ ok: true, demo: true });

  const { error } = await supabase
    .from("tasks")
    .update({ status: "done", completed_at: new Date().toISOString() })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }
  return NextResponse.json({ ok: true });
}
