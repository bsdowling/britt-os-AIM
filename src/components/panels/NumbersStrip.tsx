import type { NumbersStrip as NumbersData } from "@/lib/data";
import { money } from "@/lib/cn";

// Panel 7 (PRD §4.7). Six stats. The content-published stat is deliberately on
// the same line as the money.
export function NumbersStrip({ data }: { data: NumbersData }) {
  const stats: { label: string; value: string; accent?: boolean }[] = [
    { label: "Under contract", value: String(data.underContract) },
    { label: "Pipeline volume", value: money(data.pipelineVolume, true) },
    { label: "Closings this month", value: String(data.closingsThisMonth) },
    { label: "Closed YTD", value: money(data.closedYtd, true) },
    { label: "New leads · 7d", value: String(data.newLeads7d) },
    { label: "Content · 30d", value: String(data.contentPublished30d), accent: true },
  ];
  return (
    <div className="rounded-card bg-ink text-paper shadow-panel grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 divide-y sm:divide-y-0 sm:divide-x divide-white/10">
      {stats.map((s) => (
        <div key={s.label} className="px-panel py-4">
          <div className="text-[11px] uppercase tracking-wide text-paper/60">{s.label}</div>
          <div className={`tnum text-2xl font-semibold mt-1 ${s.accent ? "text-sand" : ""}`}>
            {s.value}
          </div>
        </div>
      ))}
    </div>
  );
}
