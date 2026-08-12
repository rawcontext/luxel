import { defineConfig } from "astro/config";
import vercel from "@astrojs/vercel";

export default defineConfig({
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
