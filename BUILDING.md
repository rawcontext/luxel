# Building Luxel

Bazel is the build and test entry point for the Swift macOS app, Rust CLI, and
TypeScript/Astro website. It also owns the metadata, screenshot, and automation
checks. Signing and publication consume Bazel outputs and run outside the build
cache.

## Toolchains

Install Bazelisk and Xcode 26.6 on an Apple silicon Mac. `.bazelversion` pins
Bazel 9.2.0, and `MODULE.bazel` pins language rules and downloaded tools. Node.js,
Bun, Rust, Python, Ruby, and lint tools are supplied by Bazel; workspace
`node_modules` and global Cargo build products are not build inputs.

The Python build runtime is 3.13.13 because that is the latest 3.13 runtime in the
pinned `rules_python` manifest; it does not yet contain the developer-tools pin
3.13.15. SwiftLint remains at 0.65.1 with the existing lint rules unchanged.

CI uses Xcode 26.6. If a newer macOS release requires another Xcode for local
development, select its version and developer directory together in an ignored
`.bazelrc.local`. For example, on a machine with Xcode 27 installed at that path:

```text
common --repo_env=DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
build --xcode_version=27.0
```

## Targets

Run commands from the repository root:

| Work | Command |
| --- | --- |
| All product builds | `bazel build //:build` |
| Complete build graph | `bazel build //...` |
| Tests and standard lint gates | `bazel test //:tests //:lint` |
| Swift tests | `bazel test //apps/macos:tests` |
| Focused Swift tests | `bazel test //apps/macos:core_tests --test_filter=UserDefaultsSettingsStoreTests` |
| Rust tests and lint | `bazel test //apps/cli:tests //apps/cli:lint` |
| Universal CLI package | `bazel build --config=release //apps/cli:package` |
| Website build and tests | `bazel build //apps/web:build` and `bazel test //apps/web:tests` |
| Website development | `bazel run //apps/web:dev` |
| App Store metadata | `bazel build //app-store:metadata` |
| Localized screenshots | `bazel build //app-store:localized_screenshots` |
| Optional duplication check | `bazel test //:duplication` |

The duplication check retains its previous explicit, opt-in role; standard lint
does not introduce a new duplication threshold. Test runner binaries prefixed
with `_` are implementation details, not additional test suites.

Use `bazel cquery <target> --output=files` when a script needs the output path.
Apple architecture transitions can place outputs outside the default
`bazel-bin` directory. CLI archives and checksums are in
`bazel-bin/apps/cli/dist/` after building the package target.

## Caching and isolation

Local action results live in `~/.cache/luxel/bazel/actions`. Repository downloads
live under `~/.cache/luxel/bazel/repository`. GitHub Actions persists the action
cache and downloaded archives between jobs and runs; it avoids uploading the
large unpacked repository trees and output bases. Completed actions are saved
even if a later check fails.

Builds, lint checks, test results, license checks, model audits, metadata, and
screenshot rendering are cacheable. Inputs include source files, dependency
locks, tools, public website settings, and relevant runtime identity. Changing a
website setting does not invalidate Swift or Rust work. Signing keys, provisioning
profiles, Fastlane credentials, and signed upload packages are excluded from
Bazel inputs and cached outputs.

Swift tests run serially within each suite using Swift Testing. Fixtures are
materialized into writable test directories so model integrity checks do not
mistake Bazel's runfile symlinks for bundled application symlinks. The AppKit suite
and the small security-scoped bookmark suite require host services and run
outside the process sandbox; other tests retain sandboxing. Native test cache
keys include the operating-system runtime identity.

Inspect cache behavior with:

```sh
bazel test //:tests //:lint --build_event_json_file=/tmp/luxel-events.json
bazel build //:build --profile=/tmp/luxel-build.profile.json.gz
```

Repeat a command to confirm unchanged work is cached. Use
`--nocache_test_results` only when deliberately rerunning an unchanged test.
Do not routinely clear caches. No remote-cache service or credentials are
required; optional private settings belong in `.bazelrc.local`.

## Signed macOS builds

```sh
apps/macos/Scripts/build-luxel-app.sh
open "apps/macos/dist/Luxel Dev.app"
```

The script signs Bazel's assembled app with Apple Development credentials and
keeps the `com.rawcontext.luxel.dev` identity and `luxel-dev` URL scheme. Do not
launch the unsigned Bazel app or replace `/Applications/Luxel.app`.

The App Store packaging script selects `--//apps/macos:app_store=true`, signs
with the distribution profile, and produces the upload package outside Bazel's
cache. Owner merges into `master` run checks and upload to TestFlight; App Review
submission remains separately controlled. Pull requests do not run unit tests.

## Dependencies

- JavaScript dependencies: `package.json`, `apps/web/package.json`, and
  `pnpm-lock.yaml`; update with pinned pnpm 12.4.1.
- Rust dependencies: `apps/cli/Cargo.toml` and `Cargo.lock`, imported by crate
  universe. License validation reads the same resolved Bazel graph.
- Swift dependencies: `apps/macos/Package.swift` and `Package.resolved` are
  dependency-resolution manifests only. `swift package --package-path apps/macos
  resolve` updates them; application and test targets live in BUILD files.

Run `bazel mod tidy` after module changes and commit `MODULE.bazel.lock`.
Format BUILD and Starlark files with the pinned Buildifier target. Native codec
and model regeneration scripts remain maintenance tools for the checked-in
vendor artifacts; normal builds validate those artifacts without rebuilding
third-party codecs or downloading model weights.
