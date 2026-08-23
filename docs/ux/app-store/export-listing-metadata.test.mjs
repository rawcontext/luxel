import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { exportListingMetadata } from "./export-listing-metadata.mjs";
import {
  fastlaneMetadataFiles,
  parseLocaleMetadata,
} from "./listing-metadata-support.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const sourcePath = resolve(scriptDirectory, "listing-metadata.md");
const reviewNotesPath = resolve(scriptDirectory, "../../app-review/review-notes.txt");

async function readTree(rootPath) {
  const files = {};

  for (const locale of await readdir(rootPath)) {
    for (const fileName of await readdir(join(rootPath, locale))) {
      files[`${locale}/${fileName}`] = await readFile(join(rootPath, locale, fileName), "utf8");
    }
  }

  return files;
}

test("exports locale metadata and only exact review notes to a deterministic tree", async (context) => {
  const temporaryRoot = await mkdtemp(join(tmpdir(), "luxel-app-store-metadata-"));
  context.after(() => rm(temporaryRoot, { recursive: true, force: true }));
  const firstOutput = join(temporaryRoot, "first");
  const secondOutput = join(temporaryRoot, "second");

  await exportListingMetadata({ sourcePath, outputPath: firstOutput });
  await exportListingMetadata({ sourcePath, outputPath: secondOutput });

  const firstTree = await readTree(firstOutput);
  const secondTree = await readTree(secondOutput);
  const markdown = await readFile(sourcePath, "utf8");
  const locales = parseLocaleMetadata(markdown);

  assert.deepEqual(firstTree, secondTree);
  assert.equal(
    Object.keys(firstTree).length,
    locales.length * Object.keys(fastlaneMetadataFiles).length + 1,
  );

  for (const entry of locales) {
    for (const [field, fileName] of Object.entries(fastlaneMetadataFiles)) {
      assert.equal(firstTree[`${entry.locale}/${fileName}`], entry[field]);
    }
  }

  assert.deepEqual(
    await readFile(join(firstOutput, "review_information", "notes.txt")),
    await readFile(reviewNotesPath),
  );
  assert.deepEqual(await readdir(join(firstOutput, "review_information")), ["notes.txt"]);
  assert.equal(Object.keys(firstTree).some((path) => /screenshot|\.(png|jpe?g)$/iu.test(path)), false);
});

test("refuses to write into an existing output directory", async (context) => {
  const temporaryRoot = await mkdtemp(join(tmpdir(), "luxel-app-store-metadata-"));
  context.after(() => rm(temporaryRoot, { recursive: true, force: true }));
  const outputPath = join(temporaryRoot, "existing");
  await mkdir(outputPath);

  await assert.rejects(
    exportListingMetadata({ sourcePath, outputPath }),
    /file already exists/iu,
  );
});
