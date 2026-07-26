"use client";

import Image from "next/image";
import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

const MOBILE_PREVIEW_WIDTH = 560;

function Ring({
  percent,
  color,
}: {
  percent: number;
  color: string;
}) {
  return (
    <div
      className="h-10 w-10 shrink-0 rounded-full"
      style={{
        background: `conic-gradient(${color} ${percent}%, var(--preview-track) 0)`,
        padding: "5px",
      }}
    >
      <div className="h-full w-full rounded-full bg-[var(--preview-card)]" />
    </div>
  );
}

function QuotaCard({
  label,
  percent,
  color,
}: {
  label: string;
  percent: number;
  color: string;
}) {
  return (
    <div className="flex min-w-0 flex-1 items-center gap-2.5 rounded-[12px] border border-[color:var(--preview-line)] bg-[var(--preview-card)] px-3 py-2.5">
      <Ring percent={percent} color={color} />
      <div className="min-w-0">
        <div className="text-[20px] font-bold leading-none tabular-nums text-[var(--preview-ink)]">
          {percent}%
        </div>
        <div className="mt-1 text-[10px] font-medium text-[var(--preview-muted)]">{label}</div>
      </div>
    </div>
  );
}

function IconButton({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div
      aria-hidden
      title={label}
      className="flex h-9 w-9 items-center justify-center rounded-[10px] bg-[var(--preview-icon-bg)] text-[var(--preview-muted)]"
    >
      {children}
    </div>
  );
}

function ResetTicket() {
  return (
    <div className="relative mt-4 h-[84px]">
      <div className="absolute inset-x-2 bottom-0 top-3 rounded-[13px] border border-[color:var(--preview-line)] bg-[var(--preview-ticket-back)]" />
      <div className="absolute inset-x-1 bottom-1.5 top-1.5 rounded-[13px] border border-[color:var(--preview-line)] bg-[var(--preview-ticket-mid)]" />
      <div className="absolute inset-x-0 top-0 flex h-[70px] items-center rounded-[13px] border border-[color:var(--preview-line)] bg-[linear-gradient(135deg,var(--preview-ticket-face),var(--preview-card))] px-3.5 shadow-[var(--preview-card-shadow)]">
        <span className="absolute -left-1.5 h-3 w-3 rounded-full bg-[var(--preview-panel)]" />
        <span className="absolute -right-1.5 h-3 w-3 rounded-full bg-[var(--preview-panel)]" />
        <div className="mr-3 flex h-9 w-9 shrink-0 items-center justify-center rounded-[11px] bg-[var(--preview-green-soft)] text-base text-[var(--preview-green)]">
          ↻
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <span className="truncate text-[12px] font-semibold text-[var(--preview-ink)]">
              重置券
            </span>
            <span className="rounded-full bg-[var(--preview-green-soft)] px-1.5 py-0.5 text-[9px] font-bold text-[var(--preview-green)]">
              1 / 3
            </span>
          </div>
          <div className="mt-1.5 truncate text-[9px] font-medium tabular-nums text-[var(--preview-muted)]">
            7月27日 07:34 到期
          </div>
        </div>
        <div className="ml-2 border-l-2 border-dotted border-[color:var(--preview-line)] pl-2.5 text-center text-[var(--preview-green)]">
          <div className="rounded-[5px] border border-dashed border-[color:var(--preview-green)]/50 bg-[var(--preview-green-soft)] px-2 py-1 text-[9px] font-bold">
            ▣　01
          </div>
          <div className="mt-1 text-[8px] font-semibold text-[var(--preview-muted)]">切换查看</div>
          <div className="text-[7.5px] text-[var(--preview-muted)]">available</div>
        </div>
      </div>
    </div>
  );
}

export function MenuBarPreview() {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLDivElement>(null);
  const [mobileLayout, setMobileLayout] = useState<{ scale: number; height: number } | null>(null);

  useLayoutEffect(() => {
    const wrapper = wrapperRef.current;
    const canvas = canvasRef.current;
    if (!wrapper || !canvas) return;

    const updateScale = () => {
      if (!window.matchMedia("(max-width: 639px)").matches) {
        setMobileLayout(null);
        return;
      }

      const scale = Math.min(1, wrapper.clientWidth / MOBILE_PREVIEW_WIDTH);
      const height = canvas.offsetHeight * scale;
      setMobileLayout((current) => {
        if (
          current &&
          Math.abs(current.scale - scale) < 0.001 &&
          Math.abs(current.height - height) < 0.5
        ) {
          return current;
        }
        return { scale, height };
      });
    };

    updateScale();
    const observer = new ResizeObserver(updateScale);
    observer.observe(wrapper);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={wrapperRef}
      className="relative w-full max-sm:aspect-[560/499]"
      style={mobileLayout ? { height: mobileLayout.height, aspectRatio: "auto" } : undefined}
    >
      <div
        ref={canvasRef}
        className="overflow-hidden rounded-[24px] border border-[color:var(--preview-frame-border)] bg-[var(--preview-bg)] shadow-[var(--preview-shadow)] max-sm:w-[560px] sm:w-full"
        style={
          mobileLayout
            ? {
                transform: `scale(${mobileLayout.scale})`,
                transformOrigin: "top left",
              }
            : undefined
        }
        aria-hidden
      >
        <div className="border-b border-[color:var(--preview-hairline)] bg-[var(--preview-menubar-bg)] px-3 py-1.5 backdrop-blur-xl">
        <div className="flex items-center justify-between gap-2 text-[9px] text-[var(--preview-menubar-fg)]">
          <div className="flex min-w-0 shrink gap-2">
            <span className="shrink-0"></span>
            <span>Finder</span>
            <span>文件</span>
          </div>
          <div className="flex min-w-0 items-center justify-end gap-2">
            <span className="inline-flex h-6 min-w-[120px] max-w-[190px] items-center justify-center gap-1.5 truncate rounded-full bg-[var(--preview-status-pill)] px-2.5 text-[10px] font-bold tracking-[0.01em] text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.48),0_1px_3px_rgba(0,0,0,0.14)] [text-shadow:0_1px_1px_rgba(0,0,0,0.22)]">
              <span className="h-2 w-2 shrink-0 rounded-full bg-[#7c3cff] shadow-[0_0_0_1px_white,0_0_5px_rgba(255,255,255,0.95)]" />
              <span className="truncate">思考中 · 周 95%</span>
            </span>
            <span className="shrink-0">Wed 17:57</span>
          </div>
        </div>
      </div>

        <div className="grid h-[462px] grid-cols-[31%_69%] bg-[var(--preview-panel)]">
        <aside className="relative flex min-w-0 flex-col border-r border-[color:var(--preview-line)] bg-[var(--preview-sidebar)] px-3.5 pb-4 pt-3">
          <div className="flex gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
          </div>

          <div className="mt-5 min-w-0">
            <div className="flex items-center gap-1.5">
              <span className="truncate text-[13px] font-bold text-[var(--preview-ink)]">seven x</span>
              <span className="rounded-[5px] bg-[var(--preview-green-soft)] px-1.5 py-0.5 text-[8px] font-bold text-[var(--preview-green)]">
                plus
              </span>
            </div>
            <div className="mt-1 truncate text-[9px] text-[var(--preview-muted)]">xujinqi7@gmail.com</div>
            <div className="mt-2.5 border-t border-[color:var(--preview-line)] pt-2.5 text-[8.5px] font-medium text-[var(--preview-muted)]">
              8月21日 14:22 · 自动续费 ↗
            </div>
          </div>

          <div className="flex flex-1 items-center justify-center">
            <Image
              src="/brand/codexling-logo.webp"
              alt=""
              width={128}
              height={128}
              className="h-auto w-[70%] max-w-[118px] drop-shadow-[0_14px_16px_rgba(0,0,0,0.18)]"
            />
          </div>

          <div className="mx-auto flex max-w-full items-center gap-1.5 rounded-full border border-[color:var(--preview-line)] bg-[var(--preview-card)] px-2.5 py-1.5">
            <span className="h-2 w-2 shrink-0 rounded-full bg-[#7c3cff]" />
            <span className="truncate text-[9px] font-semibold text-[var(--preview-ink)]">
              Codexling · 正在思考
            </span>
          </div>
          <div className="mt-2 text-center text-[9px] text-[var(--preview-muted)]">
            今天一起工作 17 分钟
          </div>
        </aside>

        <main className="flex min-w-0 flex-col px-4 pb-3 pt-4">
          <div className="flex items-center justify-between gap-2">
            <div className="min-w-0">
              <h3 className="truncate text-[18px] font-bold leading-tight text-[var(--preview-ink)]">
                正在处理 1 个任务
              </h3>
            </div>
            <div className="inline-flex h-7 shrink-0 items-center gap-1.5 rounded-full border border-[color:var(--preview-green)]/25 bg-[var(--preview-green-soft)] px-2.5 text-[10px] font-bold text-[var(--preview-green)]">
              <span className="h-1.5 w-1.5 rounded-full bg-[var(--preview-green)]" />
              本周 95%
            </div>
          </div>

          <div className="mt-3 rounded-[13px] border border-[color:var(--preview-line)] bg-[var(--preview-card)] px-3 py-2.5">
            <div className="flex items-center justify-between gap-2 text-[9px]">
              <span className="font-semibold text-[#7c3cff]">●　思考中</span>
              <span className="text-[var(--preview-muted)]">任务 1 / 1</span>
            </div>
            <div className="mt-2 truncate text-[13px] font-bold text-[var(--preview-ink)]">评估并更新 Codexling UI</div>
            <div className="mt-1 truncate text-[10px] text-[var(--preview-muted)]">正在运行本地命令</div>
            <div className="mt-2 flex items-center gap-3 truncate text-[8.5px] font-medium text-[var(--preview-muted)]">
              <span>▱　Codexling</span>
              <span>⑂　main</span>
              <span>▣　gpt-5.6-sol</span>
            </div>
            <div className="mt-2 flex items-center justify-between border-t border-[color:var(--preview-line)] pt-1.5 text-[8.5px] text-[var(--preview-muted)]">
              <span>分析任务</span>
              <span>更新于刚刚</span>
            </div>
          </div>

          <div className="mt-3 flex items-center justify-between">
            <span className="text-[12px] font-bold text-[var(--preview-ink)]">额度</span>
            <span className="text-[9px] text-[var(--preview-muted)]">额度重置：7月27日 23:59</span>
          </div>
          <div className="mt-2 flex gap-2">
            <QuotaCard label="5 小时" percent={77} color="var(--preview-green)" />
            <QuotaCard label="本周" percent={95} color="var(--preview-green)" />
          </div>

          <ResetTicket />

          <div className="mt-auto flex items-center justify-between border-t border-[color:var(--preview-line)] pt-3.5">
            <span className="truncate text-[9px] text-[var(--preview-muted)]">上次同步：今天 17:48</span>
            <div className="flex shrink-0 gap-2">
              <IconButton label="设置">
                <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="3" />
                  <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.12 2.12-.06-.06a1.7 1.7 0 0 0-1.88-.34 1.7 1.7 0 0 0-1.03 1.55V20.3h-3v-.09a1.7 1.7 0 0 0-1.03-1.55 1.7 1.7 0 0 0-1.88.34l-.06.06-2.12-2.12.06-.06A1.7 1.7 0 0 0 7 15a1.7 1.7 0 0 0-1.55-1.03H5.3v-3h.15A1.7 1.7 0 0 0 7 9.94a1.7 1.7 0 0 0-.34-1.88L6.6 8l2.12-2.12.06.06a1.7 1.7 0 0 0 1.88.34A1.7 1.7 0 0 0 11.7 4.7V4.6h3v.1a1.7 1.7 0 0 0 1.03 1.55 1.7 1.7 0 0 0 1.88-.34l.06-.06L19.8 8l-.06.06a1.7 1.7 0 0 0-.34 1.88A1.7 1.7 0 0 0 20.95 11h.15v3h-.15A1.7 1.7 0 0 0 19.4 15Z" />
                </svg>
              </IconButton>
              <IconButton label="官方 Usage">
                <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <rect x="4" y="4" width="16" height="16" rx="3" />
                  <path d="M10 14 16 8M11 8h5v5" />
                </svg>
              </IconButton>
              <IconButton label="退出">
                <svg viewBox="0 0 24 24" className="h-[19px] w-[19px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                  <path d="M12 3v9" />
                  <path d="M7.05 5.95a8 8 0 1 0 9.9 0" />
                </svg>
              </IconButton>
              <div className="flex h-9 items-center justify-center rounded-[10px] bg-[var(--preview-primary)] px-4 text-[10px] font-bold text-[var(--preview-on-primary)]">
                立即刷新
              </div>
            </div>
          </div>
        </main>
        </div>
      </div>
    </div>
  );
}
