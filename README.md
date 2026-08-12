# Britt's OS

A single-screen operating system for a solo real estate business. It reads from
the tools already in use (Follow Up Boss, MLS), ranks what matters today, and
answers three questions on one page: **what am I doing today, which clients need
me, and which leads are worth calling.**

This is not a CRM. It is a decision layer that sits on top of Follow Up Boss
(the system of record). Built per the Britt's OS PRD v1.0.

> **Stack:** Next.js 15 (App Router, TypeScript) · Supabase (Postgres + Auth) ·
> Tailwind + brand tokens · TanStack Query · Zod · Vercel (+ Cron). See PRD §2.

---

## Quick start

```bash
npm install
npm run dev          # http://localhost:3000
```

With no environment variables the app runs in **demo mode** — the full dashboard
renders against realistic sample data (40 contacts, 6 deals, 3 listings, tasks,
content, appointments), so you can review the layout and behavior before wiring
any integration. A banner marks demo mode.

To connect a live database, copy `.env.example` → `.env.local` and set at least
the Supabase variables. See **Going live** below.

## What's built (Phase 0 + Phase 1 MVP)

Per the PRD build order (§9):

- **Phase 0 — Foundation:** Next.js + TypeScript app, full Supabase schema
  migration (`supabase/migrations/`), Tailwind config carrying the brand tokens
  (§11), Supabase Auth (magic link) with route-protecting middleware,
  `vercel.json` cron schedule, `.env.example`.
- **Phase 1 — The one screen:** all seven dashboard panels (§4):
  1. **Today** — merged timeline of tasks + appointments, overdue band, one-tap complete
  2. **Who Needs Me** — waiting-on-you / deadline-72h / gone-quiet groups
  3. **Active Deals** — horizontal rail, milestone bars, deal-health borders
  4. **Lead Follow-Up Queue** — top 15 by lead score with plain-language reason chips
  5. **Content Engine** — weekly slots + idea inbox with kanban status filter
  6. **Listing Pulse** — DOM, showings, feedback, price-reduction flag
  7. **Numbers Strip** — six period-over-period stats
- **Quick Add** with natural-language dates (§5.5)
- **Deal detail** page (timeline, tasks, key dates, contact, portal link)
- **Client portal** (`/track/[token]`) — the login-free "pizza tracker" with
  plain-language stage copy (§6.2), `noindex`
- **FUB API client** (Zod-validated, rate-limit backoff, write-back), webhook
  receiver (signature verify + dedupe), nightly reconcile cron (§7.1)
- **Lead score** and **task/deadline engine** (template firing + the cascade)
  as pure, tested-shaped functions (`src/lib/scoring.ts`, `src/lib/engine.ts`)

Later phases (2–5) — full cascade UI with preview/undo, notifications/digests,
MLS sync, content auto-capture, calendar sync — are scaffolded as cron stubs and
library functions, marked with the phase that completes them.

## Architecture

```
src/
  app/
    page.tsx                 One-screen dashboard (server component)
    deals/[id]/page.tsx      Deal detail
    track/[token]/page.tsx   Public client portal
    login/page.tsx           Magic-link login
    api/
      tasks/[id]/complete    One-tap task completion
      quick-add              Quick Add handler
      webhooks/fub           Signed FUB webhook receiver
      cron/*                 Scheduled jobs (recalc-scores, fub-reconcile, + stubs)
  components/
    panels/                  The seven dashboard panels
    ui/                      Panel, Chip, Wordmark, MilestoneBar
  lib/
    data.ts                  View-model assembly (pure fns over a Dataset)
    demo-data.ts             Sample fixtures for demo mode
    scoring.ts               Lead score + reason chip (§4.4)
    engine.ts                Template firing + date cascade (§5)
    deal-health.ts           Deal health, next deadline, milestone index
    date.ts                  America/Chicago date helpers
    integrations/fub.ts      Follow Up Boss client
    supabase/                Server + browser clients
supabase/migrations/         Schema + starter task templates
```

**Key design choice — demo/live parity:** panel logic lives in pure functions
over a `Dataset`. `loadDataset()` returns either demo fixtures or Supabase rows,
so the exact same computations run in both modes.

## Going live

1. Create a Supabase project (paid tier — the free tier pauses and cron fails
   silently, PRD §10).
2. **Build the database.** Open the Supabase **SQL Editor** and paste/run
   [`supabase/setup_all.sql`](supabase/setup_all.sql) — one file containing the
   schema, task templates, and sample data, in order. (Or run the pieces
   separately: `migrations/0001_init.sql`, `migrations/0002_templates_seed.sql`,
   then `seed.sql`.) With direct DB access you can instead `npm run seed`.
3. Set `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (the
   `sb_publishable_...` key), and `SUPABASE_SERVICE_ROLE_KEY` (the `sb_secret_...`
   key) in `.env.local`.
4. Run `npm run dev` — the demo banner disappears and the dashboard shows live rows.
5. Add Follow Up Boss (`FUB_API_KEY`, `FUB_WEBHOOK_SECRET`) and register the
   webhook at `/api/webhooks/fub`.
6. Deploy to Vercel; `vercel.json` wires the cron jobs. Set `CRON_SECRET`.

> **Regenerating the seed SQL:** `npx tsx scripts/gen-seed-sql.ts` rewrites
> `supabase/seed.sql` (and re-bundle with the migrations into `setup_all.sql`).
> Sample dates are relative to generation time, so regenerate for fresh-looking demo data.

### Security note — Row Level Security

The schema ships **without RLS policies** (PRD §2: "RLS is there when a client
portal or a future assistant login is added"). For a single operator behind
magic-link auth that's the intended starting point, but the `anon`/publishable
key is exposed to the browser, so **before exposing anything publicly**, enable
RLS on the data tables and add policies. The public client portal reads through
a server route, so it does not require broad anon access.

Cron schedules are set for Central Time in UTC; jobs re-check the local hour
internally so the twice-a-year DST shift needs no file edit (PRD §10).

## Scripts

| Command | Description |
|---|---|
| `npm run dev` | Dev server |
| `npm run build` | Production build |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run seed` | Seed sample data into a live Supabase DB |

## Definition of done (Phase 1, PRD Appendix B)

For five consecutive workdays, open only the dashboard in the morning and get
through the day without opening Follow Up Boss to figure out what to do.
