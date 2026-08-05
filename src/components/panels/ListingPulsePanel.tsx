import type { ListingRow } from "@/lib/data";
import { Panel, EmptyState } from "@/components/ui/Panel";
import { money } from "@/lib/cn";

// Panel 6 (PRD §4.6). Active listings, DOM, 7-day showings, unread feedback,
// price-reduction flag.
export function ListingPulsePanel({ listings }: { listings: ListingRow[] }) {
  return (
    <Panel title="Listing Pulse" bodyClassName="overflow-x-auto">
      {listings.length === 0 ? (
        <EmptyState>No active listings right now.</EmptyState>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-[11px] uppercase tracking-wide text-slate/60 text-left">
              <th className="font-medium pb-2 pr-3">Address</th>
              <th className="font-medium pb-2 pr-3">Price</th>
              <th className="font-medium pb-2 pr-3 tnum">DOM</th>
              <th className="font-medium pb-2 pr-3 tnum">7d</th>
              <th className="font-medium pb-2 pr-3 tnum">Feedback</th>
              <th className="font-medium pb-2"></th>
            </tr>
          </thead>
          <tbody>
            {listings.map((l) => (
              <tr key={l.id} className="border-t border-mist/60">
                <td className="py-2 pr-3 text-ink max-w-[220px] truncate">{l.address}</td>
                <td className="py-2 pr-3 tnum">
                  {money(l.currentPrice, true)}
                  {l.currentPrice !== l.listPrice && (
                    <span className="text-xs text-slate/50 line-through ml-1">
                      {money(l.listPrice, true)}
                    </span>
                  )}
                </td>
                <td className="py-2 pr-3 tnum">{l.dom ?? "—"}</td>
                <td className="py-2 pr-3 tnum">{l.showings7d}</td>
                <td className="py-2 pr-3 tnum">
                  {l.unreadFeedback > 0 ? (
                    <span className="inline-flex items-center gap-1 text-sand">
                      <span className="h-1.5 w-1.5 rounded-full bg-sand" />
                      {l.unreadFeedback}
                    </span>
                  ) : (
                    <span className="text-slate/40">0</span>
                  )}
                </td>
                <td className="py-2">
                  {l.reductionFlag && (
                    <span
                      title="High DOM, zero showings in 7 days"
                      className="inline-flex items-center gap-1 rounded-chip bg-alert/12 px-2 py-0.5 text-xs font-medium text-alert"
                    >
                      ⚑ Reduce
                    </span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Panel>
  );
}
