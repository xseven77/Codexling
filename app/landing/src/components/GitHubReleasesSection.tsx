import type { GitHubRelease } from "@/lib/github";
import { formatDate, GITHUB_RELEASES_URL } from "@/lib/github";

export function GitHubReleasesSection({ releases }: { releases: GitHubRelease[] }) {
  const latest = releases[0];

  return (
    <section id="releases" className="border-t border-border/70 bg-surface/40">
      <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-24">
        <div className="mb-8 flex flex-col gap-5 sm:mb-10 sm:flex-row sm:flex-wrap sm:items-end sm:justify-between sm:gap-6">
          <div className="max-w-2xl">
            <p className="text-sm font-medium uppercase tracking-[0.2em] text-accent">
              Releases
            </p>
            <h2 className="mt-3 text-2xl font-semibold tracking-tight sm:text-4xl">
              GitHub Releases 预览
            </h2>
            <p className="mt-4 text-base text-muted sm:text-lg">
              安装包统一在 GitHub Releases 发布与下载。Landing 只做页面预览，点击后跳转到官方
              Release 页面。
            </p>
          </div>

          <a
            href={GITHUB_RELEASES_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex w-full items-center justify-center rounded-full bg-accent px-5 py-3 text-sm font-medium text-black transition-transform hover:scale-[1.02] active:scale-[0.98] sm:w-auto"
          >
            在 GitHub 打开 Releases
          </a>
        </div>

        <div className="overflow-hidden rounded-2xl border border-[var(--github-border)] bg-[var(--github-bg)] shadow-[0_30px_80px_rgba(0,0,0,0.35)] sm:rounded-[28px]">
          <div className="flex items-center gap-2 border-b border-[var(--github-border)] bg-[#010409] px-4 py-3">
            <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
            <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
            <span className="h-3 w-3 rounded-full bg-[#28c840]" />
            <span className="ml-3 truncate text-xs text-[var(--github-muted)]">
              github.com/xseven77/Codexling/releases
            </span>
          </div>

          <div className="border-b border-[var(--github-border)] px-5 py-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h3 className="text-lg font-semibold text-white">Releases</h3>
              <span className="text-sm text-[var(--github-muted)]">
                {releases.length} releases
              </span>
            </div>
          </div>

          <div className="divide-y divide-[var(--github-border)]">
            {releases.map((release) => (
              <article
                key={release.tagName}
                className="grid gap-3 px-4 py-5 sm:gap-4 sm:px-5 sm:py-6 lg:grid-cols-[180px_1fr]"
              >
                <div>
                  <div className="text-sm text-[var(--github-muted)]">
                    {formatDate(release.publishedAt)}
                  </div>
                  <div className="mt-2 flex items-center gap-2">
                    <span className="font-mono text-sm text-[#58a6ff]">{release.tagName}</span>
                    {release.isLatest && (
                      <span className="rounded-full border border-[#238636] bg-[#238636]/20 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-[#3fb950]">
                        Latest
                      </span>
                    )}
                  </div>
                </div>

                <div>
                  <h4 className="text-lg font-semibold text-white sm:text-xl">{release.name}</h4>
                  <p className="mt-2 text-sm text-[var(--github-muted)]">
                    包含 DMG 与 ZIP 安装包，请在 GitHub Release 页面下载。
                  </p>
                </div>
              </article>
            ))}
          </div>

          <div className="border-t border-[var(--github-border)] bg-[#161b22] px-4 py-4 sm:px-5 sm:py-5">
            <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between sm:gap-4">
              <div className="text-sm text-[var(--github-muted)]">
                {latest
                  ? `最新版本 ${latest.tagName} · 点击前往 GitHub 下载`
                  : "前往 GitHub 查看所有版本"}
              </div>
              <a
                href={latest?.url ?? GITHUB_RELEASES_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex w-full items-center justify-center rounded-lg bg-[var(--github-green)] px-4 py-2.5 text-sm font-medium text-white transition-opacity hover:opacity-90 sm:w-auto"
              >
                查看 Release 详情
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
