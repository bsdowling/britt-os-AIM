import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

// Auth gate (PRD §2: Supabase Auth, single user, magic link). Runs only when
// Supabase is configured; in demo mode the app is open so it can be reviewed.
//
// Public paths that must never require a login:
//  - /login                (the login page itself)
//  - /track/*              (client portal — unguessable token is the security)
//  - /api/webhooks/*       (signed external callers)
//  - /api/cron/*           (CRON_SECRET protected)
const PUBLIC_PREFIXES = ["/login", "/track", "/api/webhooks", "/api/cron", "/_next", "/favicon"];

export async function middleware(req: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Demo mode: no auth.
  if (!url || !anon) return NextResponse.next();

  const { pathname } = req.nextUrl;
  if (PUBLIC_PREFIXES.some((p) => pathname.startsWith(p))) {
    return NextResponse.next();
  }

  const res = NextResponse.next();
  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll: () => req.cookies.getAll(),
      setAll: (
        cookiesToSet: { name: string; value: string; options?: Record<string, unknown> }[],
      ) => {
        cookiesToSet.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    const loginUrl = req.nextUrl.clone();
    loginUrl.pathname = "/login";
    return NextResponse.redirect(loginUrl);
  }

  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
