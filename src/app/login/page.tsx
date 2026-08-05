"use client";

import { useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/env";
import { Wordmark } from "@/components/ui/Wordmark";

// Magic-link login (PRD §2). Single user, no password.
export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const supabase = getBrowserSupabase();
    if (!supabase) {
      setError("Auth is not configured. Running in demo mode.");
      return;
    }
    setLoading(true);
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/` },
    });
    setLoading(false);
    if (error) setError(error.message);
    else setSent(true);
  }

  return (
    <div className="min-h-screen grid place-items-center px-4">
      <div className="w-full max-w-sm rounded-card bg-white border border-mist shadow-panel p-8">
        <div className="flex justify-center mb-6">
          <Wordmark className="text-xl" />
        </div>

        {!isSupabaseConfigured ? (
          <div className="text-center text-sm text-slate">
            <p className="mb-4">Running in demo mode — no login required.</p>
            <a href="/" className="rounded-btn bg-ink text-paper px-4 py-2 inline-block">
              Open the dashboard
            </a>
          </div>
        ) : sent ? (
          <p className="text-center text-sm text-slate">
            Check your email for a magic link to sign in.
          </p>
        ) : (
          <form onSubmit={submit} className="flex flex-col gap-3">
            <label className="text-sm font-medium text-ink">Email</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="rounded-btn border border-mist px-3 py-2 text-sm outline-none focus:border-sage"
            />
            {error && <p className="text-xs text-alert">{error}</p>}
            <button
              type="submit"
              disabled={loading}
              className="rounded-btn bg-sage text-white py-2 text-sm font-medium disabled:opacity-50"
            >
              {loading ? "Sending…" : "Send magic link"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
