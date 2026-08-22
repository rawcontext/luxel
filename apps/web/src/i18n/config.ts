export const siteUrl = "https://luxel.media";
export const defaultLocale = "en";

export const supportedLocales = [
  "en",
  "de",
  "es",
  "fr",
  "it",
  "ja",
  "ko",
  "vi",
  "zh-Hans",
  "pt-BR",
  "pt-PT"
] as const;

export type Locale = (typeof supportedLocales)[number];

export const publicPagePaths = ["/", "/docs", "/support", "/privacy"] as const;
export type PublicPagePath = (typeof publicPagePaths)[number];

export function isLocale(value: string): value is Locale {
  return supportedLocales.some((locale) => locale === value);
}

export function localizedPath(locale: Locale, path: PublicPagePath): string {
  if (locale === defaultLocale) {
    return path;
  }

  return path === "/" ? `/${locale}/` : `/${locale}${path}`;
}

export function localizedHref(locale: Locale, href: string): string {
  if (locale === defaultLocale || href.startsWith("#") || !href.startsWith("/")) {
    return href;
  }

  const [pathAndQuery, hash] = href.split("#", 2);
  const localized = pathAndQuery === "/" ? `/${locale}/` : `/${locale}${pathAndQuery}`;
  return hash === undefined ? localized : `${localized}#${hash}`;
}

export function absoluteLocalizedUrl(locale: Locale, path: PublicPagePath): string {
  return new URL(localizedPath(locale, path), siteUrl).toString();
}

export function resolvePreferredLocale(
  preferences: readonly string[],
  locales: readonly string[] = supportedLocales
): string | undefined {
  const localeByLowercase = new Map(locales.map((locale) => [locale.toLowerCase(), locale]));

  for (const preference of preferences) {
    let requested: Intl.Locale;
    try {
      requested = new Intl.Locale(preference.replaceAll("_", "-"));
    } catch {
      continue;
    }

    const exact = localeByLowercase.get(requested.baseName.toLowerCase());
    if (exact) {
      return exact;
    }

    if (requested.language === "zh") {
      const script = requested.script ?? requested.maximize().script;
      if (script === "Hans") {
        return localeByLowercase.get("zh-hans");
      }
      continue;
    }

    if (requested.language === "pt") {
      const region = requested.region ?? requested.maximize().region;
      const portugueseLocale = region === "BR" ? "pt-br" : "pt-pt";
      const match = localeByLowercase.get(portugueseLocale);
      if (match) {
        return match;
      }
    }

    const languageMatch = localeByLowercase.get(requested.language.toLowerCase());
    if (languageMatch) {
      return languageMatch;
    }
  }

  return undefined;
}

function redirectToPreferredLocale(
  resolve: typeof resolvePreferredLocale,
  locales: readonly string[],
  fallbackLocale: string,
  pagePath: string
): void {
  const preferredLocale = resolve(navigator.languages, locales);
  if (!preferredLocale || preferredLocale === fallbackLocale) {
    return;
  }

  const localizedPagePath = pagePath === "/"
    ? `/${preferredLocale}/`
    : `/${preferredLocale}${pagePath}`;
  const destination = `${localizedPagePath}${window.location.search}${window.location.hash}`;
  window.location.replace(destination);
}

export function localeRedirectScript(path: PublicPagePath): string {
  return `(${redirectToPreferredLocale.toString()})(${resolvePreferredLocale.toString()}, ${JSON.stringify(supportedLocales)}, ${JSON.stringify(defaultLocale)}, ${JSON.stringify(path)});`;
}
