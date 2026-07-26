import { GITHUB_RELEASES_URL, GITHUB_REPO_URL } from "@/lib/github";
import { siteConfig } from "@/lib/site";

type JsonLdProps = {
  latestVersion?: string;
};

export function JsonLd({ latestVersion }: JsonLdProps) {
  const softwareApp = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: siteConfig.name,
    applicationCategory: "DeveloperApplication",
    operatingSystem: "macOS 14+",
    description: siteConfig.description,
    url: siteConfig.url,
    downloadUrl: GITHUB_RELEASES_URL,
    ...(latestVersion ? { softwareVersion: latestVersion } : {}),
    author: {
      "@type": "Person",
      name: siteConfig.author,
      url: GITHUB_REPO_URL,
    },
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: GITHUB_RELEASES_URL,
    },
    featureList: [
      "macOS 菜单栏任务状态与额度窗口",
      "任务运行时主动展示的 Pet 与状态摘要浮窗",
      "auth.openai.com OAuth PKCE 登录",
      "Codex 多任务活动、元数据与截断状态摘要",
      "Codex Pet 发现、安装、选择同步与重启提示",
      "主/次级额度、重置券与订阅周期",
      "本地陪伴时间统计",
      "Application Support 本地 Token 文件（0600）",
      "本地快照缓存",
      "设置内检查并安装 GitHub Release 更新",
    ],
    isAccessibleForFree: true,
  };

  const webSite = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: siteConfig.name,
    url: siteConfig.url,
    description: siteConfig.shortDescription,
    inLanguage: "zh-CN",
    publisher: {
      "@type": "Organization",
      name: siteConfig.name,
      url: siteConfig.url,
    },
  };

  const webPage = {
    "@context": "https://schema.org",
    "@type": "WebPage",
    name: siteConfig.title,
    url: siteConfig.url,
    description: siteConfig.description,
    isPartOf: { "@id": siteConfig.url },
    about: {
      "@type": "SoftwareApplication",
      name: siteConfig.name,
    },
    inLanguage: "zh-CN",
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApp) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(webSite) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(webPage) }}
      />
    </>
  );
}
