#!/usr/bin/env node
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import * as cheerio from "cheerio";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";

const siteUrl = process.env.LUXEL_SITE_URL ?? "https://luxel.media";
const appRoot = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const distDir = path.join(appRoot, "dist");
const outputDirs = await existingOutputDirs([
  path.join(distDir, "client"),
  distDir,
  path.join(appRoot, ".vercel", "output", "static")
]);
const primaryOutputDir = outputDirs[0] ?? distDir;
const docsHtmlPath = path.join(primaryOutputDir, "docs", "index.html");

const projectSummary =
  "Luxel is a Mac menu bar recorder for screen capture, replay buffer clips, local transcripts, command-line automation, and polished exports.";
const localizedLocales = [
  "de",
  "es",
  "fr",
  "it",
  "ja",
  "ko",
  "vi",
  "zh-Hans",
  "pt-BR",
  "pt-PT"
];
const publicPages = [
  { path: "/", changefreq: "weekly", priority: "1.0" },
  { path: "/docs", changefreq: "weekly", priority: "0.8" },
  { path: "/support", changefreq: "monthly", priority: "0.6" },
  { path: "/privacy", changefreq: "monthly", priority: "0.6" }
];

const html = await readFile(docsHtmlPath, "utf8");
const $ = cheerio.load(html);
const docsContent = $(".docs-content").first();

if (docsContent.length === 0) {
  throw new Error(`Could not find .docs-content in ${docsHtmlPath}`);
}

docsContent.find("script, style, noscript, svg, img, video, source, figure").remove();
docsContent.find(".docs-eyebrow").remove();
docsContent.find(".shortcut-keys").each((_, element) => {
  const labels = $(element)
    .find("kbd")
    .map((__, key) => $(key).attr("title") ?? $(key).text())
    .get()
    .map((label) => label.trim())
    .filter(Boolean);

  if (labels.length > 0) {
    $(element).replaceWith(`<code>${escapeHtml(labels.join("+"))}</code>`);
  }
});
docsContent.find("kbd").each((_, element) => {
  const label = $(element).attr("title") ?? $(element).text();
  $(element).replaceWith(`<code>${escapeHtml(label.trim())}</code>`);
});

const turndown = new TurndownService({
  bulletListMarker: "-",
  codeBlockStyle: "fenced",
  headingStyle: "atx",
  hr: "---",
  strongDelimiter: "**"
});

turndown.use(gfm);

const docsMarkdown = normalizeMarkdown(turndown.turndown(docsContent.html() ?? ""));

const llmsIndex = normalizeMarkdown(`# Luxel

> ${projectSummary}

## Documentation

- [Luxel documentation](${siteUrl}/docs): Canonical human-readable documentation for installation, permissions, capture, replay buffer, editing, export, transcripts, CLI, automation, localization, settings, and troubleshooting.
- [Complete Luxel documentation Markdown](${siteUrl}/llms-full.txt): Complete text of the Luxel documentation.
- [Install the Luxel CLI](${siteUrl}/cli/install.sh): Shell installer for the standalone Luxel command.
- [Luxel CLI source and installation](https://github.com/rawcontext/luxel/tree/master/apps/cli): Rust command-line client in the Luxel monorepo, with installation and development instructions.

## Website

- [Luxel marketing site](${siteUrl}/): Product overview, feature summary, screenshots, and CLI demo.
- [Luxel support](${siteUrl}/support): Contact form for bug reports, feature requests, and support questions.
- [Luxel privacy policy](${siteUrl}/privacy): Privacy policy for the Luxel Mac app and marketing website.
`);

const llmsFull = normalizeMarkdown(`# Luxel Documentation

> Luxel installation, capture, editing, export, transcription, CLI, and troubleshooting documentation.

${docsMarkdown}
`);

const sitemapUrls = [
  ...publicPages,
  ...localizedLocales.flatMap((locale) => publicPages.map((page) => ({
    ...page,
    path: page.path === "/" ? `/${locale}/` : `/${locale}${page.path}`
  }))),
  { path: "/llms.txt", changefreq: "weekly", priority: "0.4" },
  { path: "/llms-full.txt", changefreq: "weekly", priority: "0.4" }
];

const sitemap = buildSitemap(sitemapUrls, siteUrl);

await Promise.all(outputDirs.flatMap(async (outputDir) => {
  await mkdir(outputDir, { recursive: true });
  return Promise.all([
    writeFile(path.join(outputDir, "llms.txt"), `${llmsIndex}\n`, "utf8"),
    writeFile(path.join(outputDir, "llms-full.txt"), `${llmsFull}\n`, "utf8"),
    writeFile(path.join(outputDir, "sitemap.xml"), `${sitemap}\n`, "utf8")
  ]);
}));

console.log(`Generated llms.txt, llms-full.txt, and sitemap.xml in ${outputDirs.length} output director${outputDirs.length === 1 ? "y" : "ies"}`);

async function existingOutputDirs(candidates) {
  const seen = new Set();
  const dirs = [];

  for (const candidate of candidates) {
    if (seen.has(candidate)) {
      continue;
    }
    seen.add(candidate);

    if (await isDirectory(candidate)) {
      dirs.push(candidate);
    }
  }

  return dirs.length > 0 ? dirs : [distDir];
}

async function isDirectory(candidate) {
  try {
    return (await stat(candidate)).isDirectory();
  } catch {
    return false;
  }
}

function normalizeMarkdown(value) {
  return value
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function buildSitemap(urls, baseUrl) {
  const origin = baseUrl.replace(/\/+$/, "");

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...urls.map(({ path: urlPath, changefreq, priority }) => [
      "  <url>",
      `    <loc>${escapeXml(`${origin}${urlPath}`)}</loc>`,
      `    <changefreq>${changefreq}</changefreq>`,
      `    <priority>${priority}</priority>`,
      "  </url>"
    ].join("\n")),
    "</urlset>"
  ].join("\n");
}

function escapeXml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}
