import Link from "next/link";
import { notFound } from "next/navigation";
import { getDealDetail, contactName, propertyLabel } from "@/lib/data";
import { STAGE_LABELS } from "@/lib/types";
import { friendlyDate, countdownLabel, daysFromToday } from "@/lib/date";
import { money } from "@/lib/cn";
import { env } from "@/lib/env";
import { Wordmark } from "@/components/ui/Wordmark";
import { MilestoneBar } from "@/components/ui/MilestoneBar";
import { Panel } from "@/components/ui/Panel";
import { Chip } from "@/components/ui/Chip";

export const dynamic = "force-dynamic";

const HEALTH_TONE: Record<string, "sage" | "sand" | "alert"> = {
  green: "sage",
  amber: "sand",
  red: "alert",
};

export default async function DealDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const detail = await getDealDetail(id);
  if (!detail) notFound();

  const { deal, contact, property, tasks, listing } = detail;
  const email = contact?.emails?.[0]?.value;
  const phone = contact?.phones?.[0]?.value;

  const keyDates: { label: string; date: string | null }[] = [
    { label: "Contract", date: deal.contract_date },
    { label: "Inspection", date: deal.inspection_deadline },
    { label: "Appraisal", date: deal.appraisal_deadline },
    { label: "Financing", date: deal.financing_deadline },
    { label: "Closing", date: deal.closing_date },
  ];

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-40 bg-paper/90 backdrop-blur border-b border-mist">
        <div className="mx-auto max-w-[1100px] px-4 sm:px-6 h-14 flex items-center gap-4">
          <Link href="/" className="text-slate hover:text-ink text-sm">
            ← Dashboard
          </Link>
          <Wordmark className="text-base ml-auto" />
        </div>
      </header>

      <main className="mx-auto max-w-[1100px] px-4 sm:px-6 py-6 flex flex-col gap-4">
        {/* Title + health */}
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="font-heading font-bold text-2xl text-ink">
              {contactName(contact)}
            </h1>
            <p className="text-slate">{propertyLabel(property)}</p>
          </div>
          <div className="flex items-center gap-2">
            <Chip tone={HEALTH_TONE[detail.health]}>{detail.health}</Chip>
            <Chip tone="ink" className="capitalize">
              {deal.side}
            </Chip>
          </div>
        </div>

        {/* Milestone */}
        <Panel>
          <div className="py-2">
            <MilestoneBar currentIndex={detail.milestoneIndex} size="lg" showLabels />
          </div>
          <div className="mt-3 text-sm text-slate">
            Status: <span className="font-medium text-ink">{STAGE_LABELS[deal.status]}</span>
            {detail.nextDeadline.type && (
              <>
                {" · "}Next: {STAGE_LABELS[detail.nextDeadline.type] ?? detail.nextDeadline.type}{" "}
                <span className="tnum">({countdownLabel(detail.nextDeadline.days)})</span>
              </>
            )}
          </div>
        </Panel>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {/* Tasks */}
          <div className="lg:col-span-2">
            <Panel title={`Tasks (${tasks.filter((t) => t.status === "open").length} open)`}>
              {tasks.length === 0 ? (
                <p className="text-sm text-slate/60 py-2">No tasks yet.</p>
              ) : (
                <ul className="flex flex-col">
                  {tasks.map((t) => {
                    const d = daysFromToday(t.due_date);
                    const overdue = t.status === "open" && d !== null && d < 0;
                    return (
                      <li
                        key={t.id}
                        className="flex items-center gap-3 py-2 border-b border-mist/60 last:border-0"
                      >
                        <span
                          className={`h-4 w-4 shrink-0 rounded-[4px] border ${
                            t.status === "done"
                              ? "bg-sage border-sage"
                              : "border-slate/40"
                          }`}
                        />
                        <div className="min-w-0 flex-1">
                          <div
                            className={`text-sm truncate ${
                              t.status === "done" ? "line-through text-slate/50" : "text-ink"
                            }`}
                          >
                            {t.title}
                          </div>
                          <div className="text-xs text-slate/60 flex items-center gap-2">
                            <span className={overdue ? "text-alert" : ""}>
                              {t.due_date ? friendlyDate(t.due_date) : "No date"}
                            </span>
                            {t.is_pinned && <Chip tone="sand">pinned</Chip>}
                            {t.is_client_visible && <Chip tone="neutral">client</Chip>}
                          </div>
                        </div>
                        {t.priority === "high" && <Chip tone="alert">high</Chip>}
                      </li>
                    );
                  })}
                </ul>
              )}
            </Panel>
          </div>

          {/* Sidebar: key dates, money, contact, portal */}
          <div className="flex flex-col gap-4">
            <Panel title="Key dates">
              <ul className="flex flex-col gap-1.5">
                {keyDates.map((k) => (
                  <li key={k.label} className="flex items-center justify-between text-sm">
                    <span className="text-slate">{k.label}</span>
                    <span className="tnum text-ink">{friendlyDate(k.date)}</span>
                  </li>
                ))}
              </ul>
            </Panel>

            <Panel title="Deal">
              <ul className="flex flex-col gap-1.5 text-sm">
                <li className="flex justify-between">
                  <span className="text-slate">Sale price</span>
                  <span className="tnum text-ink">{money(deal.sale_price)}</span>
                </li>
                <li className="flex justify-between">
                  <span className="text-slate">Commission</span>
                  <span className="tnum text-ink">{money(deal.gross_commission)}</span>
                </li>
                {deal.financing_type && (
                  <li className="flex justify-between">
                    <span className="text-slate">Financing</span>
                    <span className="text-ink uppercase">{deal.financing_type}</span>
                  </li>
                )}
                {listing && (
                  <li className="flex justify-between">
                    <span className="text-slate">Days on market</span>
                    <span className="tnum text-ink">
                      {listing.list_date ? -(daysFromToday(listing.list_date) ?? 0) : "—"}
                    </span>
                  </li>
                )}
              </ul>
            </Panel>

            <Panel title="Contact">
              <div className="text-sm flex flex-col gap-1">
                <div className="text-ink font-medium">{contactName(contact)}</div>
                {phone && <a href={`tel:${phone}`} className="text-sage">{phone}</a>}
                {email && (
                  <a href={`mailto:${email}`} className="text-sage truncate">
                    {email}
                  </a>
                )}
                {contact?.stage && <Chip tone="neutral" className="w-fit mt-1">{contact.stage}</Chip>}
              </div>
            </Panel>

            <Panel title="Client portal">
              <p className="text-xs text-slate/70 mb-2">
                Share a login-free tracker. The client sees stages and key dates only — never
                commission or notes.
              </p>
              <a
                href={`${env.appUrl}/track/demo-${deal.id}`}
                className="text-xs text-sage break-all"
              >
                {env.appUrl}/track/demo-{deal.id}
              </a>
            </Panel>
          </div>
        </div>
      </main>
    </div>
  );
}
