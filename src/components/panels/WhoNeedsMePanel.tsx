"use client";

import { useState } from "react";
import type { WhoNeedsMe, WhoRow } from "@/lib/data";
import { Panel, EmptyState } from "@/components/ui/Panel";
import { cn } from "@/lib/cn";

// Panel 2 (PRD §4.2). Three stacked, collapsible groups. Text + Snooze actions.
export function WhoNeedsMePanel({ data }: { data: WhoNeedsMe }) {
  const [snoozed, setSnoozed] = useState<Set<string>>(new Set());
  const snooze = (id: string) => setSnoozed((p) => new Set(p).add(id));

  const filter = (rows: WhoRow[]) => rows.filter((r) => !snoozed.has(r.id));

  const groups = [
    { key: "wait", title: "Waiting on you", tone: "alert" as const, rows: filter(data.waitingOnYou) },
    { key: "deadline", title: "Deadline inside 72h", tone: "sand" as const, rows: filter(data.deadline72h) },
    { key: "quiet", title: "Gone quiet", tone: "neutral" as const, rows: filter(data.goneQuiet) },
  ];

  const total = groups.reduce((s, g) => s + g.rows.length, 0);

  return (
    <Panel title="Who Needs Me" className="h-full" bodyClassName="overflow-y-auto">
      {total === 0 ? (
        <EmptyState>You&apos;re caught up. Nobody&apos;s waiting.</EmptyState>
      ) : (
        <div className="flex flex-col gap-3">
          {groups.map((g) => (
            <Group key={g.key} title={g.title} tone={g.tone} rows={g.rows} onSnooze={snooze} />
          ))}
        </div>
      )}
    </Panel>
  );
}

function Group({
  title,
  tone,
  rows,
  onSnooze,
}: {
  title: string;
  tone: "alert" | "sand" | "neutral";
  rows: WhoRow[];
  onSnooze: (id: string) => void;
}) {
  const [open, setOpen] = useState(true);
  const dot = { alert: "bg-alert", sand: "bg-sand", neutral: "bg-mist" }[tone];
  return (
    <div>
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center gap-2 text-left"
      >
        <span className={cn("h-2 w-2 rounded-full", dot)} />
        <span className="text-xs font-semibold text-ink uppercase tracking-wide">{title}</span>
        <span className="tnum text-xs text-slate/60">{rows.length}</span>
        <span className="ml-auto text-slate/40 text-xs">{open ? "▾" : "▸"}</span>
      </button>
      {open && rows.length > 0 && (
        <ul className="mt-1.5 flex flex-col">
          {rows.map((r) => (
            <li
              key={r.id}
              className="flex items-center gap-2 py-1.5 border-b border-mist/60 last:border-0"
            >
              <div className="min-w-0 flex-1">
                <div className="text-sm text-ink truncate">{r.name}</div>
                <div className="text-xs text-slate/60">{r.detail}</div>
              </div>
              <div className="flex gap-1 shrink-0">
                <button className="rounded-btn bg-ink px-2 py-1 text-[11px] font-medium text-paper hover:opacity-90">
                  Text
                </button>
                <button
                  onClick={() => onSnooze(r.id)}
                  className="rounded-btn border border-mist px-2 py-1 text-[11px] font-medium text-slate hover:bg-mist"
                >
                  Snooze
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
      {open && rows.length === 0 && (
        <p className="mt-1.5 text-xs text-slate/50">Clear.</p>
      )}
    </div>
  );
}
