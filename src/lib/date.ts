// Timezone helpers. All timestamps are stored UTC; the business runs on
// America/Chicago (PRD §3). These helpers keep "today" anchored to Central time
// so the Today panel and deadline math never drift by a day.

export const TZ = "America/Chicago";

// YYYY-MM-DD for "now" in Central time.
export function todayCentral(now: Date = new Date()): string {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return fmt.format(now); // en-CA gives ISO-like YYYY-MM-DD
}

// Whole-day difference (dateStr - today), positive = future.
export function daysFromToday(dateStr: string | null, now: Date = new Date()): number | null {
  if (!dateStr) return null;
  const today = todayCentral(now);
  return dayDiff(today, dateStr);
}

// b - a in whole days, both YYYY-MM-DD.
export function dayDiff(a: string, b: string): number {
  const da = Date.parse(a + "T00:00:00Z");
  const db = Date.parse(b + "T00:00:00Z");
  return Math.round((db - da) / 86_400_000);
}

// Hours since an ISO timestamp.
export function hoursSince(iso: string | null, now: Date = new Date()): number | null {
  if (!iso) return null;
  return Math.floor((now.getTime() - Date.parse(iso)) / 3_600_000);
}

// Add days to a YYYY-MM-DD, returning YYYY-MM-DD.
export function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// Friendly date for humans: "Aug 14".
export function friendlyDate(dateStr: string | null): string {
  if (!dateStr) return "—";
  const d = new Date(dateStr + "T12:00:00Z");
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: TZ }).format(d);
}

// Friendly time from an ISO timestamp: "2:30 PM".
export function friendlyTime(iso: string): string {
  return new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
    timeZone: TZ,
  }).format(new Date(iso));
}

// "Wednesday, August 5" for the header.
export function longToday(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    timeZone: TZ,
  }).format(now);
}

// Countdown label from a day count: "2 days", "Today", "Overdue 3d".
export function countdownLabel(days: number | null): string {
  if (days === null) return "No date";
  if (days === 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days > 1) return `${days} days`;
  if (days === -1) return "Yesterday";
  return `${Math.abs(days)}d overdue`;
}
