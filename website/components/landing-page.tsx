import Image from "next/image";

import type { LocaleCode } from "../lib/site-content";
import { getLocaleCopy, releaseInfo, siteCopy } from "../lib/site-content";

type LandingPageProps = {
  locale: LocaleCode;
};

export function LandingPage({ locale }: LandingPageProps) {
  const content = getLocaleCopy(locale);

  if (!content) {
    return null;
  }

  const alternateLocale: LocaleCode = locale === "en" ? "zh-CN" : "en";

  return (
    <div className="site-shell">
      <div className="page">
        <header className="topbar">
          <div className="container topbar__inner">
            <a className="brand" href={`/${locale}`}>
              <div className="brand__mark">
                <Image
                  src="/assets/clawbar-icon.png"
                  alt="Clawbar icon"
                  width={46}
                  height={46}
                  priority
                />
              </div>
              <div>
                <div className="brand__name">Clawbar</div>
                <div className="brand__tagline">{content.brandTagline}</div>
              </div>
            </a>

            <nav className="locale-switcher" aria-label="Language switcher">
              {(
                [
                  ["en", siteCopy.en.languageName],
                  ["zh-CN", siteCopy["zh-CN"].languageName],
                ] as const
              ).map(([itemLocale, label]) => (
                <a
                  key={itemLocale}
                  className={itemLocale === locale ? "is-active" : undefined}
                  href={`/${itemLocale}`}
                  hrefLang={itemLocale}
                  lang={itemLocale}
                >
                  {label}
                </a>
              ))}
            </nav>
          </div>
        </header>

        <main lang={locale}>
          <section className="hero">
            <div className="container hero__panel">
              <div>
                <span className="eyebrow">{content.eyebrow}</span>
                <h1>{content.title}</h1>
                <p className="hero__lede">{content.summary}</p>

                <div className="badge-row" aria-label="Release badges">
                  {content.badges.map((badge) => (
                    <span className="badge" key={badge}>
                      {badge}
                    </span>
                  ))}
                </div>

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

              <div className="hero__aside">
                <aside className="stat-card">
                  <div className="stat-card__label">{content.releaseCardLabel}</div>
                  <div className="stat-card__value">{releaseInfo.version}</div>
                  <div className="stat-card__text">{content.releaseCardBody}</div>
                </aside>

                <aside className="shot-card">
                  <div className="shot-card__header">
                    <div>
                      <div className="section__kicker">{content.shotEyebrow}</div>
                      <h3>{content.shotTitle}</h3>
                      <p>{content.shotBody}</p>
                    </div>
                    <a
                      className="button button--secondary"
                      href={`/${alternateLocale}`}
                      lang={alternateLocale}
                      hrefLang={alternateLocale}
                    >
                      {siteCopy[alternateLocale].languageName}
                    </a>
                  </div>

                  <div className="shot-card__figure">
                    <div className="shot-card__frame">
                      <Image
                        src="/assets/clawbar-smoke.png"
                        alt="Clawbar menu screenshot"
                        width={576}
                        height={768}
                        priority
                      />
                    </div>
                  </div>
                </aside>
              </div>
            </div>
          </section>

          <section className="section">
            <div className="container">
              <div className="section__intro">
                <div className="section__kicker">{content.sectionKicker}</div>
                <h2>{content.sectionTitle}</h2>
                <p>{content.sectionBody}</p>
              </div>

              <div className="feature-grid">
                {content.features.map((feature, index) => (
                  <article className="feature-card" key={feature.title}>
                    <span className="feature-card__index">{String(index + 1).padStart(2, "0")}</span>
                    <h3>{feature.title}</h3>
                    <p>{feature.description}</p>
                  </article>
                ))}
              </div>

              <div className="workflow">
                <article className="workflow-card">
                  <div className="section__kicker">{releaseInfo.minMacOS}</div>
                  <h3>{content.workflowTitle}</h3>
                  <p>{content.workflowBody}</p>
                </article>

                <article className="workflow-card">
                  <div className="workflow-list">
                    {content.workflowSteps.map((step, index) => (
                      <div className="workflow-item" key={step.title}>
                        <span className="workflow-item__marker">{index + 1}</span>
                        <div>
                          <h4>{step.title}</h4>
                          <p>{step.description}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </article>
              </div>
            </div>
          </section>
        </main>

        <footer className="footer">
          <div className="container footer-card">
            <div>
              <strong>{content.footerTitle}</strong>
              <p>{content.footerBody}</p>
            </div>

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
