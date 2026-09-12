export const requiredLocales = [
  "en-US",
  "de-DE",
  "es-ES",
  "fr-FR",
  "it",
  "ja",
  "ko",
  "vi",
  "zh-Hans",
  "pt-BR",
  "pt-PT",
];

export const fastlaneMetadataFiles = {
  name: "name.txt",
  subtitle: "subtitle.txt",
  promotionalText: "promotional_text.txt",
  description: "description.txt",
  keywords: "keywords.txt",
  whatsNew: "release_notes.txt",
  marketingUrl: "marketing_url.txt",
  supportUrl: "support_url.txt",
  privacyPolicyUrl: "privacy_url.txt",
};

export function parseTaggedJson(markdown, tag) {
  const pattern = new RegExp(
    "<!-- " + tag + " -->\\s*```json\\s*([\\s\\S]*?)\\s*```",
    "g",
  );
  return [...markdown.matchAll(pattern)].map((match) => JSON.parse(match[1]));
}

export function parseLocaleMetadata(markdown) {
  const locales = parseTaggedJson(markdown, "APP-STORE-LOCALE");
  const actualLocales = locales.map(({ locale }) => locale);

  if (JSON.stringify(actualLocales) !== JSON.stringify(requiredLocales)) {
    throw new Error(`Locale blocks must appear in this order: ${requiredLocales.join(", ")}`);
  }

  for (const entry of locales) {
    for (const field of Object.keys(fastlaneMetadataFiles)) {
      if (typeof entry[field] !== "string" || entry[field].length === 0) {
        throw new Error(`${entry.locale}: missing ${field}`);
      }
    }
  }

  return locales;
}
