import { cn } from "@/lib/cn";

export function Chip({
  children,
  tone = "neutral",
  className,
}: {
  children: React.ReactNode;
  tone?: "neutral" | "sage" | "sand" | "alert" | "ink";
  className?: string;
}) {
  const tones: Record<string, string> = {
    neutral: "bg-mist text-slate",
    sage: "bg-sage/15 text-sage",
    sand: "bg-sand/30 text-ink",
    alert: "bg-alert/12 text-alert",
    ink: "bg-ink text-paper",
  };
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-chip px-2 py-0.5 text-xs font-medium whitespace-nowrap",
        tones[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}
