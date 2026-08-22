import type { Locale } from "../config";
import de from "./de.json";
import deDocs1 from "./de-docs-1.json";
import deDocs2 from "./de-docs-2.json";
import es from "./es.json";
import esDocs1 from "./es-docs-1.json";
import esDocs2 from "./es-docs-2.json";
import fr from "./fr.json";
import frDocs1 from "./fr-docs-1.json";
import frDocs2 from "./fr-docs-2.json";
import it from "./it.json";
import itDocs1 from "./it-docs-1.json";
import itDocs2 from "./it-docs-2.json";
import ja from "./ja.json";
import jaDocs1 from "./ja-docs-1.json";
import jaDocs2 from "./ja-docs-2.json";
import ko from "./ko.json";
import koDocs1 from "./ko-docs-1.json";
import koDocs2 from "./ko-docs-2.json";
import ptBR from "./pt-BR.json";
import ptPT from "./pt-PT.json";
import ptDocs1 from "./pt-docs-1.json";
import ptDocs2 from "./pt-docs-2.json";
import sources from "./sources.json";
import vi from "./vi.json";
import viDocs1 from "./vi-docs-1.json";
import viDocs2 from "./vi-docs-2.json";
import zhHans from "./zh-Hans.json";
import zhHansDocs1 from "./zh-Hans-docs-1.json";
import zhHansDocs2 from "./zh-Hans-docs-2.json";

type TranslatedLocale = Exclude<Locale, "en">;

const localizedValues: Record<TranslatedLocale, string[]> = {
  de: [...de, ...deDocs1, ...deDocs2],
  es: [...es, ...esDocs1, ...esDocs2],
  fr: [...fr, ...frDocs1, ...frDocs2],
  it: [...it, ...itDocs1, ...itDocs2],
  ja: [...ja, ...jaDocs1, ...jaDocs2],
  ko: [...ko, ...koDocs1, ...koDocs2],
  vi: [...vi, ...viDocs1, ...viDocs2],
  "zh-Hans": [...zhHans, ...zhHansDocs1, ...zhHansDocs2],
  "pt-BR": [...ptBR, ...ptDocs1, ...ptDocs2],
  "pt-PT": [...ptPT, ...ptDocs1, ...ptDocs2]
};

export const translations = Object.fromEntries(
  Object.entries(localizedValues).map(([locale, values]) => [
    locale,
    Object.fromEntries(sources.map((source, index) => [source, values[index]]))
  ])
) as Record<TranslatedLocale, Record<string, string>>;
