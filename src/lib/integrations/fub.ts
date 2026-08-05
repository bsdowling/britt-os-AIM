// Follow Up Boss API client (PRD §7.1, P0). FUB is the system of record; the OS
// mirrors people and writes back through this client so history stays in one place.
//
// Auth: API key in the HTTP Basic username field, blank password, base64 encoded.
// An X-System header identifies the integration to FUB.

import { z } from "zod";
import { env } from "@/lib/env";

const BASE_URL = "https://api.followupboss.com/v1";

function authHeader(): string {
  const key = env.fubApiKey ?? "";
  return "Basic " + Buffer.from(`${key}:`).toString("base64");
}

export class FubError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
    this.name = "FubError";
  }
}

interface FubRequestOptions {
  method?: "GET" | "POST" | "PUT";
  query?: Record<string, string | number | undefined>;
  body?: unknown;
  // simple retry with backoff for 429 / 5xx
  retries?: number;
}

async function fubRequest<T>(path: string, opts: FubRequestOptions = {}): Promise<T> {
  if (!env.fubApiKey) {
    throw new FubError("FUB_API_KEY is not configured", 0);
  }
  const { method = "GET", query, body, retries = 3 } = opts;

  const url = new URL(BASE_URL + path);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined) url.searchParams.set(k, String(v));
    }
  }

  let attempt = 0;
  // exponential backoff: 500ms, 1s, 2s
  for (;;) {
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: authHeader(),
        "Content-Type": "application/json",
        "X-System": env.fubSystemName,
        ...(env.fubSystemName ? { "X-System-Key": process.env.FUB_SYSTEM_KEY ?? "" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      cache: "no-store",
    });

    if (res.status === 429 || res.status >= 500) {
      if (attempt < retries) {
        const wait = 500 * 2 ** attempt;
        await new Promise((r) => setTimeout(r, wait));
        attempt += 1;
        continue;
      }
    }

    if (!res.ok) {
      const text = await res.text().catch(() => res.statusText);
      throw new FubError(`FUB ${method} ${path} failed: ${text}`, res.status);
    }

    return (await res.json()) as T;
  }
}

// --- Schemas (external data is never trusted — PRD §2) ---------------------
export const fubPersonSchema = z.object({
  id: z.number(),
  firstName: z.string().nullish(),
  lastName: z.string().nullish(),
  stage: z.string().nullish(),
  source: z.string().nullish(),
  created: z.string().nullish(),
  updated: z.string().nullish(),
  emails: z
    .array(z.object({ value: z.string(), type: z.string().nullish(), isPrimary: z.boolean().nullish() }))
    .nullish(),
  phones: z
    .array(z.object({ value: z.string(), type: z.string().nullish(), isPrimary: z.boolean().nullish() }))
    .nullish(),
  tags: z.array(z.string()).nullish(),
});
export type FubPerson = z.infer<typeof fubPersonSchema>;

const peopleResponseSchema = z.object({
  _metadata: z
    .object({ collection: z.string().nullish(), next: z.string().nullish(), nextLink: z.string().nullish() })
    .nullish(),
  people: z.array(z.unknown()),
});

// List people modified since a cursor (incremental sync — PRD §7.1 reconcile).
export async function listPeople(params: {
  updatedAfter?: string;
  limit?: number;
  offset?: number;
}): Promise<{ people: FubPerson[]; next: string | null }> {
  const raw = await fubRequest<unknown>("/people", {
    query: {
      sort: "updated",
      limit: params.limit ?? 100,
      offset: params.offset,
      updatedAfter: params.updatedAfter,
    },
  });
  const parsed = peopleResponseSchema.parse(raw);
  const people = parsed.people
    .map((p) => fubPersonSchema.safeParse(p))
    .filter((r): r is { success: true; data: FubPerson } => r.success)
    .map((r) => r.data);
  return { people, next: parsed._metadata?.next ?? null };
}

// Post a note back to FUB so it appears in the person's timeline (write-back).
export async function createNote(personId: number, body: string): Promise<void> {
  await fubRequest("/notes", { method: "POST", body: { personId, body } });
}

// Send a text through FUB so the conversation stays in one history (PRD §7.1).
export async function createTextMessage(personId: number, message: string): Promise<void> {
  await fubRequest("/textMessages", { method: "POST", body: { personId, message } });
}

// Map a FUB person payload to the contacts mirror row.
export function mapPersonToContact(p: FubPerson) {
  return {
    fub_person_id: p.id,
    first_name: p.firstName ?? null,
    last_name: p.lastName ?? null,
    stage: p.stage ?? null,
    source: p.source ?? null,
    emails: (p.emails ?? []).map((e) => ({ value: e.value, type: e.type ?? undefined, is_primary: e.isPrimary ?? false })),
    phones: (p.phones ?? []).map((e) => ({ value: e.value, type: e.type ?? undefined, is_primary: e.isPrimary ?? false })),
    tags: p.tags ?? [],
    fub_created_at: p.created ?? null,
    synced_at: new Date().toISOString(),
    fub_raw: p,
  };
}
