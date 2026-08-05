// Deal-derived values (PRD §3). Deal health is what makes a card jump off the screen.

import type { Deal, DealHealth, Task, TaskAnchor } from "./types";
import { daysFromToday } from "./date";

const ANCHOR_FIELDS: Record<Exclude<TaskAnchor, "manual" | "list_date">, keyof Deal> = {
  contract: "contract_date",
  inspection: "inspection_deadline",
  appraisal: "appraisal_deadline",
  financing: "financing_deadline",
  closing: "closing_date",
};

export interface NextDeadline {
  type: string | null;
  date: string | null;
  days: number | null;
}

// Soonest future anchor date on a deal.
export function nextDeadline(deal: Deal, now: Date = new Date()): NextDeadline {
  const candidates: { type: string; date: string; days: number }[] = [];
  for (const [type, field] of Object.entries(ANCHOR_FIELDS)) {
    const date = deal[field] as string | null;
    const days = daysFromToday(date, now);
    if (date && days !== null && days >= 0) candidates.push({ type, date, days });
  }
  candidates.sort((a, b) => a.days - b.days);
  const first = candidates[0];
  return first ? first : { type: null, date: null, days: null };
}

export function isOverdue(task: Task, today: string): boolean {
  return task.status === "open" && !!task.due_date && task.due_date < today;
}

// deal_health enum (PRD §3):
//  green  — no overdue tasks, next deadline more than 5 days out
//  amber  — next deadline inside 5 days, or 1–2 overdue tasks
//  red    — next deadline inside 48h with open tasks, or 3+ overdue tasks
export function computeDealHealth(
  deal: Deal,
  tasks: Task[],
  now: Date = new Date(),
): DealHealth {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Chicago",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);

  const dealTasks = tasks.filter((t) => t.deal_id === deal.id);
  const overdue = dealTasks.filter((t) => isOverdue(t, today)).length;
  const openCount = dealTasks.filter((t) => t.status === "open").length;
  const nd = nextDeadline(deal, now);

  if (overdue >= 3) return "red";
  if (nd.days !== null && nd.days <= 2 && openCount > 0) return "red";
  if (overdue >= 1 || (nd.days !== null && nd.days <= 5)) return "amber";
  return "green";
}

export function openTaskCount(dealId: string, tasks: Task[]): number {
  return tasks.filter((t) => t.deal_id === dealId && t.status === "open").length;
}

// Which milestone stage index a status maps to (for the segmented bar).
const STATUS_TO_MILESTONE_INDEX: Record<string, number> = {
  under_contract: 0,
  inspection: 1,
  appraisal: 2,
  financing: 3,
  clear_to_close: 4,
  closing: 5,
  sold: 6,
};

export function milestoneIndex(status: string): number {
  return STATUS_TO_MILESTONE_INDEX[status] ?? -1;
}
