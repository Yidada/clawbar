import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { LandingPage } from "../../components/landing-page";
import { getMetadata, isLocaleCode, locales } from "../../lib/site-content";

type LocalePageProps = {
  params: Promise<{ locale: string }>;
};

export const dynamicParams = false;

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LocalePageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!isLocaleCode(locale)) {
    return {};
  }

  return getMetadata(locale);
}

export default async function LocalePage({ params }: LocalePageProps) {
  const { locale } = await params;

  if (!isLocaleCode(locale)) {
    notFound();
  }

  return <LandingPage locale={locale} />;
}
