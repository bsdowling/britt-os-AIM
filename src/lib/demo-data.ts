// Demo fixtures (PRD §12 seed spec: ~40 contacts, 6 active deals, 3 listings,
// tasks across deals, content across pillars/statuses). Dates are generated
// relative to "now" so the dashboard always looks live. Used whenever Supabase
// is not configured (isDemoMode).

import type {
  Appointment,
  Contact,
  ContentItem,
  Deal,
  Listing,
  Property,
  Task,
} from "./types";
import { addDays, todayCentral } from "./date";
import { computeLeadScore } from "./scoring";

const now = new Date();
const TODAY = todayCentral(now);

function isoDaysAgo(days: number, hour = 9): string {
  const d = new Date(now);
  d.setDate(d.getDate() - days);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
}
function isoAt(dayOffset: number, hour: number, minute = 0): string {
  const d = new Date(now);
  d.setDate(d.getDate() + dayOffset);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

let pid = 1000;
function uuid(prefix: string, n: number): string {
  return `${prefix}-${String(n).padStart(4, "0")}`;
}

// ---- Contacts --------------------------------------------------------------
interface ContactSeed {
  first: string;
  last: string;
  stage: string;
  source: string;
  inboundDaysAgo?: number;
  outboundDaysAgo?: number;
  ltv?: number;
}

const contactSeeds: ContactSeed[] = [
  { first: "Marcus", last: "Bell", stage: "Hot", source: "Referral", inboundDaysAgo: 0, outboundDaysAgo: 3 },
  { first: "Dana", last: "Whitfield", stage: "Hot", source: "YouTube", inboundDaysAgo: 0, outboundDaysAgo: 5 },
  { first: "Priya", last: "Nair", stage: "Active Client", source: "Sphere", inboundDaysAgo: 1, outboundDaysAgo: 4 },
  { first: "Travis", last: "Boone", stage: "Hot", source: "Open House", inboundDaysAgo: 2, outboundDaysAgo: 10 },
  { first: "Latoya", last: "Simmons", stage: "Active Client", source: "Referral", inboundDaysAgo: 3, outboundDaysAgo: 3 },
  { first: "Grant", last: "Holloway", stage: "Nurture", source: "Ylopo", inboundDaysAgo: 6, outboundDaysAgo: 2 },
  { first: "Bethany", last: "Cruz", stage: "New Lead", source: "Meta", inboundDaysAgo: 2, outboundDaysAgo: 1 },
  { first: "Sean", last: "Delacroix", stage: "Hot", source: "Referral" },
  { first: "Imani", last: "Rhodes", stage: "Active Client", source: "Sphere", inboundDaysAgo: 9, outboundDaysAgo: 14 },
  { first: "Colton", last: "Reyes", stage: "New Lead", source: "Google", inboundDaysAgo: 1, outboundDaysAgo: 2 },
  { first: "Renee", last: "Abbott", stage: "Nurture", source: "YouTube", inboundDaysAgo: 12, outboundDaysAgo: 3 },
  { first: "Deshawn", last: "Pope", stage: "Past Client", source: "Referral", ltv: 9600 },
  { first: "Kaylee", last: "Monroe", stage: "Hot", source: "Open House", inboundDaysAgo: 0, outboundDaysAgo: 8 },
  { first: "Victor", last: "Ianelli", stage: "Active Client", source: "Ylopo", inboundDaysAgo: 4, outboundDaysAgo: 1 },
  { first: "Nadia", last: "Frost", stage: "New Lead", source: "Meta", inboundDaysAgo: 2 },
  { first: "Bryce", last: "Calloway", stage: "Nurture", source: "Google", inboundDaysAgo: 40, outboundDaysAgo: 4 },
  { first: "Selena", last: "Ortega", stage: "Hot", source: "Referral", inboundDaysAgo: 0, outboundDaysAgo: 1 },
  { first: "Omar", last: "Haddad", stage: "Active Client", source: "Sphere", inboundDaysAgo: 5, outboundDaysAgo: 6 },
  { first: "Kelsey", last: "Vance", stage: "Past Client", source: "Sphere", ltv: 11200 },
  { first: "Trent", last: "Buford", stage: "New Lead", source: "Ylopo", inboundDaysAgo: 1, outboundDaysAgo: 0 },
  { first: "Alicia", last: "Kwan", stage: "Nurture", source: "YouTube", inboundDaysAgo: 15, outboundDaysAgo: 5 },
  { first: "Gabe", last: "Sutter", stage: "Hot", source: "Open House", inboundDaysAgo: 3, outboundDaysAgo: 12 },
  { first: "Monique", last: "Dill", stage: "Active Client", source: "Referral", inboundDaysAgo: 8, outboundDaysAgo: 2 },
  { first: "Parker", last: "Ellison", stage: "New Lead", source: "Google", inboundDaysAgo: 0, outboundDaysAgo: 0 },
  { first: "Rosa", last: "Benitez", stage: "Nurture", source: "Meta", inboundDaysAgo: 22, outboundDaysAgo: 6 },
  { first: "Chad", last: "Mercer", stage: "Past Client", source: "Referral", ltv: 8700 },
  { first: "Yasmin", last: "Attah", stage: "Hot", source: "Sphere", inboundDaysAgo: 0, outboundDaysAgo: 2 },
  { first: "Blake", last: "Fontaine", stage: "Active Client", source: "Ylopo", inboundDaysAgo: 11, outboundDaysAgo: 3 },
  { first: "Erin", last: "Gallagher", stage: "New Lead", source: "YouTube", inboundDaysAgo: 1, outboundDaysAgo: 0 },
  { first: "Damon", last: "Wexler", stage: "Nurture", source: "Google", inboundDaysAgo: 18, outboundDaysAgo: 7 },
  { first: "Sofia", last: "Marchetti", stage: "Hot", source: "Referral", inboundDaysAgo: 2, outboundDaysAgo: 9 },
  { first: "Ty", last: "Robinson", stage: "Active Client", source: "Open House", inboundDaysAgo: 6, outboundDaysAgo: 5 },
  { first: "Hannah", last: "Beaumont", stage: "Past Client", source: "Sphere", ltv: 10400 },
  { first: "Jamal", last: "Ferris", stage: "New Lead", source: "Meta", inboundDaysAgo: 3, outboundDaysAgo: 2 },
  { first: "Court", last: "Nyland", stage: "Nurture", source: "Ylopo", inboundDaysAgo: 33, outboundDaysAgo: 8 },
  { first: "Bianca", last: "Loomis", stage: "Hot", source: "YouTube", inboundDaysAgo: 0, outboundDaysAgo: 6 },
  { first: "Wes", last: "Pryor", stage: "Active Client", source: "Referral", inboundDaysAgo: 7, outboundDaysAgo: 1 },
  { first: "Denise", last: "Alcorn", stage: "New Lead", source: "Google", inboundDaysAgo: 2, outboundDaysAgo: 1 },
  { first: "Rafael", last: "Cordova", stage: "Nurture", source: "Sphere", inboundDaysAgo: 26, outboundDaysAgo: 9 },
  { first: "Kim", last: "Stanhope", stage: "Past Client", source: "Referral", ltv: 12900 },
];

export const contacts: Contact[] = contactSeeds.map((s, i) => {
  const last_inbound_at = s.inboundDaysAgo !== undefined ? isoDaysAgo(s.inboundDaysAgo, 8 + (i % 8)) : null;
  const last_outbound_at = s.outboundDaysAgo !== undefined ? isoDaysAgo(s.outboundDaysAgo, 10) : null;
  const needs_response =
    !!last_inbound_at && (!last_outbound_at || Date.parse(last_inbound_at) > Date.parse(last_outbound_at));
  const base: Contact = {
    id: uuid("contact", i + 1),
    fub_person_id: pid++,
    first_name: s.first,
    last_name: s.last,
    emails: [{ value: `${s.first.toLowerCase()}.${s.last.toLowerCase()}@example.com`, is_primary: true }],
    phones: [{ value: `334-555-${String(1000 + i).slice(-4)}`, is_primary: true }],
    stage: s.stage,
    source: s.source,
    tags: [],
    assigned_pond: null,
    fub_created_at: isoDaysAgo(90 + i),
    last_inbound_at,
    last_outbound_at,
    lifetime_value: s.ltv ?? 0,
    lead_score: 0,
    is_archived: false,
    synced_at: isoDaysAgo(0),
    needs_response,
    created_at: isoDaysAgo(90 + i),
    updated_at: isoDaysAgo(0),
  };
  // New leads are recent additions so the Numbers strip reflects fresh inflow.
  if (s.stage === "New Lead") {
    base.fub_created_at = isoDaysAgo(i % 7, 9);
  }
  const eng = { eventsLast14d: needs_response ? 3 + (i % 4) : i % 3 };
  base.lead_score = computeLeadScore(base, eng, now).score;
  return base;
});

const byName = (first: string): Contact => contacts.find((c) => c.first_name === first)!;

// ---- Properties ------------------------------------------------------------
interface PropSeed {
  addr: string;
  city: string;
  zip: string;
  subdivision: string;
  beds: number;
  baths: number;
  sqft: number;
  mls?: string;
}
const propSeeds: PropSeed[] = [
  { addr: "1234 Elm Street", city: "Montgomery", zip: "36104", subdivision: "Cloverdale", beds: 4, baths: 3, sqft: 2450, mls: "MGM100234" },
  { addr: "88 Ryan Ridge", city: "Pike Road", zip: "36064", subdivision: "The Waters", beds: 5, baths: 4, sqft: 3200, mls: "MGM100891" },
  { addr: "701 Sturbridge Dr", city: "Prattville", zip: "36066", subdivision: "Sturbridge", beds: 4, baths: 3, sqft: 2780, mls: "MGM101120" },
  { addr: "215 Halcyon Blvd", city: "Montgomery", zip: "36117", subdivision: "Halcyon", beds: 3, baths: 2, sqft: 1850, mls: "MGM101455" },
  { addr: "3390 Wetumpka Hwy", city: "Wetumpka", zip: "36092", subdivision: "Emerald Mountain", beds: 4, baths: 3, sqft: 2600, mls: "MGM101788" },
  { addr: "42 Millbrook Lane", city: "Millbrook", zip: "36054", subdivision: "Deer Creek", beds: 3, baths: 2, sqft: 1720, mls: "MGM102001" },
  { addr: "560 Wynlakes Blvd", city: "Montgomery", zip: "36117", subdivision: "Wynlakes", beds: 5, baths: 4, sqft: 3600, mls: "MGM102310" },
];

export const properties: Property[] = propSeeds.map((p, i) => ({
  id: uuid("prop", i + 1),
  mls_number: p.mls ?? null,
  address_line1: p.addr,
  city: p.city,
  state: "AL",
  zip: p.zip,
  county: "Montgomery",
  beds: p.beds,
  baths: p.baths,
  sqft: p.sqft,
  subdivision: p.subdivision,
  school_district: null,
  photos: [],
  created_at: isoDaysAgo(60),
  updated_at: isoDaysAgo(1),
}));

// ---- Deals -----------------------------------------------------------------
// Six active deals spread across the pipeline, dates relative to today.
interface DealSeed {
  contact: string;
  prop: number | null;
  side: "buyer" | "seller";
  status: Deal["status"];
  financing: Deal["financing_type"];
  contract?: number; // days from today (neg = past)
  inspection?: number;
  appraisal?: number;
  financing_d?: number;
  closing?: number | null;
  price?: number;
}
const dealSeeds: DealSeed[] = [
  { contact: "Marcus", prop: 0, side: "buyer", status: "under_contract", financing: "conventional", contract: -3, inspection: 4, appraisal: 12, financing_d: 20, closing: 27, price: 389000 },
  { contact: "Latoya", prop: 2, side: "buyer", status: "inspection", financing: "va", contract: -9, inspection: 1, appraisal: 8, financing_d: 16, closing: 22, price: 315000 },
  { contact: "Priya", prop: 4, side: "buyer", status: "financing", financing: "fha", contract: -21, inspection: -14, appraisal: -6, financing_d: 2, closing: 6, price: 268000 },
  { contact: "Imani", prop: 1, side: "seller", status: "active_listing", financing: null, closing: null, price: 545000 },
  { contact: "Omar", prop: 3, side: "seller", status: "under_contract", financing: "conventional", contract: -5, inspection: 2, appraisal: 10, financing_d: 18, closing: 25, price: 289000 },
  { contact: "Victor", prop: 6, side: "seller", status: "active_listing", financing: null, closing: null, price: 615000 },
  { contact: "Kelsey", prop: 5, side: "buyer", status: "sold", financing: "usda", contract: -40, inspection: -33, appraisal: -25, financing_d: -18, closing: -12, price: 235000 },
];

export const deals: Deal[] = dealSeeds.map((d, i) => {
  const price = d.price ?? null;
  const rate = 0.03;
  return {
    id: uuid("deal", i + 1),
    contact_id: byName(d.contact).id,
    property_id: d.prop !== null ? properties[d.prop].id : null,
    side: d.side,
    status: d.status,
    contract_date: d.contract !== undefined ? addDays(TODAY, d.contract) : null,
    inspection_deadline: d.inspection !== undefined ? addDays(TODAY, d.inspection) : null,
    appraisal_deadline: d.appraisal !== undefined ? addDays(TODAY, d.appraisal) : null,
    financing_deadline: d.financing_d !== undefined ? addDays(TODAY, d.financing_d) : null,
    closing_date: d.closing !== undefined && d.closing !== null ? addDays(TODAY, d.closing) : null,
    sale_price: price,
    commission_rate: rate,
    financing_type: d.financing,
    brokerage_file_url: null,
    notes: null,
    dead_reason: null,
    gross_commission: (price ?? 0) * rate,
    created_at: isoDaysAgo(30),
    updated_at: isoDaysAgo(0),
  };
});

// ---- Listings --------------------------------------------------------------
// Three active listings tied to seller deals.
export const listings: Listing[] = [
  {
    id: uuid("listing", 1),
    deal_id: deals[3].id,
    property_id: properties[1].id,
    list_date: addDays(TODAY, -48),
    list_price: 559000,
    current_price: 545000,
    price_history: [
      { date: addDays(TODAY, -48), price: 559000, reason: "list" },
      { date: addDays(TODAY, -18), price: 545000, reason: "reduction" },
    ],
    mls_status: "Active",
    showing_count_7d: 0,
    showing_count_total: 14,
    unread_feedback_count: 3,
  },
  {
    id: uuid("listing", 2),
    deal_id: deals[5].id,
    property_id: properties[6].id,
    list_date: addDays(TODAY, -12),
    list_price: 615000,
    current_price: 615000,
    price_history: [{ date: addDays(TODAY, -12), price: 615000, reason: "list" }],
    mls_status: "Active",
    showing_count_7d: 5,
    showing_count_total: 9,
    unread_feedback_count: 1,
  },
  {
    id: uuid("listing", 3),
    deal_id: deals[4].id,
    property_id: properties[3].id,
    list_date: addDays(TODAY, -60),
    list_price: 299000,
    current_price: 289000,
    price_history: [
      { date: addDays(TODAY, -60), price: 299000, reason: "list" },
      { date: addDays(TODAY, -30), price: 289000, reason: "reduction" },
    ],
    mls_status: "Under Contract",
    showing_count_7d: 0,
    showing_count_total: 22,
    unread_feedback_count: 0,
  },
];

// ---- Tasks -----------------------------------------------------------------
// A mix of overdue, due-today, and upcoming across the active deals, plus a
// couple attached to a contact only.
interface TaskSeed {
  deal?: number;
  contact?: string;
  title: string;
  due: number; // days from today
  anchor: Task["anchor_type"];
  offset: number | null;
  priority: Task["priority"];
  status?: Task["status"];
  pinned?: boolean;
  clientVisible?: boolean;
}
const taskSeeds: TaskSeed[] = [
  // Deal 0 (Marcus, under contract)
  { deal: 0, title: "Send executed contract to client and lender", due: -3, anchor: "contract", offset: 0, priority: "high", status: "done" },
  { deal: 0, title: "Confirm earnest money delivered", due: -2, anchor: "contract", offset: 1, priority: "high" },
  { deal: 0, title: "Order inspection", due: -2, anchor: "contract", offset: 1, priority: "high", status: "done" },
  { deal: 0, title: "Check inspection scheduled", due: 0, anchor: "contract", offset: 3, priority: "normal" },
  { deal: 0, title: "Attend inspection", due: 4, anchor: "inspection", offset: 0, priority: "high", clientVisible: true },
  { deal: 0, title: "Review inspection report with client", due: 5, anchor: "inspection", offset: 1, priority: "high" },
  // Deal 1 (Latoya, VA, inspection tomorrow)
  { deal: 1, title: "Confirm appraisal ordered by correct assigned appraiser", due: -1, anchor: "contract", offset: 3, priority: "high" },
  { deal: 1, title: "Attend inspection", due: 1, anchor: "inspection", offset: 0, priority: "high", clientVisible: true },
  { deal: 1, title: "Confirm termite / pest letter ordered", due: 12, anchor: "closing", offset: -10, priority: "high" },
  // Deal 2 (Priya, financing, closing in 6d)
  { deal: 2, title: "Lender check-in, conditions cleared?", due: -5, anchor: "financing", offset: -7, priority: "high" },
  { deal: 2, title: "Confirm clear to close", due: 2, anchor: "financing", offset: 0, priority: "high" },
  { deal: 2, title: "Send wire fraud warning to client", due: 3, anchor: "closing", offset: -3, priority: "high", clientVisible: true },
  { deal: 2, title: "Schedule final walkthrough", due: 4, anchor: "closing", offset: -2, priority: "high" },
  { deal: 2, title: "Final walkthrough", due: 5, anchor: "closing", offset: -1, priority: "high", clientVisible: true },
  { deal: 2, title: "Attend closing", due: 6, anchor: "closing", offset: 0, priority: "high", pinned: true, clientVisible: true },
  // Deal 4 (Omar, seller under contract)
  { deal: 4, title: "Confirm earnest money received", due: -1, anchor: "contract", offset: 1, priority: "high" },
  { deal: 4, title: "Prepare for inspection access", due: 1, anchor: "inspection", offset: -1, priority: "normal" },
  { deal: 4, title: "Order payoff", due: 18, anchor: "closing", offset: -7, priority: "high" },
  // Deal 3 (Imani, active listing)
  { deal: 3, title: "Weekly seller update call", due: 0, anchor: "manual", offset: null, priority: "normal" },
  { deal: 3, title: "Price and position review", due: 2, anchor: "manual", offset: null, priority: "high" },
  // Deal 5 (Victor, active listing)
  { deal: 5, title: "First seller update call", due: 0, anchor: "list_date", offset: 7, priority: "high" },
  // Contact-only tasks (no deal yet)
  { contact: "Sean", title: "Call back re: financing pre-approval", due: 0, anchor: "manual", offset: null, priority: "high" },
  { contact: "Kaylee", title: "Send Pike Road listings roundup", due: -1, anchor: "manual", offset: null, priority: "normal" },
  { contact: "Selena", title: "Schedule buyer consult", due: 1, anchor: "manual", offset: null, priority: "normal" },
];

export const tasks: Task[] = taskSeeds.map((t, i) => ({
  id: uuid("task", i + 1),
  deal_id: t.deal !== undefined ? deals[t.deal].id : null,
  contact_id: t.contact ? byName(t.contact).id : t.deal !== undefined ? deals[t.deal].contact_id : null,
  title: t.title,
  description: null,
  due_date: addDays(TODAY, t.due),
  due_time: null,
  anchor_type: t.anchor,
  anchor_offset_days: t.offset,
  is_pinned: t.pinned ?? false,
  status: t.status ?? "open",
  priority: t.priority,
  template_item_id: null,
  is_client_visible: t.clientVisible ?? false,
  completed_at: t.status === "done" ? isoDaysAgo(1) : null,
  created_at: isoDaysAgo(20),
  updated_at: isoDaysAgo(0),
}));

// ---- Appointments ----------------------------------------------------------
export const appointments: Appointment[] = [
  {
    id: uuid("appt", 1),
    contact_id: byName("Latoya").id,
    property_id: properties[2].id,
    deal_id: deals[1].id,
    source: "showingtime",
    type: "showing",
    starts_at: isoAt(0, 11, 0),
    ends_at: isoAt(0, 11, 30),
    location: "701 Sturbridge Dr, Prattville",
    notes: null,
    status: "scheduled",
    feedback: null,
  },
  {
    id: uuid("appt", 2),
    contact_id: byName("Selena").id,
    property_id: null,
    deal_id: null,
    source: "calendly",
    type: "buyer_consult",
    starts_at: isoAt(0, 15, 30),
    ends_at: isoAt(0, 16, 15),
    location: "Zoom",
    notes: "Referral from Deshawn",
    status: "scheduled",
    feedback: null,
  },
  {
    id: uuid("appt", 3),
    contact_id: byName("Marcus").id,
    property_id: properties[0].id,
    deal_id: deals[0].id,
    source: "manual",
    type: "inspection",
    starts_at: isoAt(4, 9, 0),
    ends_at: isoAt(4, 11, 0),
    location: "1234 Elm Street",
    notes: null,
    status: "scheduled",
    feedback: null,
  },
];

// ---- Content ---------------------------------------------------------------
interface ContentSeed {
  title: string;
  pillar: ContentItem["pillar"];
  format: ContentItem["format"];
  status: ContentItem["status"];
  publish?: number; // days from today
  hook?: string;
  sourceType?: ContentItem["source_type"];
  sourceContact?: string;
}
const contentSeeds: ContentSeed[] = [
  { title: "Is Pike Road actually worth the price difference?", pillar: "pros_cons", format: "youtube_long", status: "scripted", publish: 3, hook: "Everybody says Pike Road is 'worth it.' Let's actually run the numbers.", sourceType: "contact_question", sourceContact: "Kaylee" },
  { title: "5 Cloverdale streets locals fight to live on", pillar: "area_guides", format: "reel", status: "filmed", publish: 1, hook: "This one street in Cloverdale never hits the market." },
  { title: "What $300k actually buys in Prattville right now", pillar: "cost_of_living", format: "reel", status: "idea", publish: 4, hook: "Three houses, same price, wildly different." },
  { title: "August market update — rates, inventory, what it means", pillar: "livestream", format: "livestream", status: "scheduled", publish: 2, hook: "Live Thursday: where the Montgomery market actually is." },
  { title: "The truth nobody tells you about buying new construction", pillar: "gut_check", format: "youtube_long", status: "idea", hook: "Builders don't want you to know this one thing." },
  { title: "Weekly email — 3 new listings under $350k", pillar: "area_guides", format: "email", status: "idea", publish: 1 },
  { title: "Wetumpka vs Millbrook: which fits your family?", pillar: "pros_cons", format: "carousel", status: "editing", publish: 0 },
  { title: "Property taxes in Montgomery County, explained", pillar: "cost_of_living", format: "blog", status: "published", publish: -6 },
  { title: "Why I stopped recommending this popular subdivision", pillar: "gut_check", format: "reel", status: "idea", hook: "I used to send everyone here. Not anymore." },
  { title: "Emerald Mountain area guide", pillar: "area_guides", format: "youtube_long", status: "published", publish: -12 },
  { title: "Should you buy before you sell? A gut check", pillar: "gut_check", format: "reel", status: "scripted", publish: 5 },
  { title: "Live Q&A: first-time buyer questions", pillar: "livestream", format: "livestream", status: "published", publish: -9 },
];

export const content: ContentItem[] = contentSeeds.map((c, i) => ({
  id: uuid("content", i + 1),
  title: c.title,
  pillar: c.pillar,
  format: c.format,
  status: c.status,
  target_publish_date: c.publish !== undefined ? addDays(TODAY, c.publish) : null,
  hook: c.hook ?? null,
  notes: null,
  source_type: c.sourceType ?? "manual",
  source_deal_id: null,
  source_contact_id: c.sourceContact ? byName(c.sourceContact).id : null,
  canva_url: null,
  published_url: null,
  created_at: isoDaysAgo(14 - (i % 14)),
  updated_at: isoDaysAgo(0),
}));

export const demoData = {
  contacts,
  properties,
  deals,
  listings,
  tasks,
  appointments,
  content,
};
