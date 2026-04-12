import type { Metadata } from "next";

export const locales = ["en", "zh-CN"] as const;

export type LocaleCode = (typeof locales)[number];

type Feature = {
  title: string;
  description: string;
};

type WorkflowStep = {
  title: string;
  description: string;
};

type HeroLink = {
  label: string;
  href: string;
  variant: "primary" | "secondary" | "tertiary";
};

type LocaleCopy = {
  languageName: string;
  brandTagline: string;
  eyebrow: string;
  title: string;
  summary: string;
  badges: string[];
  releaseCardLabel: string;
  releaseCardBody: string;
  heroLinks: HeroLink[];
  shotEyebrow: string;
  shotTitle: string;
  shotBody: string;
  sectionKicker: string;
  sectionTitle: string;
  sectionBody: string;
  features: Feature[];
  workflowTitle: string;
  workflowBody: string;
  workflowSteps: WorkflowStep[];
  footerTitle: string;
  footerBody: string;
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
    brandTagline: "Menu bar control for local OpenClaw",
    eyebrow: "macOS menu bar companion",
    title: "Operate OpenClaw without leaving the menu bar.",
    summary:
      "Clawbar is a macOS 14+ menu bar app for installing, configuring, and operating a local OpenClaw setup. Keep install state, Gateway, Providers, Channels, and the OpenClaw TUI in one compact control surface.",
    badges: [releaseInfo.minMacOS, `Version ${releaseInfo.version}`, "Local OpenClaw workflow"],
    releaseCardLabel: "Latest release",
    releaseCardBody:
      "GitHub release tag v0.0.6 with a direct DMG install path for macOS users.",
    heroLinks: [
      { label: "Download Latest DMG", href: releaseInfo.downloadUrl, variant: "primary" },
      { label: "View Release Notes", href: releaseInfo.releaseUrl, variant: "secondary" },
      { label: "Browse Source", href: releaseInfo.repoUrl, variant: "tertiary" },
    ],
    shotEyebrow: "Live menu view",
    shotTitle: "Designed for quick operational checks",
    shotBody:
      "See install status, active Provider, Gateway health, Channel readiness, and launch actions in one place.",
    sectionKicker: "What it manages",
    sectionTitle: "A focused control layer on top of local OpenClaw.",
    sectionBody:
      "The app stays narrow on purpose: it reduces the friction around local OpenClaw operations instead of trying to replace the underlying CLI or TUI.",
    features: [
      {
        title: "Install and remove OpenClaw",
        description:
          "Run install and uninstall flows from a dedicated macOS companion instead of juggling terminal state.",
      },
      {
        title: "Track Gateway, Providers, and Channels",
        description:
          "Keep the moving parts visible with status summaries for Gateway background service, configured providers, and channel readiness.",
      },
      {
        title: "Launch the OpenClaw TUI fast",
        description:
          "Jump from the menu bar into the TUI when you need deeper operational work without hunting for the right command.",
      },
      {
        title: "Stay on a notarized DMG path",
        description:
          "The current public install channel is a signed GitHub Release DMG, which keeps onboarding simple for macOS users.",
      },
    ],
    workflowTitle: "How this release is framed",
    workflowBody:
      "The website is intentionally simple for the first pass: a direct introduction, a direct download, and enough context to know whether Clawbar belongs in your local OpenClaw setup.",
    workflowSteps: [
      {
        title: "Download the latest notarized installer",
        description:
          "Use the primary CTA to get the latest DMG published for tag v0.0.6.",
      },
      {
        title: "Install Clawbar on macOS 14+",
        description:
          "Mount the DMG, move the app into Applications, and launch it like a normal menu bar utility.",
      },
      {
        title: "Use Clawbar as the local operations surface",
        description:
          "Open the menu to inspect state, manage services, and launch OpenClaw tools from a single entry point.",
      },
    ],
    footerTitle: "Clawbar is a public GitHub project.",
    footerBody:
      "The website is built from the repository’s current README and release metadata so download links and product framing stay aligned with the shipping app.",
    footerLinks: [
      { label: "Latest DMG", href: releaseInfo.downloadUrl },
      { label: "Release v0.0.6", href: releaseInfo.releaseUrl },
      { label: "GitHub Repository", href: releaseInfo.repoUrl },
    ],
    metadataTitle: "Clawbar | Menu bar control for local OpenClaw",
    metadataDescription:
      "Download Clawbar, a macOS 14+ menu bar app for installing, configuring, and operating a local OpenClaw setup.",
  },
  "zh-CN": {
    languageName: "简体中文",
    brandTagline: "本地 OpenClaw 的菜单栏控制台",
    eyebrow: "macOS 菜单栏伴侣应用",
    title: "把 OpenClaw 的本地运维入口收进菜单栏。",
    summary:
      "Clawbar 是一个 macOS 14+ 菜单栏应用，用于本地安装、配置和操作 OpenClaw。安装状态、Gateway、Providers、Channels，以及 OpenClaw TUI 的入口，都集中在一个紧凑的控制界面里。",
    badges: [releaseInfo.minMacOS, `版本 ${releaseInfo.version}`, "本地 OpenClaw 工作流"],
    releaseCardLabel: "当前发布版本",
    releaseCardBody: "GitHub 上的 v0.0.6 发布，提供可直接下载的 DMG 安装包。",
    heroLinks: [
      { label: "下载最新 DMG", href: releaseInfo.downloadUrl, variant: "primary" },
      { label: "查看发布说明", href: releaseInfo.releaseUrl, variant: "secondary" },
      { label: "查看源码", href: releaseInfo.repoUrl, variant: "tertiary" },
    ],
    shotEyebrow: "菜单实拍",
    shotTitle: "快速确认运行状态，而不是到处翻终端",
    shotBody:
      "在一个菜单里查看安装状态、当前 Provider、Gateway 健康状态、Channel 就绪情况，以及常用启动操作。",
    sectionKicker: "它负责什么",
    sectionTitle: "围绕本地 OpenClaw 的一层轻量控制界面。",
    sectionBody:
      "Clawbar 的定位很克制：它不替代底层 CLI 或 TUI，而是把本地 OpenClaw 最常用的运维入口收敛成更顺手的 macOS 菜单栏体验。",
    features: [
      {
        title: "安装和卸载 OpenClaw",
        description:
          "直接从 macOS 伴侣应用触发安装和卸载流程，减少来回切换终端时的状态负担。",
      },
      {
        title: "查看 Gateway、Providers 和 Channels",
        description:
          "持续看到 Gateway 后台服务、Provider 配置状态，以及 Channel 是否已经完成接入。",
      },
      {
        title: "快速拉起 OpenClaw TUI",
        description:
          "需要更深入的运维操作时，可以从菜单栏直接进入 TUI，而不是再去找命令。",
      },
      {
        title: "保持 GitHub Releases 的 DMG 安装路径",
        description:
          "当前公开安装渠道就是 GitHub Releases 上的已公证 DMG，对 macOS 用户最直接。",
      },
    ],
    workflowTitle: "这个版本的网站定位",
    workflowBody:
      "第一版网站保持简单：把产品介绍、下载入口和关键上下文放在一个页面里，让用户快速判断 Clawbar 是否适合自己的本地 OpenClaw 环境。",
    workflowSteps: [
      {
        title: "下载最新 notarized 安装包",
        description: "主按钮直接指向 v0.0.6 对应的 DMG 发布资产。",
      },
      {
        title: "在 macOS 14+ 上安装 Clawbar",
        description: "挂载 DMG，把应用拖到 Applications，然后像普通菜单栏工具一样启动。",
      },
      {
        title: "把它作为本地运维入口",
        description:
          "打开菜单查看状态、管理服务，并从统一入口启动 OpenClaw 相关工具。",
      },
    ],
    footerTitle: "Clawbar 是公开托管在 GitHub 上的项目。",
    footerBody:
      "网站文案基于仓库里的 README 和 release metadata 组织，这样下载链接和产品说明能跟当前发布版本保持一致。",
    footerLinks: [
      { label: "最新 DMG", href: releaseInfo.downloadUrl },
      { label: "v0.0.6 发布页", href: releaseInfo.releaseUrl },
      { label: "GitHub 仓库", href: releaseInfo.repoUrl },
    ],
    metadataTitle: "Clawbar | 本地 OpenClaw 的菜单栏控制台",
    metadataDescription:
      "下载 Clawbar，一个用于本地安装、配置和操作 OpenClaw 的 macOS 14+ 菜单栏应用。",
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
      icon: "/assets/clawbar-icon.png",
      shortcut: "/assets/clawbar-icon.png",
      apple: "/assets/clawbar-icon.png",
    },
  };
}
