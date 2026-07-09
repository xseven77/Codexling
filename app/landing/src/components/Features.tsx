const features = [
  {
    title: "菜单栏常驻摘要",
    description:
      "在 macOS 状态栏直接看到 5 小时与周额度百分比，无需打开浏览器或 ChatGPT 页面。",
    icon: "◉",
  },
  {
    title: "官方 OAuth 登录",
    description:
      "沿用 Codex usage 同源 PKCE 流程，跳转 OpenAI 官方授权页，Token 存入 Keychain。",
    icon: "🔐",
  },
  {
    title: "详情弹窗一目了然",
    description:
      "点击菜单栏即可查看额度、重置券、过期时间与最近刷新状态；底部一键刷新，顶部可进设置。",
    icon: "▦",
  },
  {
    title: "主题与自动刷新",
    description:
      "设置页支持浅色 / 深色 / 跟随系统，并可配置 30 秒到 10 分钟的自动刷新间隔。",
    icon: "⚙",
  },
  {
    title: "本地快照缓存",
    description:
      "最近一次成功拉取的数据会缓存在本地，启动更快，离线也能看到上次额度概况。",
    icon: "⚡",
  },
  {
    title: "隐私优先设计",
    description: "不保存账号密码，不绕过 MFA / SSO，不依赖私有账号凭证。",
    icon: "🛡",
  },
  {
    title: "开源可审计",
    description: "Swift 源码完全开放，GitHub Release 提供 DMG 与 ZIP 两种安装方式。",
    icon: "⌘",
  },
];

export function Features() {
  return (
    <section id="features" className="mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-24" aria-labelledby="features-heading">
      <div className="max-w-2xl">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-accent">
          Features
        </p>
        <h2 id="features-heading" className="mt-3 text-2xl font-semibold tracking-tight sm:text-4xl">
          为 macOS 原生体验而生
        </h2>
        <p className="mt-4 text-base text-muted sm:text-lg">
          借鉴 OpenAI 与 Notion 的简洁产品叙事，把复杂额度信息压缩成一眼可读的状态栏体验。
        </p>
      </div>

      <div className="mt-10 grid gap-4 sm:mt-12 sm:gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((feature) => (
          <article
            key={feature.title}
            className="glass group rounded-2xl p-5 transition-transform duration-300 sm:rounded-3xl sm:p-6 sm:hover:-translate-y-1"
          >
            <div className="mb-4 inline-flex h-11 w-11 items-center justify-center rounded-2xl bg-accent-soft text-lg">
              {feature.icon}
            </div>
            <h3 className="text-lg font-medium">{feature.title}</h3>
            <p className="mt-2 text-sm leading-7 text-muted">{feature.description}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
