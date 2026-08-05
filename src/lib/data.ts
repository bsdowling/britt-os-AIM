// Data-access + view-model assembly for the one-screen dashboard (PRD §4).
// Panel computations are pure functions over a Dataset, so the same logic runs
// whether the data comes from demo fixtures or Supabase.

import type {
  Appointment,
  Contact,
  ContentItem,
  Deal,
  Listing,
  Property,
  Task,
} from "./types";
import { STAGE_LABELS } from "./types";
import { isDemoMode } from "./env";
import { getServerSupabase } from "./supabase/server";
import {
  daysFromToday,
  hoursSince,
  todayCentral,
} from "./date";
import {
  computeDealHealth,
  milestoneIndex,
  nextDeadline,
  openTaskCount,
} from "./deal-health";
import { computeLeadScore } from "./scoring";

export interface Dataset {
  contacts: Contact[];
  properties: Property[];
  deals: Deal[];
  listings: Listing[];
  tasks: Task[];
  appointments: Appointment[];
  content: ContentItem[];
}

export async function loadDataset(): Promise<Dataset> {
  if (isDemoMode) {
    const { demoData } = await import("./demo-data");
    // clone so mutations (optimistic completes in demo) don't leak between requests
    return structuredClone(demoData);
  }
  const supabase = await getServerSupabase();
  if (!supabase) {
    const { demoData } = await import("./demo-data");
    return structuredClone(demoData);
  }
  const [contacts, properties, deals, listings, tasks, appointments, content] =
    await Promise.all([
      supabase.from("contacts").select("*").eq("is_archived", false),
      supabase.from("properties").select("*"),
      supabase.from("deals").select("*").neq("status", "dead"),
      supabase.from("listings").select("*"),
      supabase.from("tasks").select("*"),
      supabase.from("appointments").select("*"),
      supabase.from("content_items").select("*"),
    ]);
  return {
    contacts: contacts.data ?? [],
    properties: properties.data ?? [],
    deals: deals.data ?? [],
    listings: listings.data ?? [],
    tasks: tasks.data ?? [],
    appointments: appointments.data ?? [],
    content: content.data ?? [],
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
export function contactName(c: Contact | undefined): string {
  if (!c) return "Unknown";
  return [c.first_name, c.last_name].filter(Boolean).join(" ") || "Unknown";
}

export function propertyLabel(p: Property | undefined): string {
  if (!p) return "Searching";
  return p.address_line1 || [p.city, p.state].filter(Boolean).join(", ") || "Property";
}

function index<T extends { id: string }>(rows: T[]): Map<string, T> {
  return new Map(rows.map((r) => [r.id, r]));
}

// ---------------------------------------------------------------------------
// Panel 1: TODAY
// ---------------------------------------------------------------------------
export interface TodayRow {
  kind: "task" | "appointment";
  id: string;
  time: string | null; // ISO for appts / timed tasks
  timeLabel: string | null;
  title: string;
  chip: { label: string; kind: "deal" | "contact"; id: string } | null;
  overdue: boolean;
  priority?: string;
}

export interface TodayPanel {
  overdueCount: number;
  rows: TodayRow[];
}

export function buildToday(ds: Dataset, now = new Date()): TodayPanel {
  const today = todayCentral(now);
  const dealById = index(ds.deals);
  const contactById = index(ds.contacts);
  const propById = index(ds.properties);

  const taskRows: TodayRow[] = ds.tasks
    .filter((t) => t.status === "open" && t.due_date && t.due_date <= today)
    .map((t) => {
      const deal = t.deal_id ? dealById.get(t.deal_id) : undefined;
      const contact = t.contact_id ? contactById.get(t.contact_id) : undefined;
      const chip = deal
        ? {
            label:
              propertyLabel(deal.property_id ? propById.get(deal.property_id) : undefined),
            kind: "deal" as const,
            id: deal.id,
          }
        : contact
          ? { label: contactName(contact), kind: "contact" as const, id: contact.id }
          : null;
      return {
        kind: "task" as const,
        id: t.id,
        time: null,
        timeLabel: null,
        title: t.title,
        chip,
        overdue: !!t.due_date && t.due_date < today,
        priority: t.priority,
      };
    });

  const apptRows: TodayRow[] = ds.appointments
    .filter((a) => a.status === "scheduled" && a.starts_at.slice(0, 10) === today)
    .map((a) => {
      const deal = a.deal_id ? dealById.get(a.deal_id) : undefined;
      const contact = a.contact_id ? contactById.get(a.contact_id) : undefined;
      const chip = contact
        ? { label: contactName(contact), kind: "contact" as const, id: contact.id }
        : deal
          ? { label: "Deal", kind: "deal" as const, id: deal.id }
          : null;
      return {
        kind: "appointment" as const,
        id: a.id,
        time: a.starts_at,
        timeLabel: new Intl.DateTimeFormat("en-US", {
          hour: "numeric",
          minute: "2-digit",
          timeZone: "America/Chicago",
        }).format(new Date(a.starts_at)),
        title: apptTitle(a),
        chip,
        overdue: false,
      };
    });

  // Sort chronologically: timed items by time, untimed tasks at the bottom.
  // Overdue tasks are surfaced separately as a count/band by the panel.
  const timed = apptRows.sort((a, b) => (a.time! < b.time! ? -1 : 1));
  const overdue = taskRows.filter((r) => r.overdue);
  const dueToday = taskRows.filter((r) => !r.overdue);

  return {
    overdueCount: overdue.length,
    rows: [...overdue, ...timed, ...dueToday],
  };
}

function apptTitle(a: Appointment): string {
  const map: Record<string, string> = {
    showing: "Showing",
    listing_appt: "Listing appointment",
    buyer_consult: "Buyer consult",
    closing: "Closing",
    inspection: "Inspection",
    photo_shoot: "Photo shoot",
    other: "Appointment",
  };
  return map[a.type] ?? "Appointment";
}

// ---------------------------------------------------------------------------
// Panel 2: WHO NEEDS ME
// ---------------------------------------------------------------------------
export interface WhoRow {
  id: string;
  name: string;
  detail: string;
  contactId?: string;
  dealId?: string;
}
export interface WhoNeedsMe {
  waitingOnYou: WhoRow[];
  deadline72h: WhoRow[];
  goneQuiet: WhoRow[];
}

const GONE_QUIET_DAYS = 7; // [CUSTOMIZE — PRD §4.2]

export function buildWhoNeedsMe(ds: Dataset, now = new Date()): WhoNeedsMe {
  const propById = index(ds.properties);
  const contactById = index(ds.contacts);

  const waitingOnYou: WhoRow[] = ds.contacts
    .filter((c) => c.needs_response)
    .map((c) => ({
      contact: c,
      hrs: hoursSince(c.last_inbound_at, now) ?? 0,
    }))
    .sort((a, b) => b.hrs - a.hrs)
    .map(({ contact, hrs }) => ({
      id: contact.id,
      contactId: contact.id,
      name: contactName(contact),
      detail: `${hrs}h waiting`,
    }));

  const deadline72h: WhoRow[] = ds.deals
    .filter((d) => d.status !== "dead" && d.status !== "sold")
    .map((d) => ({ deal: d, nd: nextDeadline(d, now) }))
    .filter(({ deal, nd }) => {
      if (nd.days === null || nd.days > 3) return false;
      return openTaskCount(deal.id, ds.tasks) > 0;
    })
    .sort((a, b) => (a.nd.days ?? 0) - (b.nd.days ?? 0))
    .map(({ deal, nd }) => ({
      id: deal.id,
      dealId: deal.id,
      contactId: deal.contact_id,
      name: contactName(contactById.get(deal.contact_id)),
      detail: `${STAGE_LABELS[nd.type ?? ""] ?? nd.type} in ${nd.days}d`,
    }));

  const activeStages = new Set(["Active Client"]);
  const apptContactIds = new Set(
    ds.appointments.filter((a) => a.status === "scheduled").map((a) => a.contact_id),
  );
  const goneQuiet: WhoRow[] = ds.contacts
    .filter((c) => activeStages.has(c.stage ?? ""))
    .map((c) => {
      const last = mostRecentTouch(c);
      const hrs = hoursSince(last, now);
      return { c, days: hrs === null ? null : Math.floor(hrs / 24) };
    })
    .filter(({ c, days }) => days !== null && days > GONE_QUIET_DAYS && !apptContactIds.has(c.id))
    .sort((a, b) => (b.days ?? 0) - (a.days ?? 0))
    .map(({ c, days }) => ({
      id: c.id,
      contactId: c.id,
      name: contactName(c),
      detail: `Quiet ${days}d`,
    }));

  return { waitingOnYou, deadline72h, goneQuiet };
}

function mostRecentTouch(c: Contact): string | null {
  const a = c.last_inbound_at;
  const b = c.last_outbound_at;
  if (!a) return b;
  if (!b) return a;
  return Date.parse(a) > Date.parse(b) ? a : b;
}

// ---------------------------------------------------------------------------
// Panel 3: ACTIVE DEALS
// ---------------------------------------------------------------------------
export interface DealCard {
  id: string;
  clientName: string;
  address: string;
  milestoneIndex: number;
  nextDeadlineType: string | null;
  nextDeadlineDays: number | null;
  openTasks: number;
  health: "green" | "amber" | "red";
  status: string;
}

export function buildActiveDeals(ds: Dataset, now = new Date()): DealCard[] {
  const propById = index(ds.properties);
  const contactById = index(ds.contacts);
  return ds.deals
    .filter((d) => d.status !== "dead" && d.status !== "sold")
    .map((d) => {
      const nd = nextDeadline(d, now);
      return {
        id: d.id,
        clientName: contactName(contactById.get(d.contact_id)),
        address: propertyLabel(d.property_id ? propById.get(d.property_id) : undefined),
        milestoneIndex: milestoneIndex(d.status),
        nextDeadlineType: nd.type ? STAGE_LABELS[nd.type] ?? nd.type : null,
        nextDeadlineDays: nd.days,
        openTasks: openTaskCount(d.id, ds.tasks),
        health: computeDealHealth(d, ds.tasks, now),
        status: d.status,
      };
    })
    .sort((a, b) => {
      const av = a.nextDeadlineDays ?? 9999;
      const bv = b.nextDeadlineDays ?? 9999;
      return av - bv;
    });
}

// ---------------------------------------------------------------------------
// Panel 4: LEAD FOLLOW-UP QUEUE
// ---------------------------------------------------------------------------
export interface LeadRow {
  id: string;
  name: string;
  score: number;
  source: string | null;
  daysSinceTouch: number | null;
  reason: string;
}

export function buildLeadQueue(ds: Dataset, now = new Date(), limit = 15): LeadRow[] {
  return ds.contacts
    .filter((c) => !c.is_archived && c.stage !== "Past Client")
    .map((c) => {
      const eng = { eventsLast14d: c.needs_response ? 3 : 1 };
      const { score, reason } = computeLeadScore(c, eng, now);
      const last = mostRecentTouch(c);
      const hrs = hoursSince(last, now);
      return {
        id: c.id,
        name: contactName(c),
        score: c.lead_score || score,
        source: c.source,
        daysSinceTouch: hrs === null ? null : Math.floor(hrs / 24),
        reason,
      };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}

// ---------------------------------------------------------------------------
// Panel 5: CONTENT ENGINE
// ---------------------------------------------------------------------------
export interface ContentSlot {
  label: string;
  format: string;
  filled: ContentItem | null;
  urgency: "ok" | "amber" | "red"; // empty upcoming = amber, empty past/today = red
}
export interface ContentEngine {
  slots: ContentSlot[];
  ideas: ContentItem[];
}

// Fixed weekly commitment [CUSTOMIZE cadence — PRD §4.5]
const WEEKLY_SLOTS: { label: string; format: ContentItem["format"] }[] = [
  { label: "YouTube long-form", format: "youtube_long" },
  { label: "Reel", format: "reel" },
  { label: "Reel", format: "reel" },
  { label: "Email", format: "email" },
  { label: "Livestream", format: "livestream" },
];

export function buildContentEngine(ds: Dataset, now = new Date()): ContentEngine {
  const today = todayCentral(now);
  // items targeted for the current week (today .. +6) or already in progress
  const weekItems = ds.content.filter((c) => {
    if (!c.target_publish_date) return false;
    const d = daysFromToday(c.target_publish_date, now);
    return d !== null && d >= -1 && d <= 6 && c.status !== "published";
  });

  const used = new Set<string>();
  const slots: ContentSlot[] = WEEKLY_SLOTS.map((slot) => {
    const match = weekItems.find((c) => c.format === slot.format && !used.has(c.id));
    if (match) used.add(match.id);
    let urgency: ContentSlot["urgency"] = "ok";
    if (!match) {
      urgency = "amber"; // empty upcoming slot
    }
    return { label: slot.label, format: slot.format ?? "", filled: match ?? null, urgency };
  });

  const ideas = ds.content
    .filter((c) => c.status === "idea")
    .sort((a, b) => (a.target_publish_date ?? "9999").localeCompare(b.target_publish_date ?? "9999"));

  return { slots, ideas };
}

// ---------------------------------------------------------------------------
// Panel 6: LISTING PULSE
// ---------------------------------------------------------------------------
export interface ListingRow {
  id: string;
  address: string;
  listPrice: number | null;
  currentPrice: number | null;
  dom: number | null;
  showings7d: number;
  unreadFeedback: number;
  reductionFlag: boolean;
}

const DOM_MEDIAN = 45; // [CUSTOMIZE once local numbers exist — PRD §3]

export function buildListingPulse(ds: Dataset, now = new Date()): ListingRow[] {
  const propById = index(ds.properties);
  const dealById = index(ds.deals);
  return ds.listings
    .filter((l) => {
      const deal = dealById.get(l.deal_id);
      return deal && deal.status !== "sold" && deal.status !== "dead";
    })
    .map((l) => {
      const prop = l.property_id ? propById.get(l.property_id) : undefined;
      const dom = l.list_date ? -(daysFromToday(l.list_date, now) ?? 0) : null;
      const reductionFlag = dom !== null && dom > DOM_MEDIAN && l.showing_count_7d === 0;
      return {
        id: l.id,
        address: propertyLabel(prop),
        listPrice: l.list_price,
        currentPrice: l.current_price,
        dom,
        showings7d: l.showing_count_7d,
        unreadFeedback: l.unread_feedback_count,
        reductionFlag,
      };
    })
    .sort((a, b) => (b.dom ?? 0) - (a.dom ?? 0));
}

// ---------------------------------------------------------------------------
// Panel 7: NUMBERS STRIP
// ---------------------------------------------------------------------------
export interface NumbersStrip {
  underContract: number;
  pipelineVolume: number;
  closingsThisMonth: number;
  closedYtd: number;
  newLeads7d: number;
  contentPublished30d: number;
}

const UNDER_CONTRACT_STATUSES = new Set([
  "under_contract",
  "inspection",
  "appraisal",
  "financing",
  "clear_to_close",
  "closing",
]);

export function buildNumbers(ds: Dataset, now = new Date()): NumbersStrip {
  const today = todayCentral(now);
  const monthPrefix = today.slice(0, 7);
  const yearPrefix = today.slice(0, 4);

  const underContractDeals = ds.deals.filter((d) => UNDER_CONTRACT_STATUSES.has(d.status));
  const pipelineVolume = underContractDeals.reduce((s, d) => s + (d.sale_price ?? 0), 0);

  const sold = ds.deals.filter((d) => d.status === "sold");
  const closingsThisMonth = sold.filter((d) => (d.closing_date ?? "").startsWith(monthPrefix)).length;
  const closedYtd = sold
    .filter((d) => (d.closing_date ?? "").startsWith(yearPrefix))
    .reduce((s, d) => s + (d.gross_commission ?? 0), 0);

  const newLeads7d = ds.contacts.filter((c) => {
    const hrs = hoursSince(c.fub_created_at, now);
    return hrs !== null && hrs <= 24 * 7;
  }).length;

  const contentPublished30d = ds.content.filter((c) => {
    if (c.status !== "published" || !c.target_publish_date) return false;
    const d = daysFromToday(c.target_publish_date, now);
    return d !== null && d >= -30 && d <= 0;
  }).length;

  return {
    underContract: underContractDeals.length,
    pipelineVolume,
    closingsThisMonth,
    closedYtd,
    newLeads7d,
    contentPublished30d,
  };
}

// One call that assembles everything the dashboard needs.
export async function getDashboard(now = new Date()) {
  const ds = await loadDataset();
  return {
    today: buildToday(ds, now),
    whoNeedsMe: buildWhoNeedsMe(ds, now),
    activeDeals: buildActiveDeals(ds, now),
    leadQueue: buildLeadQueue(ds, now),
    contentEngine: buildContentEngine(ds, now),
    listingPulse: buildListingPulse(ds, now),
    numbers: buildNumbers(ds, now),
  };
}

export type Dashboard = Awaited<ReturnType<typeof getDashboard>>;

// ---------------------------------------------------------------------------
// Deal detail (PRD §4.3 / §6). Full timeline, tasks, key dates, contact.
// ---------------------------------------------------------------------------
export interface DealDetail {
  deal: Deal;
  contact: Contact | undefined;
  property: Property | undefined;
  tasks: Task[];
  appointments: Appointment[];
  listing: Listing | undefined;
  health: "green" | "amber" | "red";
  nextDeadline: { type: string | null; date: string | null; days: number | null };
  milestoneIndex: number;
}

export async function getDealDetail(
  id: string,
  now = new Date(),
): Promise<DealDetail | null> {
  const ds = await loadDataset();
  const deal = ds.deals.find((d) => d.id === id);
  if (!deal) return null;
  const contactById = index(ds.contacts);
  const propById = index(ds.properties);
  const tasks = ds.tasks
    .filter((t) => t.deal_id === id)
    .sort((a, b) => (a.due_date ?? "9999").localeCompare(b.due_date ?? "9999"));
  return {
    deal,
    contact: contactById.get(deal.contact_id),
    property: deal.property_id ? propById.get(deal.property_id) : undefined,
    tasks,
    appointments: ds.appointments.filter((a) => a.deal_id === id),
    listing: ds.listings.find((l) => l.deal_id === id),
    health: computeDealHealth(deal, ds.tasks, now),
    nextDeadline: nextDeadline(deal, now),
    milestoneIndex: milestoneIndex(deal.status),
  };
}
