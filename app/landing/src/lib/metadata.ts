import type { Metadata } from "next";
import { siteConfig } from "@/lib/site";

export function createMetadata(overrides?: Partial<Metadata>): Metadata {
  const ogImage = "/opengraph-image.png";

  return {
    metadataBase: new URL(siteConfig.url),
    title: {
      default: siteConfig.title,
      template: `%s · ${siteConfig.name}`,
    },
    description: siteConfig.description,
    keywords: [...siteConfig.keywords],
    authors: [{ name: siteConfig.author, url: siteConfig.github }],
    creator: siteConfig.author,
    publisher: siteConfig.name,
    category: "technology",
    alternates: {
      canonical: "/",
    },
    openGraph: {
      type: "website",
      locale: siteConfig.locale,
      url: siteConfig.url,
      siteName: siteConfig.name,
      title: siteConfig.title,
      description: siteConfig.shortDescription,
      images: [
        {
          url: ogImage,
          width: 1200,
          height: 630,
          alt: siteConfig.title,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: siteConfig.title,
      description: siteConfig.shortDescription,
      images: [ogImage],
      creator: `@${siteConfig.author}`,
    },
    robots: {
      index: true,
      follow: true,
      googleBot: {
        index: true,
        follow: true,
        "max-video-preview": -1,
        "max-image-preview": "large",
        "max-snippet": -1,
      },
    },
    manifest: "/site.webmanifest",
    icons: {
      icon: [{ url: "/icon.png", type: "image/png", sizes: "512x512" }],
      shortcut: ["/favicon.ico"],
      apple: [{ url: "/apple-icon.png", type: "image/png", sizes: "180x180" }],
    },
    ...overrides,
  };
}
