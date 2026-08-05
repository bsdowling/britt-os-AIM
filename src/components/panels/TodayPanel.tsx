"use client";

import { useState } from "react";
import type { TodayPanel as TodayData, TodayRow } from "@/lib/data";
import { Panel, EmptyState } from "@/components/ui/Panel";
import { Chip } from "@/components/ui/Chip";
import { cn } from "@/lib/cn";

export function TodayPanel({ data }: { data: TodayData }) {
  const [done, setDone] = useState<Set<string>>(new Set());

  async function complete(id: string) {
    setDone((prev) => new Set(prev).add(id));
    // Persists when Supabase is configured; a no-op in demo mode.
    try {
      await fetch(`/api/tasks/${id}/complete`, { method: "POST" });
    } catch {
      /* optimistic — leave it struck through regardless */
    }
  }

  const visible = data.rows.filter((r) => !done.has(r.id));
  const overdue = visible.filter((r) => r.kind === "task" && r.overdue);
  const rest = visible.filter((r) => !(r.kind === "task" && r.overdue));

  return (
    <Panel title="Today" className="h-full" bodyClassName="overflow-y-auto">
      {visible.length === 0 ? (
        <EmptyState
          action={
            <a
              href="#content-engine"
              className="rounded-btn bg-sage px-3 py-1.5 text-xs font-medium text-white"
            >
              Go make content
            </a>
          }
        >
          Nothing due today. Good day to film.
        </EmptyState>
      ) : (
        <div className="flex flex-col gap-1">
          {overdue.length > 0 && (
            <div className="rounded-btn bg-alert/8 border border-alert/20 px-3 py-2 mb-1">
              <div className="text-xs font-semibold text-alert mb-1">
                {overdue.length} overdue
              </div>
              <div className="flex flex-col">
                {overdue.map((r) => (
                  <Row key={r.id} row={r} onComplete={complete} />
                ))}
              </div>
            </div>
          )}
          {rest.map((r) => (
            <Row key={r.id} row={r} onComplete={complete} />
          ))}
        </div>
      )}
    </Panel>
  );
}

function Row({
  row,
  onComplete,
}: {
  row: TodayRow;
  onComplete: (id: string) => void;
}) {
  const isTask = row.kind === "task";
  return (
    <div className="group flex items-center gap-3 py-1.5 border-b border-mist/60 last:border-0">
      {isTask ? (
        <button
          aria-label="Complete task"
          onClick={() => onComplete(row.id)}
          className="h-4 w-4 shrink-0 rounded-[4px] border border-slate/40 hover:border-sage hover:bg-sage/20 transition-colors"
        />
      ) : (
        <span className="h-4 w-4 shrink-0 rounded-full bg-ink/80" />
      )}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          {row.timeLabel && (
            <span className="tnum text-xs font-medium text-ink shrink-0">{row.timeLabel}</span>
          )}
          <span
            className={cn(
              "text-sm truncate",
              row.overdue ? "text-alert" : "text-slate",
            )}
          >
            {row.title}
          </span>
        </div>
      </div>
      {row.chip && (
        <Chip tone={row.chip.kind === "deal" ? "sand" : "neutral"} className="shrink-0 max-w-[40%] truncate">
          {row.chip.label}
        </Chip>
      )}
    </div>
  );
}
