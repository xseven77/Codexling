import { GITHUB_RELEASES_URL } from "@/lib/github";
import Image from "next/image";
import { MenuBarPreview } from "./MenuBarPreview";

export function Hero() {
  return (
    <section className="relative overflow-hidden" aria-labelledby="hero-heading">
      <div className="hero-glow absolute inset-0" />
      <div className="grid-bg absolute inset-0 opacity-40" />

      <div className="relative mx-auto grid max-w-6xl gap-12 px-6 py-20 lg:grid-cols-[1.05fr_0.95fr] lg:items-center lg:py-28">
        <div>
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-border bg-surface/80 px-3 py-1 text-xs text-muted backdrop-blur">
            <span className="h-2 w-2 rounded-full bg-accent animate-pulse-soft" />
            macOS 菜单栏 · 官方 OAuth 登录
          </div>

          <h1
            id="hero-heading"
            className="text-4xl font-semibold leading-[1.08] tracking-tight sm:text-5xl lg:text-[3.25rem]"
          >
            <span className="block whitespace-nowrap">在菜单栏一眼看清</span>
            <span className="block whitespace-nowrap bg-gradient-to-r from-foreground to-accent bg-clip-text text-transparent">
              Codex 额度与重置时间
            </span>
          </h1>

          <p className="mt-6 max-w-xl text-lg leading-8 text-muted">
            Codex Light 是一款轻量 macOS 状态栏应用。通过 OpenAI 官方授权登录，实时展示
            5 小时额度、周额度、credits 与重置券，不保存密码，不绕过 MFA。
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <a
              href={GITHUB_RELEASES_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full bg-foreground px-6 py-3 text-sm font-medium text-background transition-transform hover:scale-[1.02]"
            >
              前往 GitHub 下载
              <span aria-hidden>↗</span>
            </a>
            <a
              href="https://github.com/xseven77/codex-light"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full border border-border px-6 py-3 text-sm transition-colors hover:bg-foreground/5"
            >
              查看源码
            </a>
          </div>

          <div className="mt-10 flex flex-wrap gap-6 text-sm text-muted">
            <div className="flex items-center gap-2">
              <Image
                src="/logo.svg"
                alt="Codex Light logo"
                width={18}
                height={18}
                className="rounded-[4px]"
              />
              Swift + SwiftUI
            </div>
            <div>Keychain 存储 Token</div>
            <div>本地缓存快照</div>
          </div>
        </div>

        <div className="animate-float">
          <MenuBarPreview />
        </div>
      </div>
    </section>
  );
}
