#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  fastlaneMetadataFiles,
  parseLocaleMetadata,
} from "./listing-metadata-support.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const scriptDirectory = dirname(scriptPath);
const defaultSourcePath = resolve(scriptDirectory, "listing-metadata.md");
const defaultReviewNotesPath = resolve(scriptDirectory, "../../app-review/review-notes.txt");

export async function exportListingMetadata({
  sourcePath = defaultSourcePath,
  reviewNotesPath = defaultReviewNotesPath,
  outputPath,
}) {
  if (!outputPath) {
    throw new Error("An output directory is required");
  }

  const markdown = await readFile(sourcePath, "utf8");
  const locales = parseLocaleMetadata(markdown);
  const reviewNotes = await readFile(reviewNotesPath);
  if (reviewNotes.length === 0) {
    throw new Error("App Review notes are empty");
  }

  await mkdir(outputPath);

  for (const entry of locales) {
    const localePath = resolve(outputPath, entry.locale);
    await mkdir(localePath);

    for (const [field, fileName] of Object.entries(fastlaneMetadataFiles)) {
      await writeFile(resolve(localePath, fileName), entry[field], "utf8");
    }
  }

  const reviewInformationPath = resolve(outputPath, "review_information");
  await mkdir(reviewInformationPath);
  await writeFile(resolve(reviewInformationPath, "notes.txt"), reviewNotes);

  return locales.length;
}

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  const outputPath = process.argv[2] && resolve(process.argv[2]);

  try {
    const localeCount = await exportListingMetadata({ outputPath });
    console.log(`Exported ${localeCount} App Store locales and review notes to ${outputPath}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
