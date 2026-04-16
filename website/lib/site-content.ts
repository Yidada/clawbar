import type { Metadata } from "next";

export const locales = ["en", "zh-CN"] as const;

export type LocaleCode = (typeof locales)[number];

export const defaultLocale: LocaleCode = "en";

type Feature = {
  title: string;
  description: string;
};

type HeroLink = {
  label: string;
  href: string;
  variant: "primary" | "secondary";
};

type LocaleCopy = {
  languageName: string;
  brandTagline: string;
  title: string;
  summary: string;
  heroLinks: HeroLink[];
  featuresTitle: string;
  features: Feature[];
  footerLinks: Array<{ label: string; href: string }>;
  metadataTitle: string;
  metadataDescription: string;
};

export const releaseInfo = {
  version: "0.0.6",
  tag: "v0.0.6",
  minMacOS: "macOS 14+",
  downloadUrl:
    "https://github.com/Yidada/clawbar/releases/download/v0.0.6/Clawbar-0.0.6.dmg",
  releaseUrl: "https://github.com/Yidada/clawbar/releases/tag/v0.0.6",
  repoUrl: "https://github.com/Yidada/clawbar",
};

export const siteCopy: Record<LocaleCode, LocaleCopy> = {
  en: {
    languageName: "English",
    brandTagline: "The easiest way to use OpenClaw",
    title: "OpenClaw, made easy.",
    summary:
      "Clawbar is a macOS 14+ companion app that lets you install, configure, and run OpenClaw in a few clicks. No terminal, no guesswork — just open the menu bar and go.",
    heroLinks: [
      { label: "Download Latest DMG", href: releaseInfo.downloadUrl, variant: "primary" },
      { label: "Browse Source", href: releaseInfo.repoUrl, variant: "secondary" },
    ],
    featuresTitle: "Everything you need, nothing you don't.",
    features: [
      {
        title: "One-click install and removal",
        description:
          "Set up or tear down OpenClaw from a native macOS app — no terminal commands to remember.",
      },
      {
        title: "See everything at a glance",
        description:
          "Gateway, Providers, and Channels status all visible in one place. Always know what's running and what's ready.",
      },
      {
        title: "Jump into the TUI instantly",
        description:
          "Need deeper control? Launch the OpenClaw TUI straight from the menu bar — no hunting for the right command.",
      },
      {
        title: "Simple, signed, and notarized",
        description:
          "Install via a signed DMG from GitHub Releases. No Homebrew, no package managers — just download and open.",
      },
    ],
    footerLinks: [
      { label: "Latest DMG", href: releaseInfo.downloadUrl },
      { label: "Release v0.0.6", href: releaseInfo.releaseUrl },
      { label: "GitHub Repository", href: releaseInfo.repoUrl },
    ],
    metadataTitle: "Clawbar | The easiest way to use OpenClaw",
    metadataDescription:
      "Download Clawbar, a macOS 14+ companion app that makes installing, configuring, and running OpenClaw effortless.",
  },
  "zh-CN": {
    languageName: "简体中文",
    brandTagline: "用最简单的方式使用 OpenClaw",
    title: "在 Mac 上使用 OpenClaw 最简单的方式。",
    summary:
      "Clawbar 是一个 macOS 14+ 伴侣应用，让你几次点击就能安装、配置和运行 OpenClaw。不需要终端，不需要猜命令——打开菜单栏就能开始。",
    heroLinks: [
      { label: "下载最新 DMG", href: releaseInfo.downloadUrl, variant: "primary" },
      { label: "查看源码", href: releaseInfo.repoUrl, variant: "secondary" },
    ],
    featuresTitle: "该有的都有，多余的一概没有。",
    features: [
      {
        title: "一键安装和卸载",
        description:
          "通过原生 macOS 应用完成 OpenClaw 的安装或移除——不用记任何终端命令。",
      },
      {
        title: "状态一目了然",
        description:
          "Gateway、Providers、Channels 的运行状态集中展示，随时掌握哪些在跑、哪些就绪。",
      },
      {
        title: "秒开 TUI",
        description:
          "需要更深入的操作？从菜单栏直接拉起 OpenClaw TUI，不用翻找命令。",
      },
      {
        title: "签名公证，开箱即用",
        description:
          "通过 GitHub Releases 的签名 DMG 安装，不需要 Homebrew，不需要包管理器——下载即用。",
      },
    ],
    footerLinks: [
      { label: "最新 DMG", href: releaseInfo.downloadUrl },
      { label: "v0.0.6 发布页", href: releaseInfo.releaseUrl },
      { label: "GitHub 仓库", href: releaseInfo.repoUrl },
    ],
    metadataTitle: "Clawbar | 用最简单的方式使用 OpenClaw",
    metadataDescription:
      "下载 Clawbar，一个让安装、配置和运行 OpenClaw 变得轻松简单的 macOS 14+ 伴侣应用。",
  },
};

export function isLocaleCode(value: string): value is LocaleCode {
  return locales.includes(value as LocaleCode);
}

export function getLocaleCopy(locale: string): LocaleCopy | null {
  return isLocaleCode(locale) ? siteCopy[locale] : null;
}

export function getMetadata(locale: LocaleCode): Metadata {
  const content = siteCopy[locale];

  return {
    title: content.metadataTitle,
    description: content.metadataDescription,
    icons: {
      icon: "/assets/clawbar-logo.png",
      shortcut: "/assets/clawbar-logo.png",
      apple: "/assets/clawbar-logo.png",
    },
  };
}
