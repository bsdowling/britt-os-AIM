// Wordmark (PRD §11). Apostrophe-S in sage for a piece of ownership.
export function Wordmark({ className = "" }: { className?: string }) {
  return (
    <span
      className={`font-heading font-bold tracking-[0.12em] text-ink select-none ${className}`}
    >
      BRITT<span className="text-sage">&apos;S</span> OS
    </span>
  );
}
