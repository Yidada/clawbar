import { redirect } from "next/navigation";

import { defaultLocale } from "../lib/site-content";

export default function HomePage() {
  redirect(`/${defaultLocale}`);
}
