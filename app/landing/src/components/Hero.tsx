import { GITHUB_RELEASES_URL } from "@/lib/github";
import Image from "next/image";
import { MenuBarPreview } from "./MenuBarPreview";

export function Hero() {
  return (
    <section className="relative overflow-hidden" aria-labelledby="hero-heading">
      <div className="hero-glow absolute inset-0" />
      <div className="grid-bg absolute inset-0 opacity-40" />

      <div className="relative mx-auto grid max-w-6xl gap-10 px-4 py-14 sm:gap-12 sm:px-6 sm:py-20 lg:grid-cols-[1.05fr_0.95fr] lg:items-center lg:py-28">
        <div className="min-w-0">
          <div className="mb-5 inline-flex max-w-full items-center gap-2 rounded-full border border-border bg-surface/80 px-3 py-1 text-xs text-muted backdrop-blur sm:mb-6">
            <span className="h-2 w-2 shrink-0 rounded-full bg-accent animate-pulse-soft" />
            <span className="truncate">macOS 菜单栏 · 官方 OAuth 登录</span>
          </div>

          <h1
            id="hero-heading"
            className="text-[1.75rem] font-semibold leading-[1.12] tracking-tight sm:text-5xl sm:leading-[1.08] lg:text-[3.25rem]"
          >
            <span className="block sm:whitespace-nowrap">在菜单栏一眼看清</span>
            <span className="block bg-gradient-to-r from-foreground to-accent bg-clip-text text-transparent sm:whitespace-nowrap">
              Codex 额度与重置时间
            </span>
          </h1>

          <p className="mt-5 max-w-xl text-base leading-7 text-muted sm:mt-6 sm:text-lg sm:leading-8">
            Codex Light 是一款轻量 macOS 状态栏应用。通过 OpenAI 官方授权登录，实时展示
            5 小时额度、周额度、credits 与重置券，不保存密码，不绕过 MFA。
          </p>

          <div className="mt-7 flex flex-col gap-3 sm:mt-8 sm:flex-row sm:flex-wrap sm:items-center sm:gap-4">
            <a
              href={GITHUB_RELEASES_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 rounded-full bg-foreground px-6 py-3 text-sm font-medium text-background transition-transform hover:scale-[1.02] active:scale-[0.98]"
            >
              前往 GitHub 下载
              <span aria-hidden>↗</span>
            </a>
            <a
              href="https://github.com/xseven77/codex-light"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 rounded-full border border-border px-6 py-3 text-sm transition-colors hover:bg-foreground/5 active:bg-foreground/10"
            >
              查看源码
            </a>
          </div>

          <div className="mt-8 grid gap-3 text-sm text-muted sm:mt-10 sm:flex sm:flex-wrap sm:gap-6">
            <div className="flex items-center gap-2">
              <Image
                src="/logo.svg"
                alt="Codex Light logo"
                width={18}
                height={18}
                className="shrink-0 rounded-[4px]"
              />
              Swift + SwiftUI
            </div>
            <div>Keychain 存储 Token</div>
            <div>本地缓存快照</div>
          </div>
        </div>

        <div className="min-w-0 max-sm:animate-none sm:animate-float">
          <MenuBarPreview />
        </div>
      </div>
    </section>
  );
}
