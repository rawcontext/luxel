import { readFile, writeFile } from "node:fs/promises";

const config = JSON.parse(await readFile(process.argv[2], "utf8"));
process.env.PUBLIC_TURNSTILE_SITE_KEY = config.turnstileSiteKey;
process.env.LUXEL_SITE_URL = config.siteUrl;

const { build } = await import("astro");
await build({ root: new URL("../", import.meta.url), site: config.siteUrl });
await import("./generate-llms.mjs");

const outputConfigPath = new URL("../.vercel/output/config.json", import.meta.url);
const outputConfig = JSON.parse(await readFile(outputConfigPath, "utf8"));
outputConfig.cache = [
  "apps/web/.vercel/cache/bazel/actions/**",
  "apps/web/.vercel/cache/bazel/repository/content_addressable/**",
  "apps/web/.vercel/cache/bazel/bazelisk/**"
];
await writeFile(outputConfigPath, JSON.stringify(outputConfig, null, 2) + "\n");
