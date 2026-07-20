import { GITHUB_RELEASES_URL, GITHUB_REPO_URL } from "./github";

export const siteConfig = {
  name: "Codexling",
  title: "Codexling — macOS 菜单栏 Codex 额度工具",
  description:
    "Codexling 是 macOS 菜单栏应用，通过 OpenAI 官方 OAuth 登录，在状态栏实时查看 Codex 5 小时额度、周额度、credits 与重置券。开源、隐私优先、不保存密码。",
  shortDescription:
    "在 macOS 菜单栏一眼看清 Codex 额度与重置时间。官方 OAuth 登录，开源可审计。",
  url: process.env.NEXT_PUBLIC_SITE_URL ?? "https://codexling.qiizo.cn",
  locale: "zh_CN",
  author: "xseven77",
  keywords: [
    "Codexling",
    "Codex",
    "OpenAI Codex",
    "ChatGPT Codex",
    "macOS 菜单栏",
    "Codex 额度",
    "Codex usage",
    "状态栏工具",
    "Swift",
    "OAuth",
  ],
  github: GITHUB_REPO_URL,
  releases: GITHUB_RELEASES_URL,
} as const;

export function absoluteUrl(path = "/") {
  return new URL(path, siteConfig.url).toString();
}
