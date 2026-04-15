import Image from "next/image";

import type { LocaleCode } from "../lib/site-content";
import { getLocaleCopy, locales, releaseInfo, siteCopy } from "../lib/site-content";

type LandingPageProps = {
  locale: LocaleCode;
};

export function LandingPage({ locale }: LandingPageProps) {
  const content = getLocaleCopy(locale);

  if (!content) {
    return null;
  }

  return (
    <div className="site-shell">
      <div className="page">
        <header className="topbar">
          <div className="container topbar__inner">
            <a className="brand" href={`/${locale}`}>
              <div className="brand__mark">
                <Image
                  src="/assets/clawbar-logo.png"
                  alt="Clawbar icon"
                  width={345}
                  height={459}
                  priority
                />
              </div>
              <div>
                <div className="brand__name">Clawbar</div>
                <div className="brand__tagline">{content.brandTagline}</div>
              </div>
            </a>

            <nav className="locale-switcher" aria-label="Language switcher">
              {locales.map((itemLocale) => (
                <a
                  key={itemLocale}
                  className={itemLocale === locale ? "is-active" : undefined}
                  href={`/${itemLocale}`}
                  hrefLang={itemLocale}
                  lang={itemLocale}
                >
                  {siteCopy[itemLocale].languageName}
                </a>
              ))}
            </nav>
          </div>
        </header>

        <main lang={locale}>
          <section className="hero">
            <div className="container hero__inner">
              <div>
                <h1>{content.title}</h1>
                <p className="hero__lede">{content.summary}</p>

                <div className="cta-row">
                  {content.heroLinks.map((link) => (
                    <a
                      className={`button button--${link.variant}`}
                      href={link.href}
                      key={link.label}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {link.label}
                    </a>
                  ))}
                </div>
              </div>

              <div className="hero__screenshot">
                <div className="screenshot-frame">
                  <Image
                    src="/assets/clawbar-smoke.png"
                    alt="Clawbar menu screenshot"
                    width={576}
                    height={768}
                    priority
                  />
                </div>
              </div>
            </div>
          </section>

          <section className="features">
            <div className="container">
              <h2 className="features__title">{content.featuresTitle}</h2>

              <div className="feature-grid">
                {content.features.map((feature, index) => (
                  <article className="feature-card" key={feature.title}>
                    <span className="feature-card__index">{String(index + 1).padStart(2, "0")}</span>
                    <h3>{feature.title}</h3>
                    <p>{feature.description}</p>
                  </article>
                ))}
              </div>
            </div>
          </section>
        </main>

        <footer className="footer">
          <div className="container footer__inner">
            <span>Clawbar {releaseInfo.version}</span>

            <div className="footer-links">
              {content.footerLinks.map((link) => (
                <a href={link.href} key={link.label} target="_blank" rel="noreferrer">
                  {link.label}
                </a>
              ))}
            </div>
          </div>
        </footer>
      </div>
    </div>
  );
}
