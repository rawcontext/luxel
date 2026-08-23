#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  parseLocaleMetadata,
  parseTaggedJson,
  requiredLocales,
} from "./listing-metadata-support.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../../..");
const metadataPath = resolve(scriptDirectory, "listing-metadata.md");
const markdown = await readFile(metadataPath, "utf8");
const reviewNotes = await readFile(resolve(repositoryRoot, "docs/app-review/review-notes.txt"), "utf8");
const screenshotConfiguration = JSON.parse(
  await readFile(resolve(scriptDirectory, "localized-screenshot-headings.json"), "utf8"),
);
const committedScreenshotRoot = resolve(repositoryRoot, "docs/design/app-store-localized");
const committedScreenshotManifest = JSON.parse(
  await readFile(resolve(repositoryRoot, "docs/design/app-store-localized-manifest.json"), "utf8"),
);

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
  ["docs/design/app-store-05-menu-bar.png", "menu-bar"],
  ["docs/design/app-store-01-area-capture.png", "area-capture"],
  ["docs/design/app-store-06-transcripts.png", "transcripts"],
  ["docs/design/app-store-04-export.png", "export"],
  ["docs/design/app-store-03-recording-status.png", "recording-status"],
  ["docs/design/app-store-02-editor-trim.png", "editor-trim"],
];

function characterCount(value) {
  return Array.from(value).length;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const locales = parseLocaleMetadata(markdown);
const screenshotPlans = parseTaggedJson(markdown, "APP-STORE-SCREENSHOTS");
assert(screenshotPlans.length === 1, "Expected one APP-STORE-SCREENSHOTS JSON block");

const screenshotPlan = screenshotPlans[0];
assert(Array.isArray(screenshotPlan) && screenshotPlan.length === 6, "Expected six screenshots");
for (const [index, screenshot] of screenshotPlan.entries()) {
  assert(screenshot.position === index + 1, `Screenshot position ${index + 1} is missing or out of order`);
  const [expectedPath, expectedHeadingId] = screenshotReferences[index];
  assert(screenshot.referencePath === expectedPath, `Screenshot ${screenshot.position} must use ${expectedPath}`);
  assert(screenshot.headingId === expectedHeadingId, `Screenshot ${screenshot.position} must use heading ${expectedHeadingId}`);
  assert(screenshot.referenceSize === "2880x1800", `Screenshot ${screenshot.position} reference must be 2880x1800`);
  assert(screenshot.uploadStatus === "ready", `Screenshot ${screenshot.position} is not upload-ready`);
  const screenshotBuffer = await readFile(resolve(repositoryRoot, screenshot.referencePath));
  assert(screenshotBuffer.toString("ascii", 1, 4) === "PNG", `Screenshot ${screenshot.position} must be PNG`);
  const actualSize = `${screenshotBuffer.readUInt32BE(16)}x${screenshotBuffer.readUInt32BE(20)}`;
  assert(actualSize === screenshot.referenceSize, `Screenshot ${screenshot.position} is ${actualSize}, not ${screenshot.referenceSize}`);
  assert(![4, 6].includes(screenshotBuffer[25]), `Screenshot ${screenshot.position} must not have an alpha channel`);
}

assert(
  JSON.stringify(Object.keys(screenshotConfiguration.locales)) === JSON.stringify(requiredLocales),
  `Screenshot locales must appear in this order: ${requiredLocales.join(", ")}`,
);
assert(screenshotConfiguration.screenshots.length === screenshotPlan.length, "Screenshot configuration count is stale");
for (const [index, screenshot] of screenshotConfiguration.screenshots.entries()) {
  assert(screenshot.position === index + 1, `Configured screenshot position ${index + 1} is missing or out of order`);
  assert(screenshot.source === screenshotReferences[index][0], `Configured screenshot ${index + 1} has the wrong source`);
  assert(screenshot.id === screenshotReferences[index][1], `Configured screenshot ${index + 1} has the wrong heading ID`);
}
for (const locale of requiredLocales) {
  const headings = screenshotConfiguration.locales[locale];
  assert(headings && Object.keys(headings).length === screenshotPlan.length, `${locale}: screenshot headings are incomplete`);
  for (const screenshot of screenshotConfiguration.screenshots) {
    assert(typeof headings[screenshot.id] === "string" && headings[screenshot.id].trim(), `${locale}: ${screenshot.id} heading is empty`);
  }
}

assert(committedScreenshotManifest.schemaVersion === 1, "Localized screenshot manifest schema is unsupported");
assert(
  committedScreenshotManifest.width === 2_880 && committedScreenshotManifest.height === 1_800,
  "Localized screenshot manifest has the wrong dimensions",
);
assert(
  JSON.stringify(committedScreenshotManifest.locales) === JSON.stringify(requiredLocales),
  "Localized screenshot manifest locale order is stale",
);
assert(committedScreenshotManifest.files.length === 66, "Localized screenshot manifest must contain 66 files");
const manifestFiles = new Map(
  committedScreenshotManifest.files.map((file) => [`${file.locale}/${file.id}`, file]),
);
assert(manifestFiles.size === 66, "Localized screenshot manifest contains duplicate entries");

for (const locale of requiredLocales) {
  const expectedNames = [];
  for (const screenshot of screenshotConfiguration.screenshots) {
    const extension = locale === "en-US" ? "png" : "jpg";
    const outputName = `${String(screenshot.position).padStart(2, "0")}-${screenshot.outputStem}.${extension}`;
    const relativePath = `${locale}/${outputName}`;
    const manifestFile = manifestFiles.get(`${locale}/${screenshot.id}`);
    assert(manifestFile, `${locale}: missing ${screenshot.id} from localized screenshot manifest`);
    assert(manifestFile.position === screenshot.position, `${relativePath}: manifest position is stale`);
    assert(manifestFile.source === screenshot.source, `${relativePath}: manifest source is stale`);
    assert(manifestFile.output === relativePath, `${relativePath}: manifest output is stale`);
    assert(
      manifestFile.heading === screenshotConfiguration.locales[locale][screenshot.id],
      `${relativePath}: manifest heading is stale`,
    );

    const outputBuffer = await readFile(resolve(committedScreenshotRoot, relativePath));
    const outputDigest = createHash("sha256").update(outputBuffer).digest("hex");
    assert(manifestFile.sha256 === outputDigest, `${relativePath}: hash does not match the manifest`);
    assert(manifestFile.bytes === outputBuffer.length, `${relativePath}: byte count does not match the manifest`);
    if (locale === "en-US") {
      const sourceBuffer = await readFile(resolve(repositoryRoot, screenshot.source));
      assert(outputBuffer.equals(sourceBuffer), `${relativePath}: English output must exactly match its source master`);
    }
    expectedNames.push(outputName);
  }

  const committedNames = (await readdir(resolve(committedScreenshotRoot, locale))).sort();
  assert(
    JSON.stringify(committedNames) === JSON.stringify(expectedNames.sort()),
    `${locale}: checked-in localized screenshot set is incomplete`,
  );
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
  const configuredHeadings = screenshotConfiguration.screenshots.map(
    ({ id }) => screenshotConfiguration.locales[entry.locale][id],
  );
  assert(
    JSON.stringify(entry.screenshotCaptions) === JSON.stringify(configuredHeadings),
    `${entry.locale}: screenshot captions must match the rendered headings`,
  );
}

const reviewNoteBytes = Buffer.byteLength(reviewNotes, "utf8");
assert(reviewNoteBytes > 0, "App Review notes are empty");
assert(reviewNoteBytes <= 4_000, `App Review notes are ${reviewNoteBytes} bytes; limit is 4000`);

console.log(
  `Validated ${locales.length} localized listings, ${screenshotPlan.length} localized screenshot masters, `
    + `and ${reviewNoteBytes} bytes of App Review notes.`,
);
