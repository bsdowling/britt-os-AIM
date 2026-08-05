import { NextResponse } from "next/server";
import { z } from "zod";
import { getServerSupabase } from "@/lib/supabase/server";
import { isDemoMode } from "@/lib/env";
import { parseNaturalDate } from "@/lib/natural-date";

const schema = z.object({
  kind: z.enum(["task", "contact", "deal", "content"]),
  title: z.string().min(1).max(300),
  when: z.string().optional().default(""),
});

// Quick Add handler (PRD §5.5). Manual anchor, never touched by the cascade.
export async function POST(req: Request) {
  const parsed = schema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid payload" }, { status: 400 });
  }
  const { kind, title, when } = parsed.data;

  if (isDemoMode) {
    return NextResponse.json({ ok: true, demo: true });
  }
  const supabase = await getServerSupabase();
  if (!supabase) return NextResponse.json({ ok: true, demo: true });

  if (kind === "task") {
    const due = parseNaturalDate(when);
    const { error } = await supabase.from("tasks").insert({
      title,
      due_date: due,
      anchor_type: "manual",
      status: "open",
      priority: "normal",
    });
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  } else if (kind === "content") {
    const due = parseNaturalDate(when);
    const { error } = await supabase.from("content_items").insert({
      title,
      status: "idea",
      source_type: "manual",
      target_publish_date: due,
    });
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  } else {
    // contact/deal creation is a deliberate multi-field flow; Quick Add stubs a
    // note in the activity log so nothing is lost. Full forms live on their pages.
    await supabase.from("activity_log").insert({
      entity_type: kind,
      action: "quick_add_stub",
      actor: "britt",
      payload: { title },
    });
  }

  return NextResponse.json({ ok: true });
}
