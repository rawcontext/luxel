import { defineConfig } from "astro/config";
import vercel from "@astrojs/vercel";

export default defineConfig({
  site: "https://luxel.media",
  redirects: {
    "/cli": "/"
  },
  vite: {
    build: {
      cssMinify: "esbuild"
    }
  },
  output: "static",
  adapter: vercel({
    maxDuration: 10
  })
});
