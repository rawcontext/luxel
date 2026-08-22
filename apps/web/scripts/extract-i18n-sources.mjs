#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { load } from "cheerio";

const appRoot = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const outputPath = path.join(appRoot, "src", "i18n", "translations", "sources.json");
const pages = ["index.html", "support/index.html", "privacy/index.html"];
const sources = new Set();

for (const page of pages) {
  await addPageSources(page);
}

for (const source of [
  "Luxel - Screen recording for Mac",
  "Luxel is a Mac menu bar recorder for screen capture, replay buffer clips, local transcripts, command-line automation, and polished exports.",
  "Page sections",
  "Luxel Documentation",
  "Luxel user documentation for installation, permissions, capture, replay buffer, editing, export, transcripts, command-line control, automation, localization, settings, and troubleshooting.",
  "Documentation navigation",
  "Privacy Policy - Luxel",
  "Luxel privacy policy for the Mac recorder and Luxel marketing website.",
  "Privacy page navigation",
  "Support - Luxel",
  "Contact Luxel support with a bug report, feature request, or product question.",
  "Support page navigation",
  "Luxel LLM-readable index",
  "Luxel full Markdown documentation",
  "Sending...",
  "Could not send the report.",
  "Thank you for your submission.",
  "Method not allowed.",
  "Could not read the support request.",
  "Email and message are required.",
  "Enter a valid email address.",
  "Message is too long.",
  "Support submissions are not configured yet.",
  "Please complete the anti-spam check and try again.",
  "Could not create the support request. Please try again later.",
  "Report sent."
]) {
  sources.add(source);
}

await addPageSources("docs/index.html");

const serializedSources = `${JSON.stringify([...sources], null, 2)}\n`;

if (process.argv.includes("--check")) {
  const currentSources = await readFile(outputPath, "utf8");
  if (currentSources !== serializedSources) {
    throw new Error("The website localization source catalog is out of date. Run `bun run i18n:extract` after updating the English page content, then add every translation.");
  }
  console.log(`Verified ${sources.size} English localization sources`);
} else {
  await writeFile(outputPath, serializedSources, "utf8");
  console.log(`Wrote ${sources.size} English localization sources to ${outputPath}`);
}

async function addPageSources(page) {
  const html = await readFile(path.join(appRoot, "dist", "client", page), "utf8");
  const $ = load(html);

  $("main *").each((_, element) => {
    if ($(element).closest("code,kbd,pre,script,style,svg").length > 0) {
      return;
    }

    for (const attribute of ["alt", "aria-label", "placeholder", "title"]) {
      const value = normalize($(element).attr(attribute));
      if (value) {
        sources.add(value);
      }
    }

    for (const node of element.childNodes) {
      if (node.type !== "text") {
        continue;
      }

      const value = normalize(node.data);
      if (value) {
        sources.add(value);
      }
    }
  });
}

function normalize(value) {
  return value?.replace(/\s+/gu, " ").trim() ?? "";
}
