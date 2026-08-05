import { cn } from "@/lib/cn";

// Base panel surface (PRD §11: mist/paper separation, near-invisible shadow,
// 24px padding, 8px radius).
export function Panel({
  title,
  action,
  className,
  bodyClassName,
  children,
}: {
  title?: string;
  action?: React.ReactNode;
  className?: string;
  bodyClassName?: string;
  children: React.ReactNode;
}) {
  return (
    <section
      className={cn(
        "rounded-card bg-white shadow-panel border border-mist/70 flex flex-col min-w-0",
        className,
      )}
    >
      {title && (
        <header className="flex items-center justify-between px-panel pt-5 pb-3">
          <h2 className="font-heading font-semibold text-ink text-sm uppercase tracking-wide">
            {title}
          </h2>
          {action}
        </header>
      )}
      <div className={cn("px-panel pb-5 flex-1 min-h-0", bodyClassName)}>{children}</div>
    </section>
  );
}

export function EmptyState({
  children,
  action,
}: {
  children: React.ReactNode;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center text-center py-8 text-sm text-slate/70 gap-3">
      <p>{children}</p>
      {action}
    </div>
  );
}
