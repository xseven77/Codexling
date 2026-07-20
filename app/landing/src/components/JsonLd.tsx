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
    operatingSystem: "macOS 13+",
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
      "macOS 菜单栏 Codex 额度摘要",
      "OpenAI 官方 OAuth PKCE 登录",
      "5 小时与周额度详情",
      "Credits 与重置券展示",
      "Keychain Token 存储",
      "本地快照缓存",
    ],
    isAccessibleForFree: true,
    license: "https://github.com/xseven77/Codexling",
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
