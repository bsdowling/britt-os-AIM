// Lead score (PRD §4.4). 0..100, recalculated nightly and on relevant webhooks.
// The reason chip matters more than the number, so we return both.

import type { Contact } from "./types";
import { hoursSince } from "./date";

export interface FubEngagement {
  // Count of FUB events (notes/texts/emails) in the last 14 days.
  eventsLast14d: number;
}

const STAGE_WEIGHT: Record<string, number> = {
  Hot: 25,
  "Active Client": 22,
  "New Lead": 15,
  Lead: 15,
  Nurture: 12,
  "Past Client": 10,
};

// [CUSTOMIZE once you have closing data by source — PRD §4.4]
const SOURCE_QUALITY: Record<string, number> = {
  Referral: 15,
  Sphere: 15,
  YouTube: 13,
  "Open House": 10,
  Ylopo: 7,
  Google: 7,
  Meta: 7,
};

export interface LeadScoreResult {
  score: number;
  reason: string; // plain-words explanation for the reason chip
}

export function computeLeadScore(
  contact: Pick<
    Contact,
    "stage" | "source" | "last_inbound_at" | "last_outbound_at" | "needs_response"
  >,
  engagement: FubEngagement = { eventsLast14d: 0 },
  now: Date = new Date(),
): LeadScoreResult {
  let score = 0;

  // Inbound recency — max 30
  const inboundHrs = hoursSince(contact.last_inbound_at, now);
  if (inboundHrs !== null) {
    if (inboundHrs < 2) score += 30;
    else if (inboundHrs < 24) score += 24;
    else if (inboundHrs < 72) score += 15;
    else if (inboundHrs < 168) score += 8;
  }

  // Stage weight — max 25
  score += (contact.stage && STAGE_WEIGHT[contact.stage]) || 0;

  // Engagement volume — max 20, 5+ events = 20, scaled below
  const ev = Math.min(engagement.eventsLast14d, 5);
  score += Math.round((ev / 5) * 20);

  // Source quality — max 15
  score += (contact.source && SOURCE_QUALITY[contact.source]) || 0;

  // Unanswered penalty reversal — +10
  if (contact.needs_response) score += 10;

  // Staleness decay — minus 1/week, capped at 15
  const lastTouch = mostRecent(contact.last_inbound_at, contact.last_outbound_at);
  const touchHrs = hoursSince(lastTouch, now);
  if (touchHrs !== null) {
    const weeks = Math.floor(touchHrs / 168);
    score -= Math.min(weeks, 15);
  }

  score = Math.max(0, Math.min(100, score));
  return { score, reason: reasonChip(contact, inboundHrs, engagement, touchHrs) };
}

function mostRecent(a: string | null, b: string | null): string | null {
  if (!a) return b;
  if (!b) return a;
  return Date.parse(a) > Date.parse(b) ? a : b;
}

function reasonChip(
  contact: Pick<Contact, "stage" | "source" | "needs_response">,
  inboundHrs: number | null,
  engagement: FubEngagement,
  touchHrs: number | null,
): string {
  if (contact.needs_response && inboundHrs !== null) {
    if (inboundHrs < 3) return "Replied moments ago, no answer yet";
    if (inboundHrs < 24) return `Replied ${inboundHrs}h ago, waiting on you`;
    return "Waiting on a reply";
  }
  if (engagement.eventsLast14d >= 4) return `Engaged — ${engagement.eventsLast14d} touches in 14 days`;
  if (contact.source === "Referral" || contact.source === "Sphere") {
    if (touchHrs === null) return `${contact.source}, never contacted`;
  }
  if (touchHrs !== null && touchHrs > 168 && contact.stage === "Hot") {
    return "Went quiet, was hot";
  }
  if (contact.source) return `${contact.source} lead`;
  return "Worth a look";
}
