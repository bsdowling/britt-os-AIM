import type { LeadRow } from "@/lib/data";
import { Panel, EmptyState } from "@/components/ui/Panel";
import { Chip } from "@/components/ui/Chip";
import { cn } from "@/lib/cn";

// Panel 4 (PRD §4.4). Top 15 by lead score. The reason chip matters more than
// the number.
export function LeadQueuePanel({ leads }: { leads: LeadRow[] }) {
  return (
    <Panel title="Lead Follow-Up Queue" className="h-full" bodyClassName="overflow-y-auto">
      {leads.length === 0 ? (
        <EmptyState>No leads to rank yet.</EmptyState>
      ) : (
        <ul className="flex flex-col">
          {leads.map((l, i) => (
            <li
              key={l.id}
              className="flex items-center gap-3 py-2 border-b border-mist/60 last:border-0"
            >
              <span className="tnum text-xs text-slate/40 w-4 text-right">{i + 1}</span>
              <ScorePill score={l.score} />
              <div className="min-w-0 flex-1">
                <div className="text-sm text-ink truncate">{l.name}</div>
                <div className="flex items-center gap-2 text-xs text-slate/60">
                  {l.source && <span>{l.source}</span>}
                  {l.daysSinceTouch !== null && (
                    <span className="tnum">· {l.daysSinceTouch}d since touch</span>
                  )}
                </div>
              </div>
              <Chip tone="sage" className="shrink-0 max-w-[45%] truncate">
                {l.reason}
              </Chip>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}

function ScorePill({ score }: { score: number }) {
  const tone =
    score >= 70 ? "bg-sage text-white" : score >= 40 ? "bg-sand text-ink" : "bg-mist text-slate";
  return (
    <span
      className={cn(
        "tnum shrink-0 h-8 w-8 rounded-full grid place-items-center text-sm font-semibold",
        tone,
      )}
    >
      {score}
    </span>
  );
}
