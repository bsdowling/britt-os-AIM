import { cronStub } from "@/lib/cron-stub";

// Hourly deadline check + tier-1 SMS escalation
export const GET = cronStub("Phase 3", "Hourly deadline check + tier-1 SMS escalation");
