/**
 * 刘海屏伴侣 · 演示数据模型
 *
 * agent 与 provider 是两个独立维度，互不一一对应：
 * - agent：本机所有 Agent 的实时任务状态（Codex 可同时登录多个账号，各自独立）
 * - provider：所有已登录账号 / 已配置 API Key 的额度（API Key 型没有对应 agent）
 *
 * 因此左区（agent 状态）与右区（provider 额度）各自独立轮播，节奏错开。
 */

export type AgentState =
  | "working"
  | "idle"
  | "waiting"
  | "reviewing"
  | "completed"
  | "interrupted"
  | "unavailable";

export interface AgentStateMeta {
  label: string;
  /** Tailwind 圆点色 class */
  dotClass: string;
  /** 与 Swift CodexActivityState.statusNSColor 对齐的 hex */
  color: string;
}

export const agentStateMeta: Record<AgentState, AgentStateMeta> = {
  working: { label: "工作中", dotClass: "bg-[#2e6bff]", color: "#2e6bff" },
  idle: { label: "空闲", dotClass: "bg-[#aeb5b3]", color: "#aeb5b3" },
  waiting: { label: "待确认", dotClass: "bg-[#f27314]", color: "#f27314" },
  reviewing: { label: "检查中", dotClass: "bg-[#05a1cc]", color: "#05a1cc" },
  completed: { label: "已完成", dotClass: "bg-[#1fa55a]", color: "#1fa55a" },
  interrupted: { label: "已中止", dotClass: "bg-[#ed384d]", color: "#ed384d" },
  unavailable: { label: "不可用", dotClass: "bg-[#aeb5b3]", color: "#aeb5b3" },
};

export function isAgentActive(state: AgentState): boolean {
  return state !== "idle" && state !== "unavailable";
}

export interface AgentSource {
  id: string;
  agentName: string;
  accountName: string;
  logo: string;
  state: AgentState;
  taskTitle: string;
  taskDetail: string;
}

export interface ProviderQuota {
  /** account 型：账号额度窗；apiKey 型：余额 */
  kind: "account" | "apiKey";
  /** 胶囊短文本，如 "5h 82% · 周76%" 或 "¥42.80" */
  compact: string;
  /** 展开面板主值，如 "82%" 或 "¥42.80" */
  primary: string;
  /** 展开面板副值，如 "周 76%" 或 "API Key" */
  secondary: string;
}

export interface ProviderSource {
  id: string;
  providerName: string;
  accountName: string;
  logo: string;
  quota: ProviderQuota;
}

/** 本机 Agent 任务：Codex 同时登录了 Work 与 Personal 两个账号，各自独立 */
export const agents: AgentSource[] = [
  {
    id: "codex-work",
    agentName: "Codex",
    accountName: "Work",
    logo: "/brand-assets/codex/color.svg",
    state: "working",
    taskTitle: "重构账户切换逻辑",
    taskDetail: "正在修改 4 个文件",
  },
  {
    id: "kimi",
    agentName: "Kimi Code",
    accountName: "Personal",
    logo: "/brand-assets/kimi-code/color.svg",
    state: "waiting",
    taskTitle: "是否执行完整测试？",
    taskDetail: "确认后继续运行测试",
  },
  {
    id: "claude",
    agentName: "Claude Code",
    accountName: "Work",
    logo: "/brand-assets/claude-code/color.svg",
    state: "reviewing",
    taskTitle: "检查 pull request 改动",
    taskDetail: "正在 review 12 个文件",
  },
  {
    id: "codex-personal",
    agentName: "Codex",
    accountName: "Personal",
    logo: "/brand-assets/codex/color.svg",
    state: "idle",
    taskTitle: "当前没有运行任务",
    taskDetail: "最近同步于 2 分钟前",
  },
];

/** 账号 / API Key 额度：与 agent 独立，DeepSeek / Claude 为 API Key 型（无对应 agent） */
export const providers: ProviderSource[] = [
  {
    id: "codex-work",
    providerName: "Codex",
    accountName: "Work",
    logo: "/brand-assets/codex/color.svg",
    quota: { kind: "account", compact: "5h 82% · 周76%", primary: "82%", secondary: "周 76%" },
  },
  {
    id: "codex-personal",
    providerName: "Codex",
    accountName: "Personal",
    logo: "/brand-assets/codex/color.svg",
    quota: { kind: "account", compact: "5h 54% · 周91%", primary: "54%", secondary: "周 91%" },
  },
  {
    id: "deepseek",
    providerName: "DeepSeek",
    accountName: "Personal Key",
    logo: "/brand-assets/deepseek/color.svg",
    quota: { kind: "apiKey", compact: "¥42.80", primary: "¥42.80", secondary: "API Key" },
  },
  {
    id: "kimi",
    providerName: "Kimi Code",
    accountName: "Personal",
    logo: "/brand-assets/kimi-code/color.svg",
    quota: { kind: "account", compact: "5h 28% · 周63%", primary: "28%", secondary: "周 63%" },
  },
  {
    id: "claude",
    providerName: "Claude Code",
    accountName: "Work Key",
    logo: "/brand-assets/claude-code/color.svg",
    quota: { kind: "apiKey", compact: "¥128.50", primary: "¥128.50", secondary: "API Key" },
  },
];

/** 多 agent 并发计数：活跃（非 idle / 非 unavailable）的 agent 数量 */
export const activeAgentCount = agents.filter((a) => isAgentActive(a.state)).length;

/** 待确认计数 */
export const waitingCount = agents.filter((a) => a.state === "waiting").length;

export function agentLabelOf(agent: AgentSource): string {
  return agentStateMeta[agent.state].label;
}

export function agentDotClassOf(agent: AgentSource): string {
  return agentStateMeta[agent.state].dotClass;
}

export function agentColorOf(agent: AgentSource): string {
  return agentStateMeta[agent.state].color;
}
