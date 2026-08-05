import { getDashboard } from "@/lib/data";
import { longToday } from "@/lib/date";
import { isDemoMode } from "@/lib/env";
import { Wordmark } from "@/components/ui/Wordmark";
import { QuickAdd } from "@/components/QuickAdd";
import { TodayPanel } from "@/components/panels/TodayPanel";
import { WhoNeedsMePanel } from "@/components/panels/WhoNeedsMePanel";
import { ActiveDealsPanel } from "@/components/panels/ActiveDealsPanel";
import { LeadQueuePanel } from "@/components/panels/LeadQueuePanel";
import { ContentEnginePanel } from "@/components/panels/ContentEnginePanel";
import { ListingPulsePanel } from "@/components/panels/ListingPulsePanel";
import { NumbersStrip } from "@/components/panels/NumbersStrip";

// The one screen (PRD §4). Server-rendered so the dashboard renders with data
// already attached; interactive panels hydrate for optimistic updates.
export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const d = await getDashboard();

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="sticky top-0 z-40 bg-paper/90 backdrop-blur border-b border-mist">
        <div className="mx-auto max-w-[1440px] px-4 sm:px-6 h-14 flex items-center justify-between gap-4">
          <Wordmark className="text-lg" />
          <div className="hidden sm:block text-sm font-medium text-slate">{longToday()}</div>
          <QuickAdd />
        </div>
      </header>

      {isDemoMode && (
        <div className="mx-auto max-w-[1440px] px-4 sm:px-6 pt-3">
          <div className="rounded-btn bg-sand/25 border border-sand/50 px-3 py-1.5 text-xs text-ink">
            Demo mode — showing sample data. Set{" "}
            <code className="font-mono">NEXT_PUBLIC_SUPABASE_URL</code> and keys to connect a
            live database.
          </div>
        </div>
      )}

      {/* Grid — PRD §4 layout */}
      <main className="mx-auto max-w-[1440px] px-4 sm:px-6 py-4 grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* Row 1 — fixed height, panels scroll internally to keep one screen */}
        <div className="lg:col-span-7 lg:h-[460px]">
          <TodayPanel data={d.today} />
        </div>
        <div className="lg:col-span-5 lg:h-[460px]">
          <WhoNeedsMePanel data={d.whoNeedsMe} />
        </div>

        {/* Row 2 — full width rail */}
        <div className="lg:col-span-12">
          <ActiveDealsPanel deals={d.activeDeals} />
        </div>

        {/* Row 3 */}
        <div className="lg:col-span-7 lg:h-[560px]">
          <LeadQueuePanel leads={d.leadQueue} />
        </div>
        <div id="content-engine" className="lg:col-span-5 lg:h-[560px]">
          <ContentEnginePanel data={d.contentEngine} />
        </div>

        {/* Row 4 */}
        <div className="lg:col-span-7">
          <ListingPulsePanel listings={d.listingPulse} />
        </div>
        <div className="lg:col-span-5 flex">
          <div className="w-full self-start">
            <NumbersStrip data={d.numbers} />
          </div>
        </div>
      </main>

      <footer className="mx-auto max-w-[1440px] px-4 sm:px-6 py-6 text-xs text-slate/50">
        Britt&apos;s OS · Montgomery, Alabama
      </footer>
    </div>
  );
}
