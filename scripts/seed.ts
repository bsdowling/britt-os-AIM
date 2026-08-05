/**
 * Seed a live Supabase database with the demo dataset (PRD §9 Phase 1: "seed
 * existing deals and content ideas"). Run with: `npm run seed`.
 *
 * Requires NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Idempotent on
 * contacts/properties via their natural keys; deals/tasks/etc. are inserted
 * fresh, so run against an empty database or truncate first.
 */
import { createClient } from "@supabase/supabase-js";
import { demoData } from "../src/lib/demo-data";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !key) {
  console.error("Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to seed.");
  process.exit(1);
}

const supabase = createClient(url, key, { auth: { persistSession: false } });

// Strip generated/computed columns Postgres owns. Returns a loose record so
// foreign-key ids can be remapped before insert.
function omit(row: object, keys: string[]): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) if (!keys.includes(k)) out[k] = v;
  return out;
}

async function main() {
  console.log("Seeding contacts…");
  const contacts = demoData.contacts.map((c) =>
    omit(c, ["id", "needs_response", "created_at", "updated_at", "lead_score"]),
  );
  const { data: insertedContacts, error: cErr } = await supabase
    .from("contacts")
    .upsert(contacts, { onConflict: "fub_person_id" })
    .select("id, fub_person_id");
  if (cErr) throw cErr;

  // Map demo ids -> real ids via fub_person_id.
  const contactIdByFub = new Map(insertedContacts!.map((c) => [c.fub_person_id, c.id]));
  const demoContactToFub = new Map(demoData.contacts.map((c) => [c.id, c.fub_person_id]));
  const realContactId = (demoId: string) =>
    contactIdByFub.get(demoContactToFub.get(demoId)!)!;

  console.log("Seeding properties…");
  const properties = demoData.properties.map((p) => omit(p, ["id", "created_at", "updated_at"]));
  const { data: insertedProps, error: pErr } = await supabase
    .from("properties")
    .upsert(properties, { onConflict: "mls_number" })
    .select("id, mls_number");
  if (pErr) throw pErr;
  const propIdByMls = new Map(insertedProps!.map((p) => [p.mls_number, p.id]));
  const demoPropToMls = new Map(demoData.properties.map((p) => [p.id, p.mls_number]));
  const realPropId = (demoId: string | null) =>
    demoId ? (propIdByMls.get(demoPropToMls.get(demoId)!) ?? null) : null;

  console.log("Seeding deals…");
  const dealIdMap = new Map<string, string>();
  for (const d of demoData.deals) {
    const row = omit(d, ["id", "gross_commission", "created_at", "updated_at"]);
    row.contact_id = realContactId(d.contact_id);
    row.property_id = realPropId(d.property_id);
    const { data, error } = await supabase.from("deals").insert(row).select("id").single();
    if (error) throw error;
    dealIdMap.set(d.id, data!.id);
  }

  console.log("Seeding listings, tasks, appointments, content…");
  for (const l of demoData.listings) {
    const row = omit(l, ["id"]);
    row.deal_id = dealIdMap.get(l.deal_id);
    row.property_id = realPropId(l.property_id);
    await supabase.from("listings").insert(row);
  }
  for (const t of demoData.tasks) {
    const row = omit(t, ["id", "created_at", "updated_at"]);
    row.deal_id = t.deal_id ? dealIdMap.get(t.deal_id) : null;
    row.contact_id = t.contact_id ? realContactId(t.contact_id) : null;
    await supabase.from("tasks").insert(row);
  }
  for (const a of demoData.appointments) {
    const row = omit(a, ["id"]);
    row.deal_id = a.deal_id ? dealIdMap.get(a.deal_id) : null;
    row.contact_id = a.contact_id ? realContactId(a.contact_id) : null;
    row.property_id = realPropId(a.property_id);
    await supabase.from("appointments").insert(row);
  }
  for (const ci of demoData.content) {
    const row = omit(ci, ["id", "created_at", "updated_at"]);
    row.source_deal_id = ci.source_deal_id ? dealIdMap.get(ci.source_deal_id) : null;
    row.source_contact_id = ci.source_contact_id ? realContactId(ci.source_contact_id) : null;
    await supabase.from("content_items").insert(row);
  }

  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
