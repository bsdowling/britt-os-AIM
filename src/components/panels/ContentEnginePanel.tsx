"use client";

import { useState } from "react";
import type { ContentEngine } from "@/lib/data";
import type { ContentStatus } from "@/lib/types";
import { Panel } from "@/components/ui/Panel";
import { Chip } from "@/components/ui/Chip";
import { cn } from "@/lib/cn";

const PILLAR_LABELS: Record<string, string> = {
  area_guides: "Area Guides",
  pros_cons: "Pros & Cons",
  gut_check: "Gut Check",
  cost_of_living: "Cost of Living",
  livestream: "Livestream",
};

const STATUSES: ContentStatus[] = [
  "idea",
  "scripted",
  "filmed",
  "editing",
  "scheduled",
  "published",
];

// Panel 5 (PRD §4.5). Weekly slots on top, idea inbox below, kanban status filter.
export function ContentEnginePanel({ data }: { data: ContentEngine }) {
  const [filter, setFilter] = useState<ContentStatus | "all">("all");

  const ideas =
    filter === "all" ? data.ideas : data.ideas.filter((i) => i.status === filter);

  return (
    <Panel title="Content Engine" className="h-full" bodyClassName="flex flex-col gap-4">
      {/* This week's slots */}
      <div>
        <div className="text-[11px] uppercase tracking-wide text-slate/60 mb-2">
          This week
        </div>
        <div className="flex flex-col gap-1.5">
          {data.slots.map((slot, i) => (
            <div
              key={i}
              className={cn(
                "flex items-center gap-2 rounded-btn border px-3 py-2",
                slot.filled
                  ? "border-mist bg-white"
                  : slot.urgency === "red"
                    ? "border-alert/30 bg-alert/8"
                    : "border-sand/50 bg-sand/15",
              )}
            >
              <span className="text-xs font-medium text-slate w-28 shrink-0">
                {slot.label}
              </span>
              {slot.filled ? (
                <>
                  <span className="text-sm text-ink truncate flex-1">{slot.filled.title}</span>
                  <Chip tone="neutral" className="shrink-0 capitalize">
                    {slot.filled.status}
                  </Chip>
                </>
              ) : (
                <span className="text-xs italic text-slate/60 flex-1">Empty</span>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Idea inbox */}
      <div className="flex-1 min-h-0 flex flex-col">
        <div className="flex items-center justify-between mb-2">
          <div className="text-[11px] uppercase tracking-wide text-slate/60">Idea inbox</div>
        </div>
        <div className="flex flex-wrap gap-1 mb-2">
          <FilterBtn active={filter === "all"} onClick={() => setFilter("all")}>
            all
          </FilterBtn>
          {STATUSES.map((s) => (
            <FilterBtn key={s} active={filter === s} onClick={() => setFilter(s)}>
              {s}
            </FilterBtn>
          ))}
        </div>
        <ul className="flex flex-col overflow-y-auto">
          {ideas.length === 0 ? (
            <li className="text-xs text-slate/50 py-2">No ideas in this bucket.</li>
          ) : (
            ideas.map((i) => (
              <li
                key={i.id}
                className="flex items-center gap-2 py-1.5 border-b border-mist/60 last:border-0"
              >
                <div className="min-w-0 flex-1">
                  <div className="text-sm text-ink truncate">{i.title}</div>
                  {i.hook && <div className="text-xs text-slate/60 truncate">{i.hook}</div>}
                </div>
                {i.pillar && (
                  <Chip tone="sand" className="shrink-0">
                    {PILLAR_LABELS[i.pillar]}
                  </Chip>
                )}
              </li>
            ))
          )}
        </ul>
      </div>
    </Panel>
  );
}

function FilterBtn({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "rounded-chip px-2 py-0.5 text-[11px] font-medium capitalize transition-colors",
        active ? "bg-ink text-paper" : "bg-mist text-slate hover:bg-mist/70",
      )}
    >
      {children}
    </button>
  );
}
