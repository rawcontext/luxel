# Luxel marketing website

The Astro/TypeScript website is built and checked through Bazel:

```sh
bazel build //apps/web:build
bazel test //apps/web:tests //apps/web:lint
bazel run //apps/web:dev
```

Use `ibazel run //apps/web:dev` for continuous synchronization while editing. The website target does not compile the macOS app or Rust CLI. Its localization tests declare the Swift locale definitions as inputs so cross-language contract changes invalidate the tests.

Dependencies are resolved from the root `pnpm-lock.yaml`. Bazel supplies Node.js and Bun; installing workspace `node_modules` is optional for editor tooling.

## Vercel

The `luxel-media` project uses `rawcontext/luxel`, root directory `apps/web`, and production branch `master`. The checked-in `vercel.json` selects the custom Bazel build and Vercel Build Output API. The generated output retains Astro's routes and server function for the support form.

`tools/bazel/vercel-build.sh` builds only the website, exports its declared output to `apps/web/.vercel/output`, and keeps Bazel action, repository archive, and Bazelisk caches under `node_modules/.cache/bazel` on Vercel. This uses Vercel’s persisted dependency cache; unpacked repository trees remain outside it. Pull-request previews build the site without running unit tests.

For a local export:

```sh
bash tools/bazel/vercel-build.sh
```

Public build configuration is explicit in Bazel's cache keys:

```sh
bazel build //apps/web:build --//apps/web:site_url=https://luxel.media
```

The export script forwards `PUBLIC_TURNSTILE_SITE_KEY` and `LUXEL_SITE_URL` to the website's build settings. Private support credentials are runtime Vercel environment variables.

## CLI links and downloads

Source and documentation links point to [`apps/cli`](https://github.com/rawcontext/luxel/tree/master/apps/cli). The installer uses the public monorepo `cli-v1.0.0` release; keep its download URL aligned with published CLI release assets.
