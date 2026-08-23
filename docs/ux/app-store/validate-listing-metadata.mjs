#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
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
const screenshotReferences = [
  ["apps/web/public/screenshots/luxel-menu-capture-under-menu-bar.png", "1114x896"],
  ["apps/web/public/screenshots/luxel-settings-speech-detection.png", "2064x1744"],
  ["apps/web/public/screenshots/luxel-area-selection.png", "1200x870"],
  ["apps/web/public/screenshots/luxel-settings-transcripts.png", "1830x1235"],
  ["apps/web/public/screenshots/luxel-editor-loaded.png", "1800x1184"],
  ["apps/web/public/screenshots/luxel-menu-bar-recording-status.png", "1162x736"],
  ["apps/web/public/screenshots/luxel-audio-transcript-editor.png", "2224x1648"],
];
const canonicalSpeechScreenshotHash = "1a8051f2d614d27eb301063db1cf58e9ce3ccac151f81c79eae20dadc167db6c";

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
const screenshotBuffers = [];
for (const [index, screenshot] of screenshotPlan.entries()) {
  assert(screenshot.position === index + 1, `Screenshot position ${index + 1} is missing or out of order`);
  const [expectedPath, expectedSize] = screenshotReferences[index];
  assert(screenshot.referencePath === expectedPath, `Screenshot ${screenshot.position} must use ${expectedPath}`);
  assert(screenshot.referenceSize === expectedSize, `Screenshot ${screenshot.position} reference must be ${expectedSize}`);
  assert(
    screenshot.referencePath.startsWith("apps/web/public/screenshots/"),
    `Screenshot ${screenshot.position} must use a real apps/web screenshot reference`,
  );
  assert(!screenshot.referencePath.includes("docs/design"), `Screenshot ${screenshot.position} uses a legacy composite`);
  assert(screenshot.requiredUploadSize === "2880x1800", `Screenshot ${screenshot.position} must be recaptured at 2880x1800`);
  assert(screenshot.uploadStatus === "recapture-required", `Screenshot ${screenshot.position} is not upload-ready`);
  assert(screenshot.referenceSize !== screenshot.requiredUploadSize, `Screenshot ${screenshot.position} incorrectly claims upload readiness`);
  const screenshotBuffer = await readFile(resolve(repositoryRoot, screenshot.referencePath));
  assert(screenshotBuffer.toString("ascii", 1, 4) === "PNG", `Screenshot ${screenshot.position} must be PNG`);
  const actualSize = `${screenshotBuffer.readUInt32BE(16)}x${screenshotBuffer.readUInt32BE(20)}`;
  assert(actualSize === screenshot.referenceSize, `Screenshot ${screenshot.position} is ${actualSize}, not ${screenshot.referenceSize}`);
  screenshotBuffers.push(screenshotBuffer);
}

const canonicalSpeechScreenshotDigest = createHash("sha256").update(screenshotBuffers[1]).digest("hex");
assert(
  canonicalSpeechScreenshotDigest === canonicalSpeechScreenshotHash,
  "Canonical Speech Detection screenshot hash changed",
);

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
  `Validated ${locales.length} localized listings, ${screenshotPlan.length} recapture references, `
    + `and ${reviewNoteBytes} bytes of App Review notes.`,
);
