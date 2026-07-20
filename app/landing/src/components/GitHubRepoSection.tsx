import type { GitHubRepo } from "@/lib/github";
import { formatRelative } from "@/lib/github";

const tree = [
  { name: "app/Codexling", type: "dir" },
  { name: "docs", type: "dir" },
  { name: "README.md", type: "file" },
  { name: "PROJECT.md", type: "file" },
  { name: "ui-concepts.html", type: "file" },
];

export function GitHubRepoSection({ repo }: { repo: GitHubRepo }) {
  return (
    <section id="github" className="mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-24">
      <div className="mb-8 max-w-2xl sm:mb-10">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-accent">
          Open Source
        </p>
        <h2 className="mt-3 text-2xl font-semibold tracking-tight sm:text-4xl">
          GitHub 仓库预览
        </h2>
        <p className="mt-4 text-base text-muted sm:text-lg">
          仿 GitHub 仓库页的信息架构，展示项目结构、语言与最近更新时间。
        </p>
      </div>

      <div className="overflow-hidden rounded-2xl border border-[var(--github-border)] bg-[var(--github-bg)] shadow-[0_30px_80px_rgba(0,0,0,0.35)] sm:rounded-[28px]">
        <div className="border-b border-[var(--github-border)] px-4 py-4 sm:px-5">
          <div className="flex flex-col gap-4 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
            <div className="flex min-w-0 flex-wrap items-center gap-2 text-[var(--github-text)]">
              <span className="text-[var(--github-muted)]">📁</span>
              <a
                href={repo.url}
                target="_blank"
                rel="noopener noreferrer"
                className="break-all text-lg font-semibold hover:underline sm:text-xl"
              >
                {repo.fullName}
              </a>
              <span className="rounded-full border border-[var(--github-border)] px-2 py-0.5 text-xs text-[var(--github-muted)]">
                Public
              </span>
            </div>

            <div className="flex flex-wrap gap-2 text-xs sm:text-sm">
              <span className="rounded-md border border-[var(--github-border)] px-3 py-1.5 text-[var(--github-muted)]">
                ★ Star {repo.stars}
              </span>
              <span className="rounded-md border border-[var(--github-border)] px-3 py-1.5 text-[var(--github-muted)]">
                Fork {repo.forks}
              </span>
              <a
                href={repo.url}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-md bg-[var(--github-green)] px-3 py-1.5 font-medium text-white"
              >
                Code
              </a>
            </div>
          </div>

          <p className="mt-3 max-w-3xl text-sm text-[var(--github-muted)]">
            {repo.description}
          </p>

          <div className="mt-3 flex flex-wrap gap-2 text-xs text-[var(--github-muted)] sm:gap-3">
            <span className="rounded-full bg-white/5 px-2 py-1">{repo.language}</span>
            <span>Updated {formatRelative(repo.updatedAt)}</span>
            <span>Default branch: {repo.defaultBranch}</span>
          </div>
        </div>

        <div className="grid lg:grid-cols-[280px_1fr]">
          <aside className="border-b border-[var(--github-border)] p-4 sm:p-5 lg:border-b-0 lg:border-r">
            <div className="text-xs font-semibold uppercase tracking-wider text-[var(--github-muted)]">
              About
            </div>
            <p className="mt-3 text-sm leading-6 text-[var(--github-text)]">
              macOS menu bar app for Codex usage. Built with SwiftUI, OAuth PKCE, and
              Keychain token storage.
            </p>
            <div className="mt-4 space-y-2 text-sm text-[var(--github-muted)]">
              <div>🔒 Official OpenAI login only</div>
              <div>📦 DMG + ZIP releases</div>
              <div>🍎 macOS 13+</div>
            </div>
          </aside>

          <div className="p-4 sm:p-5">
            <div className="mb-4 flex flex-col gap-1 text-sm text-[var(--github-muted)] sm:flex-row sm:items-center sm:justify-between">
              <span>README.md</span>
              <span>Latest commit · {formatRelative(repo.updatedAt)}</span>
            </div>

            <div className="overflow-hidden rounded-xl border border-[var(--github-border)]">
              {tree.map((item) => (
                <div
                  key={item.name}
                  className="flex items-center justify-between border-b border-[var(--github-border)] px-4 py-3 last:border-b-0"
                >
                  <div className="flex items-center gap-3 text-sm text-[var(--github-text)]">
                    <span>{item.type === "dir" ? "📁" : "📄"}</span>
                    <span>{item.name}</span>
                  </div>
                  <span className="text-xs text-[var(--github-muted)]">
                    {item.type === "dir" ? "folder" : "file"}
                  </span>
                </div>
              ))}
            </div>

            <div className="mt-5 rounded-xl border border-[var(--github-border)] bg-[#161b22] p-5 text-sm leading-7 text-[var(--github-text)]">
              <h3 className="text-lg font-semibold text-white">Codexling</h3>
              <p className="mt-3 text-[var(--github-muted)]">
                Show Codex short-window and weekly usage in the macOS menu bar. Click to
                open a detail panel with credits, reset coupons, expiration times, and
                refresh status.
              </p>
              <pre className="mt-4 overflow-x-auto rounded-lg bg-[#0d1117] p-4 text-xs text-[#7ee787]">
{`cd app/Codexling
./package_app.sh
open "dist/Codexling.app"`}
              </pre>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
