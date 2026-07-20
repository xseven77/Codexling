const steps = [
  {
    step: "01",
    title: "点击菜单栏图标",
    description: "启动 Codexling，状态栏会显示当前额度摘要或登录提示。",
  },
  {
    step: "02",
    title: "官方 OAuth 授权",
    description:
      "应用打开 OpenAI 授权页，本地监听 localhost 回调并完成 PKCE code exchange。",
  },
  {
    step: "03",
    title: "拉取 wham 用量",
    description:
      "使用官方 Token 访问 ChatGPT wham usage / rate-limit-reset-credits 端点。",
  },
  {
    step: "04",
    title: "缓存并展示",
    description: "解析额度、credits、重置券后写入本地缓存，菜单栏与弹窗同步更新。",
  },
];

export function HowItWorks() {
  return (
    <section id="how-it-works" className="border-y border-border/70 bg-surface/50" aria-labelledby="how-heading">
      <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-24">
        <div className="max-w-2xl">
          <p className="text-sm font-medium uppercase tracking-[0.2em] text-accent">
            How it works
          </p>
          <h2 id="how-heading" className="mt-3 text-2xl font-semibold tracking-tight sm:text-4xl">
            四步完成登录与额度同步
          </h2>
        </div>

        <div className="mt-10 grid gap-4 sm:mt-12 sm:gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {steps.map((item) => (
            <div key={item.step} className="relative rounded-2xl border border-border p-5 sm:rounded-3xl sm:p-6">
              <div className="text-sm font-mono text-accent">{item.step}</div>
              <h3 className="mt-4 text-lg font-medium">{item.title}</h3>
              <p className="mt-2 text-sm leading-7 text-muted">{item.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
