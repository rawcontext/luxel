<h1>
  Luxel
  <a href="https://apps.apple.com/us/app/luxel/id6800438206?mt=12">
    <img align="right" src="apps/web/public/app-store/mac-app-store-badge.svg" alt="Download on the Mac App Store" width="156" />
  </a>
</h1>

A native macOS menu bar recorder with screen and audio capture, replay buffer, local transcription, and video export.

[User docs](https://luxel.media/docs) · [Support](https://luxel.media/support) · [CLI](apps/cli)

## Run locally

Requires an Apple silicon Mac running macOS 26+, Xcode 26.6, [Bazelisk](https://github.com/bazelbuild/bazelisk), and an Apple Development signing certificate installed through Xcode. Bazel downloads the other pinned build tools and dependencies.

```sh
git clone https://github.com/rawcontext/luxel.git
cd luxel
```

Replace `YOUR_TEAM_ID` with your Apple Developer team ID, then build and open the app:

```sh
APPLE_TEAM_IDENTIFIER=YOUR_TEAM_ID apps/macos/Scripts/build-luxel-app.sh
open "apps/macos/dist/Luxel Dev.app"
```

The development app is named **Luxel Dev** and runs from the menu bar. Grant Screen Recording, Microphone, and Camera access when prompted for the features you use. Always run the signed development bundle.

## Build and check

```sh
bazel build //:build
bazel test //:tests //:lint
```

Bazel builds Swift, Rust, and TypeScript in one dependency graph and caches builds, tests, and lint checks. For focused checks:

```sh
bazel test //apps/macos:localization_tests
bazel test //apps/cli:tests //apps/cli:lint
bazel test //apps/web:tests
```

See [BUILDING.md](BUILDING.md) for targets, toolchains, caching, and release packaging, and [AGENTS.md](AGENTS.md) for contribution guidance.

## Website

```sh
bazel run //apps/web:dev
```

The website's [build and deployment documentation](apps/web/README.md) covers Vercel.

## License

Luxel's original code is licensed under the [MIT License](LICENSE),
copyright © 2026 Raw Context LLC. Third-party code and models retain their
own licenses; the MIT license does not replace those terms. See the
[macOS acknowledgements](apps/macos/THIRD_PARTY_LICENSES.md) and
[CLI acknowledgements](apps/cli/THIRD_PARTY_LICENSES.md), plus the
[website notices](apps/web/THIRD_PARTY_LICENSES.md).
