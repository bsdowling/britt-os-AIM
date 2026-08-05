import { cn } from "@/lib/cn";
import { MILESTONE_STAGES, STAGE_LABELS } from "@/lib/types";

// Seven-segment milestone bar (PRD §6.1). Completed = sage, current = sand
// (pulsing), future = mist.
export function MilestoneBar({
  currentIndex,
  size = "sm",
  showLabels = false,
}: {
  currentIndex: number;
  size?: "sm" | "lg";
  showLabels?: boolean;
}) {
  return (
    <div className="w-full">
      <div className={cn("flex gap-1", size === "lg" ? "h-2.5" : "h-1.5")}>
        {MILESTONE_STAGES.map((stage, i) => {
          const done = i < currentIndex;
          const current = i === currentIndex;
          return (
            <div
              key={stage}
              title={STAGE_LABELS[stage]}
              className={cn(
                "flex-1 rounded-full transition-colors",
                done && "bg-sage",
                current && "bg-sand animate-pulse",
                !done && !current && "bg-mist",
              )}
            />
          );
        })}
      </div>
      {showLabels && (
        <div className="mt-2 grid grid-cols-7 gap-1 text-[10px] text-slate/70">
          {MILESTONE_STAGES.map((stage, i) => (
            <span
              key={stage}
              className={cn(
                "text-center leading-tight",
                i === currentIndex && "text-ink font-semibold",
              )}
            >
              {STAGE_LABELS[stage]}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
