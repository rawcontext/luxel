import { cp, readFile, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const config = JSON.parse(await readFile(process.argv[2], "utf8"));
process.env.PUBLIC_TURNSTILE_SITE_KEY = config.turnstileSiteKey;
process.env.LUXEL_SITE_URL = config.siteUrl;

const { build } = await import("astro");
const sourceDirectory = new URL("../.astro-build-src/", import.meta.url);
try {
  // Rolldown resolves Bazel's source symlinks outside the sandbox, losing Astro's page-to-asset mapping.
  await cp(new URL("../src", import.meta.url), sourceDirectory, { recursive: true, dereference: true });
  await build({
    root: new URL("../", import.meta.url),
    srcDir: fileURLToPath(sourceDirectory),
    site: config.siteUrl
  });
} finally {
  await rm(sourceDirectory, { recursive: true, force: true });
}
await import("./generate-llms.mjs");
