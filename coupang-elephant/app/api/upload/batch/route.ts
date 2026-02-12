import { NextResponse } from "next/server";

type BatchItem = {
  candidateId: string;
  title: string;
  sourceUrl?: string;
};

type Body = {
  items?: BatchItem[];
  // client-generated idempotency key (optional in MVP)
  idempotencyKey?: string;
};

function isValidItem(x: any): x is BatchItem {
  return (
    x &&
    typeof x.candidateId === "string" &&
    x.candidateId.trim().length > 0 &&
    typeof x.title === "string" &&
    x.title.trim().length > 0
  );
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

export async function POST(req: Request) {
  const body = (await req.json().catch(() => null)) as Body | null;
  const items = Array.isArray(body?.items) ? body!.items : [];

  if (!items.length) {
    return NextResponse.json(
      { ok: false, message: "업로드할 상품이 없습니다." },
      { status: 400 },
    );
  }

  // Guardrails: keep payload small in MVP.
  if (items.length > 25) {
    return NextResponse.json(
      {
        ok: false,
        message:
          "한 번에 업로드할 수 있는 상품 수를 초과했습니다. (최대 25개)",
      },
      { status: 413 },
    );
  }

  // MVP implementation:
  // - This simulates the 'batch upload' behavior with per-item results.
  // - Replace `simulateUpload` with the existing working upload logic (single item)
  //   and run it sequentially / with limited concurrency.

  const startedAt = new Date().toISOString();

  const results: Array<{
    candidateId: string;
    ok: boolean;
    message: string;
    uploadedId?: string;
  }> = [];

  // Sequential processing avoids rate-limit bursts and simplifies error handling.
  for (const raw of items) {
    if (!isValidItem(raw)) {
      const candidateId =
        raw && typeof (raw as any).candidateId === "string" ? (raw as any).candidateId : "unknown";
      results.push({
        candidateId,
        ok: false,
        message: "Invalid item payload.",
      });
      continue;
    }

    // Simulate variable latency.
    await sleep(80 + Math.round(Math.random() * 140));

    // Simulate occasional failures.
    const fail = raw.title.toLowerCase().includes("fail") || Math.random() < 0.08;
    if (fail) {
      results.push({
        candidateId: raw.candidateId,
        ok: false,
        message: "업로드 실패(시뮬레이션). 재시도하세요.",
      });
      continue;
    }

    results.push({
      candidateId: raw.candidateId,
      ok: true,
      message: "업로드 완료",
      uploadedId: `upl_${raw.candidateId}`,
    });
  }

  const okCount = results.filter((r) => r.ok).length;
  const failCount = results.length - okCount;

  return NextResponse.json({
    ok: failCount === 0,
    startedAt,
    finishedAt: new Date().toISOString(),
    summary: {
      total: results.length,
      ok: okCount,
      failed: failCount,
    },
    results,
  });
}
