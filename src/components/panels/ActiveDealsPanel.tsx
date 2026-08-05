import Link from "next/link";
import type { DealCard } from "@/lib/data";
import { Panel, EmptyState } from "@/components/ui/Panel";
import { MilestoneBar } from "@/components/ui/MilestoneBar";
import { Chip } from "@/components/ui/Chip";
import { countdownLabel } from "@/lib/date";
import { cn } from "@/lib/cn";

// Panel 3 (PRD §4.3). Horizontal rail, sorted by soonest deadline, colored left
// border keyed to deal health.
export function ActiveDealsPanel({ deals }: { deals: DealCard[] }) {
  return (
    <Panel title="Active Deals" bodyClassName="pb-4">
      {deals.length === 0 ? (
        <EmptyState>No active deals. Convert a lead to get started.</EmptyState>
      ) : (
        <div className="rail flex gap-4 overflow-x-auto pb-2 -mx-1 px-1">
          {deals.map((d) => (
            <DealCardView key={d.id} deal={d} />
          ))}
        </div>
      )}
    </Panel>
  );
}

const HEALTH_BORDER: Record<string, string> = {
  green: "border-l-sage",
  amber: "border-l-sand",
  red: "border-l-alert",
};

function DealCardView({ deal }: { deal: DealCard }) {
  const overdue = deal.nextDeadlineDays !== null && deal.nextDeadlineDays < 0;
  return (
    <Link
      href={`/deals/${deal.id}`}
      className={cn(
        "shrink-0 w-64 rounded-card border border-mist bg-white p-4 border-l-4 hover:shadow-panel transition-shadow",
        HEALTH_BORDER[deal.health],
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-sm font-semibold text-ink truncate">{deal.clientName}</div>
          <div className="text-xs text-slate/70 truncate">{deal.address}</div>
        </div>
        {deal.openTasks > 0 && (
          <Chip tone="neutral" className="tnum shrink-0">
            {deal.openTasks}
          </Chip>
        )}
      </div>

      <div className="my-3">
        <MilestoneBar currentIndex={deal.milestoneIndex} />
      </div>

      <div className="flex items-end justify-between">
        <div>
          <div className="text-[11px] uppercase tracking-wide text-slate/60">
            {deal.nextDeadlineType ?? "Next"}
          </div>
          <div
            className={cn(
              "tnum text-lg font-semibold leading-tight",
              overdue ? "text-alert" : "text-ink",
            )}
          >
            {countdownLabel(deal.nextDeadlineDays)}
          </div>
        </div>
      </div>
    </Link>
  );
}
