"use client";

import { GITHUB_RELEASES_URL } from "@/lib/github";
import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ThemeToggle } from "./ThemeToggle";

const nav = [
  { href: "#features", label: "功能" },
  { href: "#how-it-works", label: "原理" },
  { href: "#github", label: "GitHub" },
  { href: "#releases", label: "Releases" },
];

function MenuIcon({ open }: { open: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className="size-5"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      aria-hidden
    >
      {open ? (
        <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
      ) : (
        <>
          <path d="M4 7h16M4 12h16M4 17h16" strokeLinecap="round" />
        </>
      )}
    </svg>
  );
}

export function Header() {
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    document.body.style.overflow = menuOpen ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [menuOpen]);

  const closeMenu = () => setMenuOpen(false);

  return (
    <header className="sticky top-0 z-50 border-b border-border/80 bg-background/70 backdrop-blur-xl supports-[padding:max(0px)]:pt-[env(safe-area-inset-top)]">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-3 px-4 sm:h-16 sm:px-6">
        <Link href="/" className="flex min-w-0 items-center gap-2.5 sm:gap-3">
          <Image
            src="/brand/codexling-logo.webp"
            alt="Codexling"
            width={32}
            height={32}
            className="shrink-0 rounded-[8px]"
          />
          <span className="truncate text-sm font-semibold tracking-tight">Codexling</span>
        </Link>

        <nav className="hidden items-center gap-8 md:flex" aria-label="主导航">
          {nav.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="text-sm text-muted transition-colors hover:text-foreground"
            >
              {item.label}
            </a>
          ))}
        </nav>

        <div className="flex shrink-0 items-center gap-2 sm:gap-3">
          <ThemeToggle />
          <a
            href="https://github.com/xseven77/Codexling"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden rounded-full border border-border px-4 py-2 text-sm transition-colors hover:bg-foreground/5 sm:inline-flex"
          >
            GitHub
          </a>
          <a
            href={GITHUB_RELEASES_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="hidden rounded-full bg-foreground px-4 py-2 text-sm font-medium text-background transition-opacity hover:opacity-90 sm:inline-flex"
          >
            下载
          </a>
          <button
            type="button"
            className="inline-flex size-9 items-center justify-center rounded-[10px] border border-border text-foreground transition-colors hover:bg-foreground/5 md:hidden"
            aria-expanded={menuOpen}
            aria-controls="mobile-nav"
            aria-label={menuOpen ? "关闭菜单" : "打开菜单"}
            onClick={() => setMenuOpen((v) => !v)}
          >
            <MenuIcon open={menuOpen} />
          </button>
        </div>
      </div>

      {menuOpen ? (
        <div
          id="mobile-nav"
          className="border-t border-border/80 bg-background/95 backdrop-blur-xl md:hidden"
        >
          <nav className="mx-auto flex max-w-6xl flex-col px-4 py-3 sm:px-6" aria-label="移动端导航">
            {nav.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className="rounded-xl px-3 py-3.5 text-base text-foreground transition-colors active:bg-foreground/5"
                onClick={closeMenu}
              >
                {item.label}
              </a>
            ))}
            <div className="mt-2 flex flex-col gap-2 border-t border-border/70 pt-3">
              <a
                href="https://github.com/xseven77/Codexling"
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-xl border border-border px-4 py-3 text-center text-sm transition-colors active:bg-foreground/5"
                onClick={closeMenu}
              >
                GitHub 仓库
              </a>
              <a
                href={GITHUB_RELEASES_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-xl bg-foreground px-4 py-3 text-center text-sm font-medium text-background"
                onClick={closeMenu}
              >
                前往下载
              </a>
            </div>
          </nav>
        </div>
      ) : null}
    </header>
  );
}
