import { GITHUB_RELEASES_URL } from "@/lib/github";
import Image from "next/image";
import Link from "next/link";
import { ThemeToggle } from "./ThemeToggle";

const nav = [
  { href: "#features", label: "功能" },
  { href: "#how-it-works", label: "原理" },
  { href: "#github", label: "GitHub" },
  { href: "#releases", label: "Releases" },
];

export function Header() {
  return (
    <header className="sticky top-0 z-50 border-b border-border/80 bg-background/70 backdrop-blur-xl">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="flex items-center gap-3">
          <Image
            src="/logo.svg"
            alt="Codex Light"
            width={32}
            height={32}
            className="rounded-[8px]"
          />
          <span className="text-sm font-semibold tracking-tight">Codex Light</span>
        </Link>

        <nav className="hidden items-center gap-8 md:flex">
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

        <div className="flex items-center gap-3">
          <ThemeToggle />
          <a
            href="https://github.com/xseven77/codex-light"
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
            className="rounded-full bg-foreground px-4 py-2 text-sm font-medium text-background transition-opacity hover:opacity-90"
          >
            下载
          </a>
        </div>
      </div>
    </header>
  );
}
