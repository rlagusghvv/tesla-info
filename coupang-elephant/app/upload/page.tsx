"use client";

import { useState } from "react";
import Shell from "../ui/Shell";

async function apiJson(path: string, init?: RequestInit) {
  const r = await fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
    credentials: "include",
  });
  const text = await r.text();
  try {
    return { ok: r.ok, status: r.status, json: JSON.parse(text) };
  } catch {
    return { ok: r.ok, status: r.status, json: { ok: false, raw: text } };
  }
}

export default function UploadPage() {
  const [url, setUrl] = useState("https://domeggook.com/");
  const [preview, setPreview] = useState<any>(null);
  const [busy, setBusy] = useState(false);
  const [log, setLog] = useState<string>("");

  const doPreview = async () => {
    setBusy(true);
    try {
      setPreview(null);
      const r = await apiJson("/api/upload/preview", {
        method: "POST",
        body: JSON.stringify({ url }),
      });
      if (r.ok && r.json?.ok) {
        setPreview(r.json);
        setLog((s) => `${s}\npreview ok`);
      } else {
        setLog((s) => `${s}\npreview failed (${r.status})`);
      }
    } finally {
      setBusy(false);
    }
  };

  const enqueue = async () => {
    setBusy(true);
    try {
      const r = await apiJson("/api/upload-queue/enqueue", {
        method: "POST",
        body: JSON.stringify({ url, force: "0" }),
      });
      if (r.ok && r.json?.ok) {
        setLog((s) => `${s}\nqueued`);
      } else {
        setLog((s) => `${s}\nqueue failed (${r.status})`);
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <Shell title="업로드" subtitle="URL → 미리보기 → 큐">
      <section className="rounded-3xl border border-black/10 bg-white p-6 shadow-[0_20px_60px_-30px_rgba(0,0,0,0.25)]">
        <div className="text-sm font-extrabold">도매꾹/도매매 링크</div>
        <input
          className="mt-3 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-fuchsia-400"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="https://domeggook.com/..."
        />
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            className="rounded-full px-4 py-2 text-sm font-bold text-neutral-800 hover:bg-black/5 disabled:opacity-60"
            onClick={doPreview}
            disabled={busy}
          >
            미리보기
          </button>
          <button
            className="rounded-full bg-neutral-900 px-4 py-2 text-sm font-bold text-white hover:bg-neutral-800 disabled:opacity-60"
            onClick={enqueue}
            disabled={busy}
          >
            큐에 넣기
          </button>
          <a
            className="rounded-full px-4 py-2 text-sm font-bold text-neutral-800 hover:bg-black/5"
            href="/console"
            target="_blank"
            rel="noreferrer"
          >
            레거시 콘솔 열기
          </a>
        </div>

        <div className="mt-6 grid grid-cols-1 gap-6 md:grid-cols-2">
          <div className="rounded-2xl border border-black/10 bg-neutral-50 p-4">
            <div className="text-sm font-extrabold">미리보기</div>
            <div className="mt-3 text-xs text-neutral-600">
              {preview?.preview?.draft?.title || preview?.draft?.title || "-"}
            </div>
            <pre className="mt-3 max-h-[420px] overflow-auto rounded-xl border border-black/10 bg-white p-3 text-[11px]">
              {preview ? JSON.stringify(preview, null, 2) : "-"}
            </pre>
          </div>

          <div className="rounded-2xl border border-black/10 bg-neutral-50 p-4">
            <div className="text-sm font-extrabold">로그</div>
            <pre className="mt-3 max-h-[520px] overflow-auto rounded-xl border border-black/10 bg-neutral-950 p-3 text-[11px] text-white">
              {log || "-"}
            </pre>
          </div>
        </div>
      </section>
    </Shell>
  );
}
