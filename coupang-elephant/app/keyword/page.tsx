import Link from "next/link";

export const dynamic = "force-static";

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-bold text-neutral-700 shadow-sm">
      <span className="h-1.5 w-1.5 rounded-full bg-fuchsia-500" />
      {children}
    </span>
  );
}

export default function KeywordPage() {
  return (
    <div className="min-h-screen bg-white text-neutral-900">
      <header className="sticky top-0 z-40 border-b border-black/5 bg-white/75 backdrop-blur supports-[backdrop-filter]:bg-white/55">
        <div className="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4">
          <Link href="/" className="flex items-center gap-2 font-black tracking-tight">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-xl bg-gradient-to-br from-fuchsia-500 to-pink-500 text-white">
              C
            </span>
            <span className="text-sm">COUPANG ELEPHANT</span>
          </Link>
          <div className="ml-auto flex items-center gap-2">
            <Link
              href="/analyze"
              className="rounded-full px-4 py-2 text-sm font-semibold text-neutral-700 hover:bg-black/5"
            >
              분석
            </Link>
            <Link
              href="/recommend"
              className="rounded-full bg-neutral-900 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-neutral-800"
            >
              추천
            </Link>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-10">
        <Pill>발굴</Pill>
        <h1 className="mt-4 text-2xl font-black tracking-tight">키워드 발굴</h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-neutral-600">
          기존 메인에서 사용하던 <span className="font-bold">/keyword</span> 경로가 404가 나서,
          우선 신 디자인 기준으로 페이지 틀을 복구했습니다.
          <br />
          다음 단계에서 실제 발굴 기능(API/화면)을 이 페이지에 이식합니다.
        </p>

        <div className="mt-6 grid gap-3 rounded-3xl border border-black/10 bg-neutral-50 p-6">
          <div className="text-sm font-black">바로가기</div>
          <div className="flex flex-wrap gap-3">
            <Link
              href="/analyze"
              className="inline-flex items-center justify-center rounded-full bg-neutral-900 px-5 py-2 text-sm font-extrabold text-white"
            >
              분석으로 이동
            </Link>
            <Link
              href="/recommend"
              className="inline-flex items-center justify-center rounded-full px-5 py-2 text-sm font-extrabold text-neutral-800 hover:bg-black/5"
            >
              추천/배치 업로드
            </Link>
          </div>
        </div>
      </main>
    </div>
  );
}
