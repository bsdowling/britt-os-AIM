"use client";

import { useState } from "react";

type Kind = "task" | "contact" | "deal" | "content";

// Quick Add (PRD §5.5). Header entry. Anything created here defaults to
// anchor_type = manual and is never touched by the cascade.
export function QuickAdd() {
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<Kind>("task");
  const [title, setTitle] = useState("");
  const [when, setWhen] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    try {
      await fetch("/api/quick-add", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ kind, title, when }),
      });
      setSaved(true);
      setTitle("");
      setWhen("");
      setTimeout(() => {
        setSaved(false);
        setOpen(false);
      }, 900);
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="rounded-btn bg-ink px-3 py-1.5 text-sm font-medium text-paper hover:opacity-90"
      >
        + Quick Add
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 bg-ink/30 flex items-start justify-center pt-24 px-4"
          onClick={() => setOpen(false)}
        >
          <form
            onClick={(e) => e.stopPropagation()}
            onSubmit={submit}
            className="w-full max-w-md rounded-card bg-white shadow-lg border border-mist p-5"
          >
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-heading font-semibold text-ink">Quick Add</h3>
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="text-slate/50 hover:text-ink"
              >
                ✕
              </button>
            </div>

            <div className="flex gap-1 mb-3">
              {(["task", "contact", "deal", "content"] as Kind[]).map((k) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setKind(k)}
                  className={`rounded-chip px-2.5 py-1 text-xs font-medium capitalize ${
                    kind === k ? "bg-ink text-paper" : "bg-mist text-slate"
                  }`}
                >
                  {k}
                </button>
              ))}
            </div>

            <input
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={`New ${kind}…`}
              className="w-full rounded-btn border border-mist px-3 py-2 text-sm outline-none focus:border-sage"
            />

            {(kind === "task" || kind === "content") && (
              <input
                value={when}
                onChange={(e) => setWhen(e.target.value)}
                placeholder='Date — "Friday", "in 3 days", 2026-08-14'
                className="mt-2 w-full rounded-btn border border-mist px-3 py-2 text-sm outline-none focus:border-sage"
              />
            )}

            <button
              type="submit"
              disabled={saving || !title.trim()}
              className="mt-3 w-full rounded-btn bg-sage py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              {saved ? "Added ✓" : saving ? "Saving…" : "Add"}
            </button>
          </form>
        </div>
      )}
    </>
  );
}
