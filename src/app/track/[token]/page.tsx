import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getDealDetail, contactName, propertyLabel } from "@/lib/data";
import { MILESTONE_STAGES, STAGE_LABELS, type MilestoneStage } from "@/lib/types";
import { STAGE_CLIENT_COPY } from "@/lib/stage-copy";
import { friendlyDate, countdownLabel, daysFromToday } from "@/lib/date";
import { MilestoneBar } from "@/components/ui/MilestoneBar";
import { Wordmark } from "@/components/ui/Wordmark";

// Client portal (PRD §6.2). Unguessable token URL is the security model. Public,
// noindex. Never shows commission, notes, other clients, or internal tasks.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};
export const dynamic = "force-dynamic";

// Demo tokens are "demo-<dealId>". In production a token maps to a deal via a
// portal_tokens lookup; kept simple here.
function dealIdFromToken(token: string): string | null {
  if (token.startsWith("demo-")) return token.slice(5);
  return null;
}

export default async function PortalPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const dealId = dealIdFromToken(token);
  if (!dealId) notFound();
  const detail = await getDealDetail(dealId);
  if (!detail) notFound();

  const { deal, contact, property } = detail;
  const currentIndex = detail.milestoneIndex >= 0 ? detail.milestoneIndex : 0;
  const currentStage = MILESTONE_STAGES[currentIndex] as MilestoneStage;

  // Only tasks explicitly marked client-visible and still open.
  const clientTasks = detail.tasks.filter((t) => t.is_client_visible && t.status === "open");

  const keyDates: { label: string; date: string | null }[] = [
    { label: "Inspection", date: deal.inspection_deadline },
    { label: "Appraisal", date: deal.appraisal_deadline },
    { label: "Financing", date: deal.financing_deadline },
    { label: "Closing", date: deal.closing_date },
  ].filter((k) => k.date);

  return (
    <div className="min-h-screen bg-paper">
      <div className="mx-auto max-w-2xl px-5 py-8">
        <div className="flex justify-center mb-6">
          <Wordmark className="text-lg" />
        </div>

        <h1 className="font-heading font-bold text-2xl text-ink text-center">
          {propertyLabel(property)}
        </h1>
        <p className="text-center text-slate mt-1">
          Hi {contact?.first_name ?? "there"} — here&apos;s where things stand.
        </p>

        {/* Tracker */}
        <div className="mt-8 rounded-card bg-white border border-mist p-6 shadow-panel">
          <MilestoneBar currentIndex={currentIndex} size="lg" showLabels />
        </div>

        {/* Where things stand */}
        <section className="mt-6">
          <h2 className="font-heading font-semibold text-ink text-sm uppercase tracking-wide mb-2">
            Where things stand
          </h2>
          <div className="rounded-card bg-white border border-mist p-5">
            <div className="text-sm font-semibold text-ink mb-1">
              {STAGE_LABELS[currentStage]}
            </div>
            <p className="text-slate leading-relaxed">{STAGE_CLIENT_COPY[currentStage]}</p>
          </div>
        </section>

        {/* What I need from you */}
        <section className="mt-6">
          <h2 className="font-heading font-semibold text-ink text-sm uppercase tracking-wide mb-2">
            What I need from you
          </h2>
          <div className="rounded-card bg-white border border-mist p-5">
            {clientTasks.length === 0 ? (
              <p className="text-slate">Nothing right now, I&apos;ll reach out.</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {clientTasks.map((t) => (
                  <li key={t.id} className="flex items-start gap-2 text-slate">
                    <span className="mt-1.5 h-1.5 w-1.5 rounded-full bg-sand shrink-0" />
                    <span>
                      {t.title}
                      {t.due_date && (
                        <span className="text-slate/60"> · by {friendlyDate(t.due_date)}</span>
                      )}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>

        {/* Key dates */}
        {keyDates.length > 0 && (
          <section className="mt-6">
            <h2 className="font-heading font-semibold text-ink text-sm uppercase tracking-wide mb-2">
              Key dates
            </h2>
            <div className="rounded-card bg-white border border-mist p-5 grid grid-cols-2 gap-4">
              {keyDates.map((k) => {
                const days = daysFromToday(k.date);
                return (
                  <div key={k.label}>
                    <div className="text-xs uppercase tracking-wide text-slate/60">{k.label}</div>
                    <div className="text-ink font-medium">{friendlyDate(k.date)}</div>
                    {days !== null && days >= 0 && (
                      <div className="text-xs text-sage">{countdownLabel(days)}</div>
                    )}
                  </div>
                );
              })}
            </div>
          </section>
        )}

        {/* Contact block */}
        <section className="mt-6">
          <div className="rounded-card bg-ink text-paper p-5 text-center">
            <div className="font-heading font-semibold">Britt Dowling</div>
            <div className="text-paper/70 text-sm">Montgomery, Alabama</div>
            <p className="text-paper/80 text-sm mt-2">
              Have a question about anything above? Just call or text — anytime.
            </p>
            <div className="mt-3 flex justify-center gap-3 text-sm">
              <a href="tel:334-555-0100" className="rounded-btn bg-sage px-4 py-1.5 font-medium">
                Call
              </a>
              <a href="sms:334-555-0100" className="rounded-btn bg-white/10 px-4 py-1.5 font-medium">
                Text
              </a>
            </div>
          </div>
        </section>

        <p className="text-center text-xs text-slate/40 mt-8">
          This page is private to you.
        </p>
      </div>
    </div>
  );
}
