import { NextResponse } from "next/server";
import crypto from "crypto";
import { z } from "zod";
import { getServiceSupabase } from "@/lib/supabase/server";
import { isDemoMode } from "@/lib/env";

// FUB webhook receiver (PRD §7.1). Requirements: verify signature, return 200
// within 5s (queue the work, don't process inline), dedupe on event id so a
// redelivery does not double-write.
//
// FUB signs the raw body with the app's system key (HMAC-SHA256) in the
// `FUB-Signature` header. We verify before trusting anything.

const eventSchema = z.object({
  event: z.string(),
  eventId: z.string().nullish(),
  resourceIds: z.array(z.number()).nullish(),
  uri: z.string().nullish(),
});

function verifySignature(raw: string, signature: string | null): boolean {
  const secret = process.env.FUB_WEBHOOK_SECRET;
  if (!secret) return true; // dev: accept when unset
  if (!signature) return false;
  const expected = crypto.createHmac("sha256", secret).update(raw).digest("hex");
  // constant-time compare
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export async function POST(req: Request) {
  const raw = await req.text();
  const signature = req.headers.get("fub-signature") ?? req.headers.get("x-fub-signature");

  if (!verifySignature(raw, signature)) {
    return NextResponse.json({ ok: false, error: "bad signature" }, { status: 401 });
  }

  const parsed = eventSchema.safeParse(JSON.parse(raw || "{}"));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "bad payload" }, { status: 400 });
  }
  const evt = parsed.data;

  if (isDemoMode) {
    return NextResponse.json({ ok: true, demo: true, event: evt.event });
  }

  const supabase = getServiceSupabase();
  if (supabase) {
    // Dedupe + queue: record the event; a worker/cron drains it. Returning fast
    // keeps us inside FUB's 5s window.
    const dedupeKey = `fub:${evt.eventId ?? crypto.createHash("sha1").update(raw).digest("hex")}`;
    await supabase
      .from("notifications")
      .upsert(
        {
          type: `webhook.${evt.event}`,
          channel: "in_app",
          status: "pending",
          dedupe_key: dedupeKey,
          payload: evt,
        },
        { onConflict: "dedupe_key", ignoreDuplicates: true },
      );
    await supabase.from("activity_log").insert({
      entity_type: "fub_webhook",
      action: evt.event,
      actor: "system",
      payload: evt,
    });
  }

  return NextResponse.json({ ok: true });
}
