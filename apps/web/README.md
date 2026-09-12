# Luxel marketing website

The Astro website is the `@luxel/web` workspace. Run commands from the monorepo root:

```sh
bun install --frozen-lockfile
bun run vercel-build
bun run test --filter=@luxel/web
```

The filtered build runs only the website and caches both `dist/` and `.vercel/output/`.
It does not build the macOS app or the Rust CLI.

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

Vercel Hobby does not support automatic Git deployments from private organization
repositories. Git-triggered deployments can resume when this repository becomes
public, or when the Vercel project uses a plan that supports private organization
repositories. Keep the repository private until its planned public release.

## CLI links and downloads

Source and documentation links point to
[`apps/cli`](https://github.com/rawcontext/luxel/tree/master/apps/cli), where the CLI
README lives. These GitHub links require repository access while the monorepo is private.

The installer targets the monorepo's `cli-v1.0.0` release. Source links and anonymous
release downloads return 404 while the repository is private. Keep the CLI's
versioned download URL aligned with published `cli-v<version>` release assets.
