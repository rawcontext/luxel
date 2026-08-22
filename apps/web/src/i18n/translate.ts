import { load } from "cheerio";
import type { AnyNode, Element } from "domhandler";

import { defaultLocale, type Locale } from "./config";
import { translate } from "./text";

const translatedAttributes = ["alt", "aria-label", "placeholder", "title"] as const;
const skippedElements = new Set(["code", "kbd", "pre", "script", "style", "svg"]);

export function localizeHtml(html: string, locale: Locale): string {
  if (locale === defaultLocale) {
    return html;
  }

  const $ = load(html, null, false);

  $("*").each((_, element) => {
    const tagName = element.tagName.toLowerCase();
    if (skippedElements.has(tagName) || hasSkippedAncestor(element)) {
      return;
    }

    for (const attribute of translatedAttributes) {
      const source = $(element).attr(attribute);
      if (source) {
        $(element).attr(attribute, translate(locale, normalizeWhitespace(source)));
      }
    }

    for (const node of element.childNodes) {
      if (node.type !== "text") {
        continue;
      }

      const firstNonWhitespace = node.data.search(/\S/u);
      if (firstNonWhitespace === -1) {
        continue;
      }

      const lastNonWhitespace = node.data.search(/\s*$/u);
      const source = node.data.slice(firstNonWhitespace, lastNonWhitespace);
      const localized = translate(locale, normalizeWhitespace(source));
      node.data = `${node.data.slice(0, firstNonWhitespace)}${localized}${node.data.slice(lastNonWhitespace)}`;
    }
  });

  return $.html();
}

function hasSkippedAncestor(element: Element): boolean {
  let parent: AnyNode | null = element.parent;
  while (parent && parent.type !== "root") {
    if (parent.type === "tag" && skippedElements.has(parent.tagName.toLowerCase())) {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}

function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/gu, " ").trim();
}
