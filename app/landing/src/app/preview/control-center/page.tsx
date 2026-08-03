import type { Metadata } from "next";
import { MultiAgentPreview } from "@/components/preview/MultiAgentPreview";

export const metadata: Metadata = {
  title: "多 Agent 控制台备份 · Codexling",
  description: "Codexling 多 Agent 中台方案的保留原型。",
};

export default function ControlCenterBackupPage() {
  return <MultiAgentPreview />;
}
