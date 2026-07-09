"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useTheme, type ThemeName } from "./ThemeProvider";

function SunIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" />
    </svg>
  );
}

function MoonIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden>
      <path d="M21 14.5A8.5 8.5 0 0 1 9.5 3 7 7 0 1 0 21 14.5Z" />
    </svg>
  );
}

function MonitorIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden>
      <rect x="3" y="4" width="18" height="12" rx="2" />
      <path d="M8 20h8M12 16v4" />
    </svg>
  );
}

function CheckIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="2.5" aria-hidden>
      <path d="M5 12l5 5L20 7" />
    </svg>
  );
}

const OPTIONS: { value: ThemeName; label: string; Icon: typeof SunIcon }[] = [
  { value: "system", label: "跟随系统", Icon: MonitorIcon },
  { value: "light", label: "浅色", Icon: SunIcon },
  { value: "dark", label: "深色", Icon: MoonIcon },
];

export function ThemeToggle({ className = "" }: { className?: string }) {
  const { theme, setTheme, resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const listId = useId();

  useEffect(() => setMounted(true), []);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    const onEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    document.addEventListener("keydown", onEsc);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      document.removeEventListener("keydown", onEsc);
    };
  }, [open]);

  if (!mounted) {
    return (
      <span
        className={`inline-flex size-8 shrink-0 rounded-[10px] bg-black/[0.05] dark:bg-white/[0.08] ${className}`}
        aria-hidden
      />
    );
  }

  const TriggerIcon =
    theme === "system" ? MonitorIcon : resolvedTheme === "dark" ? MoonIcon : SunIcon;

  const pick = (next: ThemeName) => {
    setTheme(next);
    setOpen(false);
  };

  return (
    <div ref={containerRef} className={`relative ${className}`}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-controls={open ? listId : undefined}
        title="选择主题"
        aria-label="选择主题"
        className={[
          "inline-flex size-8 shrink-0 items-center justify-center rounded-[10px]",
          "bg-black/[0.05] text-foreground/80 ring-1 ring-black/[0.06]",
          "transition-[transform,background-color] duration-150 ease-out",
          "hover:bg-black/[0.08] active:scale-[0.97]",
          "dark:bg-white/[0.08] dark:text-white/90 dark:ring-white/[0.12]",
          "dark:hover:bg-white/[0.12]",
          open ? "bg-black/[0.08] ring-black/[0.1] dark:bg-white/[0.12]" : "",
        ].join(" ")}
      >
        <TriggerIcon className="size-[15px] shrink-0 opacity-90" />
      </button>

      {open ? (
        <div
          id={listId}
          role="listbox"
          aria-label="选择主题"
          className={[
            "absolute right-0 top-[calc(100%+6px)] z-50 min-w-[10.5rem] overflow-hidden rounded-[12px] p-1",
            "border border-black/[0.06] bg-white/95 shadow-[0_8px_30px_rgba(0,0,0,0.12),0_2px_8px_rgba(0,0,0,0.06)] backdrop-blur-xl",
            "dark:border-white/[0.12] dark:bg-zinc-900/95 dark:shadow-[0_12px_40px_rgba(0,0,0,0.45)]",
          ].join(" ")}
        >
          {OPTIONS.map(({ value, label, Icon }) => {
            const active = theme === value;
            return (
              <button
                key={value}
                type="button"
                role="option"
                aria-selected={active}
                onClick={() => pick(value)}
                className={[
                  "flex w-full items-center gap-2 rounded-[8px] px-2.5 py-2 text-left text-[13px] font-medium leading-none",
                  "transition-colors duration-150",
                  active
                    ? "bg-black/[0.06] text-foreground dark:bg-white/[0.12] dark:text-white"
                    : "text-muted hover:bg-black/[0.04] hover:text-foreground dark:hover:bg-white/[0.08] dark:hover:text-white",
                ].join(" ")}
              >
                <Icon className="size-3.5 shrink-0 opacity-80" />
                <span className="min-w-0 flex-1">{label}</span>
                {active ? <CheckIcon className="size-3.5 shrink-0 opacity-80" /> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
