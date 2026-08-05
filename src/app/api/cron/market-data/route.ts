import { cronStub } from "@/lib/cron-stub";

// Nightly market pull for target zips to compute local medians
export const GET = cronStub("Phase 4", "Nightly market pull for target zips to compute local medians");
