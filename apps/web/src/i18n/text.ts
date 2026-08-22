import { defaultLocale, type Locale } from "./config";
import { translations } from "./translations";

export function translate(locale: Locale, source: string): string {
  if (locale === defaultLocale) {
    return source;
  }

  return translations[locale][source] ?? source;
}
