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

export async function exportListingMetadata({ sourcePath = defaultSourcePath, outputPath }) {
  if (!outputPath) {
    throw new Error("An output directory is required");
  }

  const markdown = await readFile(sourcePath, "utf8");
  const locales = parseLocaleMetadata(markdown);
  await mkdir(outputPath);

  for (const entry of locales) {
    const localePath = resolve(outputPath, entry.locale);
    await mkdir(localePath);

    for (const [field, fileName] of Object.entries(fastlaneMetadataFiles)) {
      await writeFile(resolve(localePath, fileName), entry[field], "utf8");
    }
  }

  return locales.length;
}

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  const outputPath = process.argv[2] && resolve(process.argv[2]);

  try {
    const localeCount = await exportListingMetadata({ outputPath });
    console.log(`Exported ${localeCount} App Store locales to ${outputPath}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
