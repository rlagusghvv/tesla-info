"use client";

import { useMemo, useState } from "react";

type FeatureTab = "상품 분석" | "소싱 분석" | "광고 분석";

function cx(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(" ");
}

export default function Home() {
  const tabs: FeatureTab[] = ["상품 분석", "소싱 분석", "광고 분석"];
  const [tab, setTab] = useState<FeatureTab>("상품 분석");

  const tabCopy = useMemo(() => {
    switch (tab) {
      case "상품 분석":
        return {
          title: "AI가 골라준 상품만\n딱 골라 추천합니다.",
          desc: "리뷰/검색/매출 신호를 한 화면에서 확인하고, 다음 액션까지 바로 제안합니다.",
          pill: "상품 분석",
        };
      case "소싱 분석":
        return {
          title: "수요가 있는 키워드로\n소싱을 역산합니다.",
          desc: "경쟁/가격대/마진을 함께 보고 ‘지금 팔릴 확률’이 높은 후보를 먼저 고릅니다.",
          pill: "소싱 분석",
        };
      case "광고 분석":
        return {
          title: "광고비가 새는 구간을\n데이터로 막습니다.",
          desc: "ROAS 변동을 원인까지 추적하고, 예산 배분을 자동으로 추천합니다.",
          pill: "광고 분석",
        };
      default:
        return null;
    }
  }, [tab]);

  return (
    <div className="min-h-screen bg-white text-neutral-900">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-black/5 bg-white/75 backdrop-blur supports-[backdrop-filter]:bg-white/55">
        <div className="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4">
          <div className="flex items-center gap-2 font-black tracking-tight">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-xl bg-gradient-to-br from-fuchsia-500 to-pink-500 text-white">
              C
            </span>
            <span className="text-sm">COUPILOT</span>
          </div>

          <nav className="hidden items-center gap-5 pl-6 text-sm font-semibold text-neutral-700 md:flex">
            <a className="hover:text-neutral-950" href="#pricing">
              요금제
            </a>
            <a className="hover:text-neutral-950" href="#quality">
              품질
            </a>
            <a className="hover:text-neutral-950" href="#manage">
              관리
            </a>
            <a className="hover:text-neutral-950" href="#consulting">
              컨설팅
            </a>
          </nav>

          <div className="ml-auto flex items-center gap-2">
            <div className="hidden w-[340px] items-center rounded-full border border-black/10 bg-white px-4 py-2 text-sm shadow-sm md:flex">
              <span className="mr-2 text-neutral-400">카테고리</span>
              <input
                className="w-full bg-transparent outline-none placeholder:text-neutral-400"
                placeholder="오늘 뭐 팔지, 키워드를 입력해보세요"
              />
              <button
                className="ml-2 inline-flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-fuchsia-500 to-pink-500 text-white"
                aria-label="search"
              >
                <span className="text-sm">⌕</span>
              </button>
            </div>
            <button className="rounded-full px-4 py-2 text-sm font-semibold text-neutral-700 hover:bg-black/5">
              로그인
            </button>
            <a
              href="/analyze"
              className="inline-flex items-center justify-center rounded-full bg-neutral-900 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-neutral-800"
            >
              시작하기
            </a>
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute -left-24 -top-36 h-[520px] w-[520px] rounded-full bg-fuchsia-200/55 blur-3xl" />
          <div className="absolute -right-24 top-16 h-[520px] w-[520px] rounded-full bg-pink-200/55 blur-3xl" />
        </div>

        <div className="mx-auto grid max-w-6xl grid-cols-1 gap-10 px-4 py-16 md:grid-cols-2 md:py-20">
          <div className="flex flex-col justify-center">
            <div className="inline-flex w-fit items-center gap-2 rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-semibold text-neutral-700 shadow-sm">
              <span className="h-1.5 w-1.5 rounded-full bg-pink-500" />
              쿠팡에서만 통하는 ‘실전’ 데이터
            </div>

            <h1 className="mt-5 text-balance text-4xl font-black leading-[1.05] tracking-tight md:text-5xl">
              사업이 막막한 순간,
              <br />
              답은 <span className="bg-gradient-to-r from-fuchsia-600 to-pink-600 bg-clip-text text-transparent">데이터</span>에
              <br />
              있습니다.
            </h1>

            <p className="mt-5 max-w-xl text-pretty text-base font-medium leading-7 text-neutral-600 md:text-lg">
              쿠팡 운영의 본질은 ‘감’이 아니라 ‘확률’입니다.
              <br />
              판매/리뷰/가격/광고 신호를 하나로 묶어, 오늘의 액션을 제시합니다.
            </p>

            <div className="mt-7 flex flex-wrap items-center gap-3">
              <a
                href="/analyze"
                className="inline-flex items-center justify-center rounded-full bg-neutral-900 px-6 py-3 text-sm font-bold text-white shadow-sm hover:bg-neutral-800"
              >
                빠르게 시작하기 →
              </a>
              <button className="rounded-full px-6 py-3 text-sm font-bold text-neutral-800 hover:bg-black/5">
                로그보기
              </button>
            </div>

            <div className="mt-7 flex items-center gap-3 text-sm text-neutral-600">
              <div className="flex -space-x-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div
                    key={i}
                    className={cx(
                      "h-8 w-8 rounded-full border border-white bg-gradient-to-br shadow-sm",
                      i % 2 ? "from-neutral-200 to-neutral-50" : "from-neutral-100 to-neutral-200",
                    )}
                  />
                ))}
              </div>
              <span className="font-semibold text-neutral-800">10,000+</span>
              <span>대표님들이 이미 사용 중</span>
            </div>
          </div>

          {/* Hero mock */}
          <div className="relative">
            <div className="relative mx-auto aspect-[5/4] w-full max-w-[560px] rounded-3xl border border-black/10 bg-white shadow-[0_30px_80px_-30px_rgba(0,0,0,0.35)]">
              <div className="absolute left-5 top-5 flex items-center gap-2">
                <span className="h-3 w-3 rounded-full bg-red-400" />
                <span className="h-3 w-3 rounded-full bg-amber-300" />
                <span className="h-3 w-3 rounded-full bg-emerald-300" />
              </div>
              <div className="absolute inset-0 grid place-items-center p-10">
                <div className="w-full rounded-2xl border border-black/10 bg-gradient-to-br from-white to-neutral-50 p-6 shadow-sm">
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="text-xs font-bold text-neutral-500">리포트</div>
                      <div className="mt-1 text-lg font-extrabold">매출/전환 대시보드</div>
                    </div>
                    <div className="rounded-full bg-black px-3 py-1 text-xs font-bold text-white">+300%</div>
                  </div>
                  <div className="mt-6 h-28 w-full rounded-xl bg-[linear-gradient(90deg,rgba(236,72,153,0.25),rgba(217,70,239,0.10))]" />
                  <div className="mt-3 grid grid-cols-3 gap-3">
                    {[
                      { k: "전환", v: "4.2%" },
                      { k: "매출", v: "₩12.4M" },
                      { k: "ROAS", v: "3.1" },
                    ].map((x) => (
                      <div key={x.k} className="rounded-xl border border-black/10 bg-white p-3">
                        <div className="text-[11px] font-bold text-neutral-500">{x.k}</div>
                        <div className="mt-1 text-sm font-extrabold text-neutral-900">{x.v}</div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>

            <div className="absolute -left-2 top-14 w-[240px] rounded-2xl border border-black/10 bg-white/90 p-4 shadow-lg backdrop-blur">
              <div className="text-xs font-extrabold text-neutral-900">판매량 급상승 감지</div>
              <div className="mt-2 text-xs text-neutral-600">‘강남역’ 키워드 트래픽 +18%</div>
              <div className="mt-3 h-2 w-full rounded-full bg-neutral-100">
                <div className="h-2 w-2/3 rounded-full bg-gradient-to-r from-fuchsia-500 to-pink-500" />
              </div>
            </div>

            <div className="absolute -right-2 top-24 w-[220px] rounded-2xl border border-black/10 bg-white/90 p-4 shadow-lg backdrop-blur">
              <div className="text-xs font-extrabold text-neutral-900">리스크 경고</div>
              <div className="mt-2 text-xs text-neutral-600">광고비 상승 구간 발견</div>
              <div className="mt-3 inline-flex rounded-full bg-neutral-900 px-3 py-1 text-xs font-bold text-white">
                체크 필요
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Feature tabs */}
      <section className="mx-auto max-w-6xl px-4 py-12">
        <div className="flex justify-center">
          <div className="inline-flex rounded-full border border-black/10 bg-white p-1 shadow-sm">
            {tabs.map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={cx(
                  "rounded-full px-4 py-2 text-sm font-extrabold transition",
                  tab === t
                    ? "bg-gradient-to-r from-fuchsia-600 to-pink-600 text-white shadow"
                    : "text-neutral-700 hover:bg-black/5",
                )}
              >
                {t}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-10 grid grid-cols-1 items-start gap-8 md:grid-cols-2">
          <div>
            <div className="inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-bold text-neutral-700 shadow-sm">
              <span className="h-1.5 w-1.5 rounded-full bg-fuchsia-500" />
              {tabCopy?.pill}
            </div>
            <h2 className="mt-4 whitespace-pre-line text-3xl font-black leading-tight tracking-tight md:text-4xl">
              {tabCopy?.title}
            </h2>
            <p className="mt-4 max-w-xl text-base font-medium leading-7 text-neutral-600">
              {tabCopy?.desc}
            </p>
          </div>

          <div className="rounded-3xl border border-black/10 bg-white p-6 shadow-[0_20px_60px_-30px_rgba(0,0,0,0.35)]">
            <div className="flex items-center justify-between">
              <div className="text-sm font-extrabold">프로젝트 요약 리포트</div>
              <div className="text-xs font-bold text-emerald-600">업데이트 완료</div>
            </div>
            <div className="mt-4 grid gap-3">
              {[
                { k: "추천 액션", v: "가격 3% 조정" },
                { k: "경쟁 강도", v: "중" },
                { k: "재고 리스크", v: "낮음" },
              ].map((x) => (
                <div key={x.k} className="rounded-2xl border border-black/10 bg-neutral-50 p-4">
                  <div className="text-xs font-bold text-neutral-500">{x.k}</div>
                  <div className="mt-1 text-base font-extrabold text-neutral-900">{x.v}</div>
                </div>
              ))}
            </div>
            <div className="mt-5 rounded-2xl bg-neutral-900 px-5 py-3 text-center text-sm font-extrabold text-white">
              요약 리포트 받기
            </div>
          </div>
        </div>
      </section>

      {/* Dark proof/video */}
      <section className="bg-neutral-950 py-14">
        <div className="mx-auto max-w-6xl px-4">
          <div className="grid grid-cols-1 gap-8 md:grid-cols-2 md:items-center">
            <div>
              <div className="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-bold text-white/80">
                실제 사용 데이터
              </div>
              <h3 className="mt-4 text-3xl font-black leading-tight tracking-tight text-white md:text-4xl">
                현업 전문가들은 이미
                <br />
                <span className="text-fuchsia-300">쿠팡</span>에서 답을 찾고 있습니다.
              </h3>
              <p className="mt-4 max-w-xl text-sm leading-6 text-white/70">
                성공 사례와 실전 운영 팁을 영상/문서로 제공합니다.
              </p>
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <div
                  key={i}
                  className="group relative aspect-[4/3] overflow-hidden rounded-2xl border border-white/10 bg-white/5 shadow"
                >
                  <div className="absolute inset-0 bg-gradient-to-br from-white/10 to-transparent" />
                  <div className="absolute bottom-3 left-3 right-3 text-xs font-bold text-white/85">
                    운영 팁 #{i + 1}
                  </div>
                  <div className="absolute right-3 top-3 rounded-full bg-white/10 px-2 py-1 text-[11px] font-bold text-white/80">
                    2:3{i}
                  </div>
                  <div className="absolute inset-0 grid place-items-center">
                    <div className="rounded-full bg-white/15 px-4 py-2 text-xs font-black text-white group-hover:bg-white/20">
                      ▶ 재생
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Metrics */}
      <section className="relative overflow-hidden py-16">
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute left-1/2 top-0 h-[520px] w-[520px] -translate-x-1/2 rounded-full bg-fuchsia-200/40 blur-3xl" />
        </div>

        <div className="mx-auto max-w-6xl px-4">
          <div className="inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-bold text-neutral-700 shadow-sm">
            ACTUAL USER DATA
          </div>
          <h4 className="mt-4 text-3xl font-black tracking-tight md:text-4xl">
            결과가
            <br />
            증명합니다.
          </h4>

          <div className="mt-10 grid grid-cols-1 gap-6 md:grid-cols-3">
            {[
              { k: "반품률", v: "0%" },
              { k: "추가 이익", v: "+0만원" },
              { k: "자동화", v: "ON" },
            ].map((x) => (
              <div
                key={x.k}
                className="rounded-3xl border border-black/10 bg-white p-6 shadow-[0_20px_60px_-30px_rgba(0,0,0,0.25)]"
              >
                <div className="text-sm font-bold text-neutral-500">{x.k}</div>
                <div className="mt-3 text-4xl font-black tracking-tight text-neutral-900">{x.v}</div>
                <div className="mt-3 text-sm text-neutral-600">
                  실제 사용자 데이터를 기반으로 일관된 개선을 제공합니다.
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Testimonials */}
      <section className="mx-auto max-w-6xl px-4 pb-20">
        <div className="text-center">
          <div className="inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-bold text-neutral-700 shadow-sm">
            REAL CHAT REVIEW
          </div>
          <h5 className="mt-4 text-2xl font-black tracking-tight md:text-3xl">
            성공한 대표님들의
            <br />
            생생한 후기만 가져다 씁니다.
          </h5>
        </div>

        <div className="mt-10 grid grid-cols-1 gap-5 md:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="h-40 rounded-3xl border border-black/10 bg-neutral-50 p-5"
            >
              <div className="h-4 w-24 rounded bg-neutral-200" />
              <div className="mt-3 h-3 w-40 rounded bg-neutral-200" />
              <div className="mt-2 h-3 w-32 rounded bg-neutral-200" />
              <div className="mt-8 h-9 w-9 rounded-full bg-neutral-200" />
            </div>
          ))}
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-black/5 bg-white py-10">
        <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 md:flex-row md:items-center md:justify-between">
          <div className="flex items-center gap-2 font-black">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-xl bg-gradient-to-br from-fuchsia-500 to-pink-500 text-white">
              C
            </span>
            <span>COUPILOT</span>
          </div>
          <div className="text-sm text-neutral-600">
            © {new Date().getFullYear()} Coupang Elephant. All rights reserved.
          </div>
        </div>
      </footer>
    </div>
  );
}
