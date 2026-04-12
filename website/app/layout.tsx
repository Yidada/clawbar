import type { ReactNode } from "react";
import Script from "next/script";

import "./globals.css";

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Script id="set-document-lang" strategy="beforeInteractive">
          {`document.documentElement.lang = location.pathname.startsWith('/zh-CN') ? 'zh-CN' : 'en';`}
        </Script>
        {children}
      </body>
    </html>
  );
}
