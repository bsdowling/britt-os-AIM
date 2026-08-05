// Task & Deadline Engine (PRD §5). Pure functions so they can be unit-tested
// and reused by both the API routes and the cron jobs.

import type { Deal, Task, TaskAnchor } from "./types";
import { addDays } from "./date";

// deal field that backs each anchor type
const ANCHOR_FIELD: Record<Exclude<TaskAnchor, "manual">, keyof Deal> = {
  contract: "contract_date",
  inspection: "inspection_deadline",
  appraisal: "appraisal_deadline",
  financing: "financing_deadline",
  closing: "closing_date",
  list_date: "contract_date", // list_date lives on listings; deals fall back to contract
};

// due_date = deal[anchor] + offset. Manual/unknown anchor => null (absolute date wins).
export function computeDueDate(
  deal: Deal,
  anchor: TaskAnchor | null,
  offset: number | null,
): string | null {
  if (!anchor || anchor === "manual") return null;
  const field = ANCHOR_FIELD[anchor];
  const base = field ? (deal[field] as string | null) : null;
  if (!base) return null;
  return addDays(base, offset ?? 0);
}

export interface TemplateItem {
  id: string;
  title: string;
  description?: string | null;
  anchor_type: TaskAnchor;
  offset_days: number;
  priority: "low" | "normal" | "high";
  default_pinned: boolean;
}

export interface GeneratedTask {
  deal_id: string;
  title: string;
  description: string | null;
  anchor_type: TaskAnchor;
  anchor_offset_days: number;
  due_date: string | null;
  priority: "low" | "normal" | "high";
  is_pinned: boolean;
  template_item_id: string;
  status: "open";
}

// Template firing (PRD §5.2). Skips items already present on the deal (dedupe by
// template_item_id) so re-firing never duplicates.
export function generateTasksFromTemplate(
  deal: Deal,
  items: TemplateItem[],
  existing: Task[],
): GeneratedTask[] {
  const already = new Set(
    existing.filter((t) => t.template_item_id != null).map((t) => t.template_item_id as string),
  );
  const out: GeneratedTask[] = [];
  for (const item of items) {
    if (already.has(item.id)) continue;
    out.push({
      deal_id: deal.id,
      title: item.title,
      description: item.description ?? null,
      anchor_type: item.anchor_type,
      anchor_offset_days: item.offset_days,
      due_date: computeDueDate(deal, item.anchor_type, item.offset_days),
      priority: item.priority,
      is_pinned: item.default_pinned,
      template_item_id: item.id,
      status: "open",
    });
  }
  return out;
}

export interface CascadeChange {
  task_id: string;
  title: string;
  old_due: string | null;
  new_due: string | null;
}

export interface CascadeResult {
  changes: CascadeChange[];
  heldPinned: number;
  summary: string;
}

// The cascade (PRD §5.3). Given a deal whose anchors have already been updated,
// recompute due dates for every open, non-pinned, non-manual task anchored to a
// changed anchor. Never touches completed or pinned tasks. Returns a preview —
// the caller decides whether to apply and how to log it.
export function computeCascade(
  updatedDeal: Deal,
  tasks: Task[],
  changedAnchors: Set<Exclude<TaskAnchor, "manual">>,
): CascadeResult {
  const changes: CascadeChange[] = [];
  let heldPinned = 0;

  for (const task of tasks) {
    if (task.deal_id !== updatedDeal.id) continue;
    if (task.status !== "open") continue; // never touch completed/skipped
    if (!task.anchor_type || task.anchor_type === "manual") continue;
    if (!changedAnchors.has(task.anchor_type as Exclude<TaskAnchor, "manual">)) continue;

    if (task.is_pinned) {
      heldPinned += 1;
      continue; // pinned tasks hold their date
    }

    const newDue = computeDueDate(updatedDeal, task.anchor_type, task.anchor_offset_days);
    if (newDue !== task.due_date) {
      changes.push({
        task_id: task.id,
        title: task.title,
        old_due: task.due_date,
        new_due: newDue,
      });
    }
  }

  return {
    changes,
    heldPinned,
    summary: buildSummary(changes.length, heldPinned),
  };
}

function buildSummary(moved: number, held: number): string {
  const parts = [`${moved} task${moved === 1 ? "" : "s"} shifted`];
  if (held > 0) parts.push(`${held} pinned task${held === 1 ? "" : "s"} held`);
  return parts.join(", ");
}

// When closing_date changes, dependent anchors that were set relative to it and
// not independently confirmed also shift. Never auto-shift inspection/appraisal
// (contract-fixed). Returns the set of anchors to cascade over.
export function anchorsToCascade(
  changed: Exclude<TaskAnchor, "manual">,
): Set<Exclude<TaskAnchor, "manual">> {
  const set = new Set<Exclude<TaskAnchor, "manual">>([changed]);
  if (changed === "closing") {
    set.add("financing");
  }
  return set;
}
