# Luxel marketing website

The Astro website is the `@luxel/web` workspace. Run commands from the monorepo root:

```sh
bun install --frozen-lockfile
bun run vercel-build
bun run test --filter=@luxel/web
```

The filtered build runs only the website and caches both `dist/` and `.vercel/output/`.
It does not build the macOS app or the Rust CLI.
Installer checks run in the website's `test` task after the build, alongside the
localization tests. Vercel builds do not run the test suite.

## Vercel

The `luxel-media` project uses:

- Git repository: `rawcontext/luxel`, production branch `master`
- Root directory: `apps/web`, with source files outside the root included
- Framework: Astro
- Install command: `bun install --frozen-lockfile`
- Build command: `bun run --cwd ../.. vercel-build`
- Output directory: detected by the Astro Vercel adapter

Run Vercel CLI commands from a clean checkout of the monorepo root. After linking the project, an
authenticated production deployment uses:

```sh
vercel pull --yes --environment=production
vercel build --prod
vercel deploy --prebuilt --prod
```

The repository is public, so the Vercel GitHub integration can deploy it on the
Hobby plan. Updates to `master` trigger production deployments. Other branches
use preview deployments. The former private-organization restriction no longer
applies.

## CLI links and downloads

Source and documentation links point to
[`apps/cli`](https://github.com/rawcontext/luxel/tree/master/apps/cli), where the CLI
README lives. These links are publicly accessible.

The installer targets the monorepo's public `cli-v1.0.0` release. Keep the CLI's
versioned download URL aligned with published `cli-v<version>` release assets.
