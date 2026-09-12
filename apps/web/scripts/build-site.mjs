import { readFile } from "node:fs/promises";

const config = JSON.parse(await readFile(process.argv[2], "utf8"));
process.env.PUBLIC_TURNSTILE_SITE_KEY = config.turnstileSiteKey;
process.env.LUXEL_SITE_URL = config.siteUrl;

const { build } = await import("astro");
await build({ root: new URL("../", import.meta.url), site: config.siteUrl });
await import("./generate-llms.mjs");
