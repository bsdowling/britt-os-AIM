import { NextResponse } from "next/server";
import { authorizeCron } from "@/lib/cron";

// Placeholder for cron jobs scheduled in vercel.json but implemented in later
// phases (PRD §9). Returns 200 so Vercel Cron doesn't error, and documents which
// phase wires it up.
export function cronStub(phase: string, description: string) {
  return async function GET(req: Request) {
    const unauth = authorizeCron(req);
    if (unauth) return unauth;
    return NextResponse.json({
      ok: true,
      pending: true,
      phase,
      description,
    });
  };
}
