/**
 * Render the demo dataset to a portable SQL file of INSERT statements, so the
 * database can be populated by pasting into the Supabase SQL Editor when direct
 * network access isn't available. Run: `npx tsx scripts/gen-seed-sql.ts`.
 *
 * Real UUIDs are generated for every row and used consistently for foreign keys.
 * Generated columns (needs_response, gross_commission) are never inserted.
 */
import { randomUUID } from "crypto";
import { writeFileSync } from "fs";
import { demoData } from "../src/lib/demo-data";

// --- literal serializers ----------------------------------------------------
function s(v: string | null | undefined): string {
  if (v === null || v === undefined) return "null";
  return "'" + v.replace(/'/g, "''") + "'";
}
function n(v: number | null | undefined): string {
  return v === null || v === undefined ? "null" : String(v);
}
function b(v: boolean): string {
  return v ? "true" : "false";
}
function json(v: unknown): string {
  if (v === null || v === undefined) return "null";
  return "'" + JSON.stringify(v).replace(/'/g, "''") + "'::jsonb";
}
function textArray(v: string[]): string {
  if (!v || v.length === 0) return "'{}'";
  return "ARRAY[" + v.map((x) => s(x)).join(",") + "]::text[]";
}

// --- id maps ----------------------------------------------------------------
const id = {
  contact: new Map<string, string>(),
  property: new Map<string, string>(),
  deal: new Map<string, string>(),
};
demoData.contacts.forEach((c) => id.contact.set(c.id, randomUUID()));
demoData.properties.forEach((p) => id.property.set(p.id, randomUUID()));
demoData.deals.forEach((d) => id.deal.set(d.id, randomUUID()));

const rc = (demoId: string | null) => (demoId ? s(id.contact.get(demoId)!) : "null");
const rp = (demoId: string | null) => (demoId ? s(id.property.get(demoId)!) : "null");
const rd = (demoId: string | null) => (demoId ? s(id.deal.get(demoId)!) : "null");

const out: string[] = [];
out.push("-- Britt's OS — sample data seed (generated). Run after 0001_init.sql + 0002_templates_seed.sql.");
out.push("begin;");

// contacts
out.push("\n-- contacts");
for (const c of demoData.contacts) {
  out.push(
    `insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values (` +
      [
        s(id.contact.get(c.id)!),
        n(c.fub_person_id),
        s(c.first_name),
        s(c.last_name),
        json(c.emails),
        json(c.phones),
        s(c.stage),
        s(c.source),
        textArray(c.tags),
        s(c.fub_created_at),
        s(c.last_inbound_at),
        s(c.last_outbound_at),
        n(c.lifetime_value),
        n(c.lead_score),
        b(c.is_archived),
        s(c.synced_at),
      ].join(", ") +
      ") on conflict (fub_person_id) do nothing;",
  );
}

// properties
out.push("\n-- properties");
for (const p of demoData.properties) {
  out.push(
    `insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values (` +
      [
        s(id.property.get(p.id)!),
        s(p.mls_number),
        s(p.address_line1),
        s(p.city),
        s(p.state),
        s(p.zip),
        s(p.county),
        n(p.beds),
        n(p.baths),
        n(p.sqft),
        s(p.subdivision),
      ].join(", ") +
      ") on conflict (mls_number) do nothing;",
  );
}

// deals
out.push("\n-- deals");
for (const d of demoData.deals) {
  out.push(
    `insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values (` +
      [
        s(id.deal.get(d.id)!),
        rc(d.contact_id),
        rp(d.property_id),
        s(d.side),
        s(d.status),
        s(d.contract_date),
        s(d.inspection_deadline),
        s(d.appraisal_deadline),
        s(d.financing_deadline),
        s(d.closing_date),
        n(d.sale_price),
        n(d.commission_rate),
        s(d.financing_type),
      ].join(", ") +
      ");",
  );
}

// listings
out.push("\n-- listings");
for (const l of demoData.listings) {
  out.push(
    `insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values (` +
      [
        s(randomUUID()),
        rd(l.deal_id),
        rp(l.property_id),
        s(l.list_date),
        n(l.list_price),
        n(l.current_price),
        json(l.price_history),
        s(l.mls_status),
        n(l.showing_count_7d),
        n(l.showing_count_total),
        n(l.unread_feedback_count),
      ].join(", ") +
      ");",
  );
}

// tasks
out.push("\n-- tasks");
for (const t of demoData.tasks) {
  out.push(
    `insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values (` +
      [
        s(randomUUID()),
        rd(t.deal_id),
        rc(t.contact_id),
        s(t.title),
        s(t.description),
        s(t.due_date),
        t.anchor_type ? s(t.anchor_type) : "null",
        n(t.anchor_offset_days),
        b(t.is_pinned),
        s(t.status),
        s(t.priority),
        b(t.is_client_visible),
        s(t.completed_at),
      ].join(", ") +
      ");",
  );
}

// appointments
out.push("\n-- appointments");
for (const a of demoData.appointments) {
  out.push(
    `insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values (` +
      [
        s(randomUUID()),
        rc(a.contact_id),
        rp(a.property_id),
        rd(a.deal_id),
        s(a.source),
        s(a.type),
        s(a.starts_at),
        s(a.ends_at),
        s(a.location),
        s(a.notes),
        s(a.status),
        s(a.feedback),
      ].join(", ") +
      ");",
  );
}

// content_items
out.push("\n-- content_items");
for (const ci of demoData.content) {
  out.push(
    `insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values (` +
      [
        s(randomUUID()),
        s(ci.title),
        ci.pillar ? s(ci.pillar) : "null",
        ci.format ? s(ci.format) : "null",
        s(ci.status),
        s(ci.target_publish_date),
        s(ci.hook),
        s(ci.notes),
        ci.source_type ? s(ci.source_type) : "null",
        rd(ci.source_deal_id),
        rc(ci.source_contact_id),
      ].join(", ") +
      ");",
  );
}

out.push("\ncommit;");

const sql = out.join("\n") + "\n";
writeFileSync("supabase/seed.sql", sql);
console.log(`Wrote supabase/seed.sql (${sql.length} bytes, ${demoData.contacts.length} contacts, ${demoData.deals.length} deals)`);
