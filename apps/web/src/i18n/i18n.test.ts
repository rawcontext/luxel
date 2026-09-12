import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";

import { commonCopy } from "./common";
import { menuBarDemoCopy } from "./menu-bar-demo";

import {
  defaultLocale,
  localizedPath,
  publicPagePaths,
  resolvePreferredLocale,
  supportedLocales
} from "./config";

const webRoot = path.resolve(import.meta.dir, "../..");
const repositoryRoot = path.resolve(webRoot, "../..");
const translationsRoot = path.join(import.meta.dir, "translations");
const translatedLocales = supportedLocales.filter((locale) => locale !== defaultLocale);

describe("locale parity", () => {
  test("covers every navigation and interactive-demo string and preserves placeholders", () => {
    const flatten = (copy: object, prefix = ""): Record<string, string> => Object.fromEntries(
      Object.entries(copy).flatMap(([key, value]) => typeof value === "string"
        ? [[`${prefix}${key}`, value]]
        : Object.entries(flatten(value, `${prefix}${key}.`)))
    );
    const english = flatten({ common: commonCopy("en"), demo: menuBarDemoCopy("en") });
    for (const locale of supportedLocales) {
      const copy = flatten({ common: commonCopy(locale), demo: menuBarDemoCopy(locale) });
      expect(Object.keys(copy).sort()).toEqual(Object.keys(english).sort());
      for (const [key, value] of Object.entries(copy)) {
        expect(value.trim().length).toBeGreaterThan(0);
        expect(value.match(/\{\w+\}/g) ?? []).toEqual(english[key].match(/\{\w+\}/g) ?? []);
      }
    }
  });

  test("matches the macOS app locale list exactly", () => {
    const swift = readFileSync(
      path.join(repositoryRoot, "apps/macos/Sources/LuxelCore/Application/Localization/LuxelLocalization.swift"),
      "utf8"
    );
    const localeBlock = swift.match(/supportedLocales\s*=\s*\[([\s\S]*?)\]/)?.[1];
    const appLocales = [...(localeBlock?.matchAll(/"([^"]+)"/g) ?? [])].map((match) => match[1]);

    expect(appLocales).toEqual([...supportedLocales]);
  });

  test("has a complete, non-empty manual translation catalog for every locale", () => {
    const sourceCount = readJson("sources.json").length;

    for (const locale of translatedLocales) {
      const values = [
        ...readJson(`${locale}.json`),
        ...readJson(`${locale}-docs-1.json`),
        ...readJson(`${locale}-docs-2.json`)
      ];

      expect(values).toHaveLength(sourceCount);
      expect(values.every((value) => typeof value === "string" && value.trim().length > 0)).toBe(true);
    }
  });

  test("matches the app transcription language options exactly", () => {
    const settings = readFileSync(
      path.join(repositoryRoot, "apps/macos/Sources/LuxelApp/Settings/Views/LuxelSettingsView+Transcripts.swift"),
      "utf8"
    );
    const homepage = readFileSync(path.join(webRoot, "src/pages/index.astro"), "utf8");
    const appBlock = settings.match(/transcriptLanguageOptions: \[String\?\] = \[([\s\S]*?)\n    \]/)?.[1];
    const websiteBlock = homepage.match(/const transcriptionLanguages = \[([\s\S]*?)\n\];/)?.[1];
    const appIdentifiers = [...(appBlock?.matchAll(/"([^"]+)"/g) ?? [])].map((match) => match[1]);
    const websiteIdentifiers = [...(websiteBlock?.matchAll(/identifier: "([^"]+)"/g) ?? [])].map(
      (match) => match[1]
    );

    expect(websiteIdentifiers).toEqual(appIdentifiers);
  });
});

describe("browser language negotiation", () => {
  test.each([
    [["vi-VN"], "vi"],
    [["de-DE"], "de"],
    [["zh-CN"], "zh-Hans"],
    [["zh-SG"], "zh-Hans"],
    [["zh-TW", "en-US"], "en"],
    [["pt-BR"], "pt-BR"],
    [["pt-PT"], "pt-PT"],
    [["pt"], "pt-BR"],
    [["xx-YY", "fr-CA"], "fr"]
  ] as const)("resolves %j to %s", (preferences, expected) => {
    expect(resolvePreferredLocale(preferences)).toBe(expected);
  });

  test("ignores malformed language tags", () => {
    expect(resolvePreferredLocale(["not_a_locale_%%%", "it-IT"])).toBe("it");
  });
});

describe("static localized output", () => {
  test("uses the appropriate Portuguese regional documentation", () => {
    const brazil = readBuiltPage("pt-BR", "/docs");
    const portugal = readBuiltPage("pt-PT", "/docs");
    expect(brazil).toContain("Gravação de tela e áudio do sistema");
    expect(brazil).toContain("Avisos de Detecção de Fala");
    expect(brazil).not.toContain("A deteção de fala não está a ouvir");
    expect(portugal).toContain("Gravação do ecrã e do áudio do sistema");
    expect(portugal).toContain("Ficheiros recentes");
    expect(portugal).not.toContain("Arquivos recentes");
  });

  test("renders every page at a locale-prefixed URL", () => {
    for (const locale of translatedLocales) {
      for (const pagePath of publicPagePaths) {
        expect(readBuiltPage(locale, pagePath)).toContain(`<html lang="${locale}">`);
      }
    }
  });

  test("renders translated documentation without English fallback", () => {
    expect(readBuiltPage("de", "/docs")).toContain("Dokumentationsbereiche");
    expect(readBuiltPage("vi", "/docs")).toContain("Các phần tài liệu");
    expect(readBuiltPage("zh-Hans", "/docs")).toContain("文档章节");

    for (const locale of translatedLocales) {
      expect(readBuiltPage(locale, "/docs")).not.toContain("Documentation sections");
    }
  });

  test("renders the full transcription language list without English marketing fallback", () => {
    for (const locale of translatedLocales) {
      const html = readBuiltPage(locale, "/");
      const languageList = html.match(
        /<ul class="transcription-languages__list"[\s\S]*?<\/ul>/
      )?.[0];

      expect(languageList?.match(/<li>/g)).toHaveLength(29);
      expect(html).not.toContain("Luxel - Screen recorder and transcription for Mac");
      expect(html).not.toContain("Luxel is a Mac screen recorder for screen and system audio capture");
      expect(html).not.toContain("Record your Mac screen with system audio or your microphone");
      expect(html).not.toContain("Turn video and audio into searchable text on your Mac.");
      expect(html).not.toContain("All 29 supported transcription languages.");
      expect(html).not.toContain("Supported transcription languages");
    }
  });

  test("includes canonical and complete hreflang metadata", () => {
    const html = readBuiltPage("vi", "/docs");
    expect(html).toContain('<link rel="canonical" href="https://luxel.media/vi/docs">');

    for (const locale of supportedLocales) {
      expect(html).toContain(`hreflang="${locale}"`);
    }
    expect(html).toContain('hreflang="x-default"');
  });

  test("lists every public locale URL in the sitemap", () => {
    const sitemap = readFileSync(path.join(webRoot, "dist/client/sitemap.xml"), "utf8");

    for (const locale of supportedLocales) {
      for (const pagePath of publicPagePaths) {
        const url = new URL(localizedPath(locale, pagePath), "https://luxel.media").toString();
        expect(sitemap).toContain(`<loc>${url}</loc>`);
      }
    }
    expect(sitemap.match(/<loc>/g)).toHaveLength(46);
  });
});

function readJson(filename: string): string[] {
  return JSON.parse(readFileSync(path.join(translationsRoot, filename), "utf8")) as string[];
}

function readBuiltPage(locale: (typeof translatedLocales)[number], pagePath: (typeof publicPagePaths)[number]): string {
  const outputPath = localizedPath(locale, pagePath);
  return readFileSync(path.join(webRoot, "dist/client", outputPath, "index.html"), "utf8");
}
