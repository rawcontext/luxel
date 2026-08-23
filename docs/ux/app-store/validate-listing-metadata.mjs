#!/usr/bin/env node

import { readFile, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../../..");
const metadataPath = resolve(scriptDirectory, "listing-metadata.md");
const markdown = await readFile(metadataPath, "utf8");
const reviewNotes = await readFile(resolve(repositoryRoot, "docs/app-review/review-notes.txt"), "utf8");

const requiredLocales = [
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
const requiredFields = [
  "name",
  "subtitle",
  "promotionalText",
  "description",
  "keywords",
  "whatsNew",
  "marketingUrl",
  "supportUrl",
  "privacyPolicyUrl",
  "screenshotCaptions",
];
const characterLimits = {
  name: 30,
  subtitle: 30,
  promotionalText: 170,
  description: 4_000,
  whatsNew: 4_000,
};

function parseTaggedJson(tag) {
  const pattern = new RegExp(
    "<!-- " + tag + " -->\\s*```json\\s*([\\s\\S]*?)\\s*```",
    "g",
  );
  return [...markdown.matchAll(pattern)].map((match) => JSON.parse(match[1]));
}

function characterCount(value) {
  return Array.from(value).length;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const locales = parseTaggedJson("APP-STORE-LOCALE");
const screenshotPlans = parseTaggedJson("APP-STORE-SCREENSHOTS");
assert(screenshotPlans.length === 1, "Expected one APP-STORE-SCREENSHOTS JSON block");

const screenshotPlan = screenshotPlans[0];
assert(Array.isArray(screenshotPlan) && screenshotPlan.length === 7, "Expected seven screenshots");
for (const [index, screenshot] of screenshotPlan.entries()) {
  assert(screenshot.position === index + 1, `Screenshot position ${index + 1} is missing or out of order`);
  const expectedSize = screenshot.position === 2 ? "2064x1744" : "2880x1800";
  assert(screenshot.size === expectedSize, `Screenshot ${screenshot.position} must be ${expectedSize}`);
  assert(typeof screenshot.sourcePath === "string", `Screenshot ${screenshot.position} needs a sourcePath`);
  await stat(resolve(repositoryRoot, screenshot.sourcePath));
  if (screenshot.capturePath) {
    await stat(resolve(repositoryRoot, screenshot.capturePath));
  }
}

assert(locales.length === requiredLocales.length, `Expected ${requiredLocales.length} locale blocks`);
assert(
  JSON.stringify(locales.map(({ locale }) => locale)) === JSON.stringify(requiredLocales),
  `Locale blocks must appear in this order: ${requiredLocales.join(", ")}`,
);

for (const entry of locales) {
  for (const field of requiredFields) {
    assert(entry[field] !== undefined, `${entry.locale}: missing ${field}`);
  }

  for (const [field, limit] of Object.entries(characterLimits)) {
    const count = characterCount(entry[field]);
    assert(count > 0, `${entry.locale}: ${field} is empty`);
    assert(count <= limit, `${entry.locale}: ${field} is ${count} characters; limit is ${limit}`);
    assert(entry.counts?.[field] === count, `${entry.locale}: update counts.${field} to ${count}`);
  }

  const keywordBytes = Buffer.byteLength(entry.keywords, "utf8");
  assert(keywordBytes <= 100, `${entry.locale}: keywords are ${keywordBytes} bytes; limit is 100`);
  assert(entry.counts?.keywordBytes === keywordBytes, `${entry.locale}: update counts.keywordBytes to ${keywordBytes}`);
  assert(!/(luxel|raw context)/iu.test(entry.keywords), `${entry.locale}: keywords repeat app or company name`);
  for (const keyword of entry.keywords.split(",")) {
    assert(characterCount(keyword.trim()) > 2, `${entry.locale}: keyword must be longer than two characters: ${keyword}`);
  }

  for (const field of ["marketingUrl", "supportUrl", "privacyPolicyUrl"]) {
    const url = new URL(entry[field]);
    assert(url.protocol === "https:", `${entry.locale}: ${field} must use HTTPS`);
  }

  assert(
    Array.isArray(entry.screenshotCaptions) && entry.screenshotCaptions.length === screenshotPlan.length,
    `${entry.locale}: expected ${screenshotPlan.length} screenshot captions`,
  );
  assert(entry.screenshotCaptions.every((caption) => caption.trim()), `${entry.locale}: screenshot caption is empty`);
}

const reviewNoteBytes = Buffer.byteLength(reviewNotes, "utf8");
assert(reviewNoteBytes > 0, "App Review notes are empty");
assert(reviewNoteBytes <= 4_000, `App Review notes are ${reviewNoteBytes} bytes; limit is 4000`);

console.log(
  `Validated ${locales.length} localized listings, ${screenshotPlan.length} screenshots, `
    + `and ${reviewNoteBytes} bytes of App Review notes.`,
);
