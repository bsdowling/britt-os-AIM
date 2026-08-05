// Tiny natural-language date parser for Quick Add (PRD §5.5): "Friday",
// "in 3 days", "tomorrow", "today", or an ISO date. Returns YYYY-MM-DD or null.

import { addDays, todayCentral } from "./date";

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

export function parseNaturalDate(input: string, now = new Date()): string | null {
  const s = input.trim().toLowerCase();
  if (!s) return null;

  // ISO date
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;

  const today = todayCentral(now);
  if (s === "today") return today;
  if (s === "tomorrow") return addDays(today, 1);

  // "in N days" / "N days"
  const inDays = s.match(/^(?:in\s+)?(\d+)\s+days?$/);
  if (inDays) return addDays(today, parseInt(inDays[1], 10));

  // "next <weekday>" or "<weekday>"
  const wd = s.replace(/^next\s+/, "");
  const idx = WEEKDAYS.indexOf(wd);
  if (idx >= 0) {
    // current weekday in Central time
    const nowIdx = new Date(today + "T12:00:00Z").getUTCDay();
    let delta = (idx - nowIdx + 7) % 7;
    if (delta === 0) delta = 7; // next occurrence, not today
    return addDays(today, delta);
  }

  return null;
}
