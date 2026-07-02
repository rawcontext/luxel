#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import * as cheerio from "cheerio";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";

const siteUrl = process.env.LUXEL_SITE_URL ?? "https://luxel.media";
const appRoot = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const distDir = path.join(appRoot, "dist");
const docsHtmlPath = path.join(distDir, "docs", "index.html");

const projectSummary =
  "Luxel is a native macOS menu bar recorder for screen capture, replay buffer clips, local transcripts, command-line automation, and polished exports.";

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

This file is generated during the Luxel website build. Use the full Markdown export for complete user documentation, and use the canonical website links for browser-readable pages.

## Documentation

- [Luxel documentation](${siteUrl}/docs): Canonical human-readable documentation for installation, permissions, capture, replay buffer, editing, export, transcripts, CLI, automation, localization, settings, and troubleshooting.
- [Complete Luxel documentation Markdown](${siteUrl}/llms-full.txt): Full Markdown mirror generated from the published documentation page.

## Website

- [Luxel marketing site](${siteUrl}/): Product overview, feature summary, screenshots, and CLI demo.
`);

const llmsFull = normalizeMarkdown(`# Luxel Documentation

> Complete Markdown mirror of the public Luxel documentation.

Source: ${siteUrl}/docs

This file is generated during the Luxel website build from the built Astro documentation page.

${docsMarkdown}
`);

const sitemapUrls = [
  { path: "/", changefreq: "weekly", priority: "1.0" },
  { path: "/docs", changefreq: "weekly", priority: "0.8" },
  { path: "/llms.txt", changefreq: "weekly", priority: "0.4" },
  { path: "/llms-full.txt", changefreq: "weekly", priority: "0.4" }
];

const sitemap = buildSitemap(sitemapUrls, siteUrl);

await mkdir(distDir, { recursive: true });
await Promise.all([
  writeFile(path.join(distDir, "llms.txt"), `${llmsIndex}\n`, "utf8"),
  writeFile(path.join(distDir, "llms-full.txt"), `${llmsFull}\n`, "utf8"),
  writeFile(path.join(distDir, "sitemap.xml"), `${sitemap}\n`, "utf8")
]);

console.log("Generated dist/llms.txt, dist/llms-full.txt, and dist/sitemap.xml");

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
