"use client";

import { useMemo, useState } from "react";

type Candidate = {
  candidateId: string;
  title: string;
  reason: string;
  effort: "낮음" | "중" | "높음";
  competition: "낮음" | "중" | "높음";
};

function cx(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(" ");
}

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-bold text-neutral-700 shadow-sm">
      <span className="h-1.5 w-1.5 rounded-full bg-fuchsia-500" />
      {children}
    </span>
  );
}

export default function RecommendPage() {
  const [keyword, setKeyword] = useState("");
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const [batchResult, setBatchResult] = useState<any>(null);
  const [jobId, setJobId] = useState<string | null>(null);

  const selectedIds = useMemo(
    () => Object.entries(selected).filter(([, v]) => v).map(([k]) => k),
    [selected],
  );

  async function generate() {
    const k = keyword.trim();
    if (!k) {
      setError("키워드를 입력해 주세요.");
      return;
    }

    setLoading(true);
    setError(null);
    setBatchResult(null);
    setJobId(null);

    try {
      const res = await fetch("/api/recommend", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ keyword: k }),
      });
      const json = await res.json();
      if (!res.ok || json?.ok === false) {
        setError(json?.message ?? "추천 생성 실패");
        return;
      }

      const list: Candidate[] = json.candidates ?? [];
      setCandidates(list);
      // default select top 3
      const nextSel: Record<string, boolean> = {};
      for (const c of list) nextSel[c.candidateId] = false;
      list.slice(0, 3).forEach((c) => (nextSel[c.candidateId] = true));
      setSelected(nextSel);
    } catch (e: any) {
      setError(e?.message ?? "추천 생성 실패");
    } finally {
      setLoading(false);
    }
  }

  async function uploadBatch(itemsOverride?: Array<{ candidateId: string; title: string }>) {
    setError(null);
    setBatchResult(null);
    setJobId(null);

    const items =
      itemsOverride ??
      candidates
        .filter((c) => selected[c.candidateId])
        .map((c) => ({ candidateId: c.candidateId, title: c.title }));

    if (items.length === 0) {
      setError("업로드할 상품을 선택해 주세요.");
      return;
    }

    setUploading(true);
    try {

      const idempotencyKey = `rec_upload_${items
        .map((x) => x.candidateId)
        .sort()
        .join("_")}`;

      const res = await fetch("/api/upload/batch", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items, idempotencyKey }),
      });
      const json = await res.json();
      if (!res.ok) {
        setError(json?.message ?? "배치 업로드 실패");
        setBatchResult(json);
        return;
      }

      const nextJobId = json?.jobId as string | undefined;
      if (!nextJobId) {
        setError("jobId가 없습니다.");
        setBatchResult(json);
        return;
      }

      setJobId(nextJobId);

      // Poll job status until done.
      for (let i = 0; i < 60; i++) {
        const r = await fetch(`/api/upload/batch?jobId=${encodeURIComponent(nextJobId)}`);
        const j = await r.json();
        if (!r.ok || j?.ok === false) {
          setError(j?.message ?? "상태 조회 실패");
          setBatchResult(j);
          break;
        }
        setBatchResult(j);
        if (j?.job?.status === "done") break;
        await new Promise((rr) => setTimeout(rr, 400));
      }
    } catch (e: any) {
      setError(e?.message ?? "배치 업로드 실패");
    } finally {
      setUploading(false);
    }
  }

  const canGenerate = keyword.trim().length > 0 && !loading;

  return (
    <div className="min-h-screen bg-white text-neutral-900">
      <header className="sticky top-0 z-40 border-b border-black/5 bg-white/75 backdrop-blur supports-[backdrop-filter]:bg-white/55">
        <div className="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4">
          <a href="/" className="flex items-center gap-2 font-black tracking-tight">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-xl bg-gradient-to-br from-fuchsia-500 to-pink-500 text-white">
              C
            </span>
            <span className="text-sm">COUPANG ELEPHANT</span>
          </a>
          <div className="ml-auto flex items-center gap-2">
            <a
              href="/analyze"
              className="rounded-full px-4 py-2 text-sm font-semibold text-neutral-700 hover:bg-black/5"
            >
              분석
            </a>
            <button
              onClick={() => uploadBatch()}
              disabled={uploading || selectedIds.length === 0}
              className={cx(
                "rounded-full px-5 py-2 text-sm font-extrabold text-white shadow-sm",
                uploading || selectedIds.length === 0
                  ? "bg-neutral-300 cursor-not-allowed"
                  : "bg-neutral-900 hover:bg-neutral-800",
              )}
            >
              {uploading ? "업로드 중…" : `선택 ${selectedIds.length}개 업로드`}
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-10">
        <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
          <section className="rounded-3xl border border-black/10 bg-white p-6 shadow-[0_20px_60px_-30px_rgba(0,0,0,0.25)] md:col-span-1">
            <Pill>추천</Pill>
            <h1 className="mt-4 text-2xl font-black tracking-tight">추천 상품을 고르고 한 번에 업로드</h1>
            <p className="mt-3 text-sm leading-6 text-neutral-600">
              대표 피드백: 추천에서 여러 상품을 한 번에 업로드할 때 오류가 발생.
              <br />
              이 화면은 “배치 업로드”를 상품별 결과로 분해해 보여주는 MVP입니다.
            </p>

            <div className="mt-6 grid gap-3">
              <label className="grid gap-2">
                <span className="text-sm font-bold text-neutral-700">키워드</span>
                <input
                  value={keyword}
                  onChange={(e) => setKeyword(e.target.value)}
                  placeholder="예: 강남역, 스마트워치"
                  className="rounded-2xl border border-black/10 bg-neutral-50 px-4 py-3 text-sm font-semibold outline-none placeholder:text-neutral-400 focus:border-fuchsia-400"
                />
              </label>

              {error && (
                <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
                  {error}
                </div>
              )}

              <button
                onClick={generate}
                disabled={!canGenerate}
                className={cx(
                  "rounded-2xl px-5 py-3 text-sm font-extrabold text-white shadow-sm",
                  canGenerate
                    ? "bg-gradient-to-r from-fuchsia-600 to-pink-600 hover:opacity-95"
                    : "bg-neutral-300 cursor-not-allowed",
                )}
              >
                {loading ? "생성 중…" : "추천 생성"}
              </button>
            </div>
          </section>

          <section className="rounded-3xl border border-black/10 bg-white p-6 shadow-[0_20px_60px_-30px_rgba(0,0,0,0.25)] md:col-span-2">
            <div className="flex items-center justify-between gap-3">
              <Pill>추천 리스트</Pill>
              <div className="text-xs font-semibold text-neutral-500">
                * MVP: 업로드 API는 시뮬레이션. 실제 서비스 업로드 로직에 교체하세요.
              </div>
            </div>

            {candidates.length === 0 ? (
              <div className="mt-6 rounded-3xl border border-black/10 bg-neutral-50 p-6 text-sm text-neutral-600">
                키워드를 입력하고 추천을 생성하세요.
              </div>
            ) : (
              <div className="mt-6 grid gap-3">
                {candidates.map((c) => (
                  <label
                    key={c.candidateId}
                    className="flex cursor-pointer items-start gap-4 rounded-3xl border border-black/10 bg-white p-5 hover:bg-neutral-50"
                  >
                    <input
                      type="checkbox"
                      className="mt-1 h-5 w-5"
                      checked={!!selected[c.candidateId]}
                      onChange={(e) =>
                        setSelected((prev) => ({
                          ...prev,
                          [c.candidateId]: e.target.checked,
                        }))
                      }
                    />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <div className="text-base font-black">{c.title}</div>
                        <span className="rounded-full bg-neutral-900 px-2 py-0.5 text-xs font-bold text-white">
                          경쟁 {c.competition}
                        </span>
                        <span className="rounded-full bg-black/5 px-2 py-0.5 text-xs font-bold text-neutral-700">
                          노력 {c.effort}
                        </span>
                      </div>
                      <div className="mt-2 text-sm text-neutral-600">{c.reason}</div>
                    </div>
                  </label>
                ))}
              </div>
            )}

            {batchResult && (
              <div className="mt-8 rounded-3xl border border-black/10 bg-neutral-50 p-6">
                <div className="flex items-center justify-between gap-3">
                  <div className="text-sm font-black">배치 업로드 결과</div>
                  {jobId && (
                    <div className="text-[11px] font-bold text-neutral-500">jobId: {jobId}</div>
                  )}
                </div>

                {batchResult?.job && (
                  <>
                    <div className="mt-2 flex flex-wrap items-center justify-between gap-3 text-sm text-neutral-700">
                      <div>
                        상태: <span className="font-extrabold">{batchResult.job.status}</span> · 진행 {batchResult.job.processed}/{batchResult.job.total} · 성공 {batchResult.job.ok} · 실패 {batchResult.job.failed}
                      </div>

                      {batchResult.job.status === "done" && batchResult.job.failed > 0 && (
                        <button
                          onClick={() => {
                            const failed = (batchResult?.job?.results ?? []).filter((r: any) => !r.ok);
                            uploadBatch(
                              failed.map((r: any) => ({
                                candidateId: r.candidateId,
                                title:
                                  candidates.find((c) => c.candidateId === r.candidateId)?.title ??
                                  r.candidateId,
                              })),
                            );
                          }}
                          disabled={uploading}
                          className={cx(
                            "rounded-full px-4 py-2 text-xs font-extrabold text-white",
                            uploading
                              ? "bg-neutral-300 cursor-not-allowed"
                              : "bg-neutral-900 hover:bg-neutral-800",
                          )}
                        >
                          실패 항목만 재시도
                        </button>
                      )}
                    </div>

                    <div className="mt-3 h-2 w-full rounded-full bg-neutral-200">
                      <div
                        className="h-2 rounded-full bg-gradient-to-r from-fuchsia-600 to-pink-600"
                        style={{
                          width: `${Math.min(
                            100,
                            Math.round((batchResult.job.processed / Math.max(1, batchResult.job.total)) * 100),
                          )}%`,
                        }}
                      />
                    </div>

                    <div className="mt-4 grid gap-2 text-sm">
                      {(batchResult?.job?.results ?? []).map((r: any) => (
                        <div
                          key={r.candidateId}
                          className={cx(
                            "rounded-2xl border px-4 py-2",
                            r.ok
                              ? "border-emerald-200 bg-emerald-50 text-emerald-800"
                              : "border-red-200 bg-red-50 text-red-800",
                          )}
                        >
                          <span className="font-extrabold">{r.candidateId}</span> — {r.message}
                        </div>
                      ))}
                    </div>
                  </>
                )}

                {!batchResult?.job && (
                  <div className="mt-3 text-sm text-neutral-700">
                    {JSON.stringify(batchResult)}
                  </div>
                )}
              </div>
            )}
          </section>
        </div>
      </main>

      <footer className="border-t border-black/5 bg-white py-10">
        <div className="mx-auto max-w-6xl px-4 text-sm text-neutral-600">
          배치 업로드는 (1) 동시성 제한 (2) 상품별 결과 (3) 재시도/멱등성 으로 안정화합니다.
        </div>
      </footer>
    </div>
  );
}
