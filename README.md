# Luxel

Luxel is a native macOS menu bar screen recorder inspired by Luxel and rebuilt in Swift. The app records displays, windows, selected regions, audio, and automation-driven workflows, then exports through Apple-native media pipelines plus in-process native WebM and AV1 adapters.

<p align="right">
  <a href="https://apps.apple.com/us/app/luxel/id6800438206?mt=12" style="text-decoration: none;">
    <img src="apps/web/public/app-store/mac-app-store-badge.svg" alt="Download on the Mac App Store" width="156" />
  </a>
</p>

This repository is a monorepo for the macOS app, marketing/docs website, release scripts, and product planning docs. The standalone Rust CLI lives in [rawcontext/luxel-cli](https://github.com/rawcontext/luxel-cli).

## Start Here

1. Read this file.
2. Read [AGENTS.md](AGENTS.md) before making changes.
3. Install the pinned workspace tools:

   ```sh
   bun install --frozen-lockfile
   ```

4. For macOS app work, build and launch the signed app bundle, not the SwiftPM debug executable:

   ```sh
   bun run app:build
   open "apps/macos/dist/Luxel Dev.app"
   ```

5. For verification, start with the focused task you touched, then broaden when the change crosses module boundaries:

   ```sh
   bun run test
   bun run lint
   ```

## Repository Map

```text
.
├── AGENTS.md                         Project rules for humans and AI agents
├── README.md                         This onboarding document
├── package.json                      Bun workspace and Turborepo entrypoint
├── turbo.json                        Task graph and cache settings
├── bun.lock                          Locked JavaScript tooling dependencies
├── apps/
│   ├── macos/                        SwiftPM macOS app, tests, and signing scripts
│   └── web/                          Astro website and user docs
├── docs/                             Architecture decisions, plans, release docs
└── packages/                         Reserved workspace package directory
```

Important macOS paths:

```text
apps/macos/Package.swift              Swift package manifest
apps/macos/Sources/LuxelApp           SwiftUI/AppKit app shell and menu bar UI
apps/macos/Sources/LuxelCore          Domain, application use cases, ports, adapters
apps/macos/Sources/LuxelPresentation  Editor presentation models and views
apps/macos/Sources/LuxelCodecWebM     Native VP9/WebM adapter
apps/macos/Sources/LuxelCodecAV1      Native SVT-AV1/MP4 adapter
apps/macos/Tests                      Swift test targets and fixtures
apps/macos/Configuration/Luxel        Info.plist, entitlements, app assets
apps/macos/Scripts                    Local build, signing, packaging, validation scripts
apps/macos/fastlane                   Fastlane lanes used by TestFlight CI
```

Important docs:

```text
docs/Luxel-swift-reimplementation-plan.md     Product and architecture intent
docs/luxel-v1-codec-decision.md             Current v1 export format decision
docs/native-codec-export-decision.md        Native codec constraints and follow-up criteria
docs/future/README.md                       Indexed backlog for post-v1 feature specs
docs/testflight-ci.md                       TestFlight CI secret and workflow notes
```

## Toolchain

The root workspace uses Bun and Turborepo. `.tool-versions` currently pins:

```text
bun 1.4.0
ruby 4.0.6
github-cli 2.98.0
nodejs 24.19.0
python 3.13.15
pre-commit 4.6.2
swiftlint 0.65.1
pipx 1.16.7
uv 0.12.5
```

The macOS app is a Swift package with:

```text
swift-tools-version: 6.2
platform: macOS 26
```

Install or select Xcode 26.6, which supplies Swift tools version 6.2 and the
macOS 26 SDK, before building the app. Fastlane release work also needs the
pinned Ruby and Bundler in `apps/macos`. Model conversion uses the pinned
Python and uv toolchain; hooks and normal lint runs use the pinned pre-commit
and SwiftLint executables rather than ambient installations.

Useful external docs:

- [Bun workspaces](https://bun.sh/docs/pm/workspaces)
- [Turborepo running tasks](https://turbo.build/repo/docs/crafting-your-repository/running-tasks)
- [Astro CLI reference](https://docs.astro.build/en/reference/cli-reference/)
- [Swift Package Manager](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/)
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)

## Workspace Commands

Run commands from the repository root unless a section says otherwise.

| Command | What it does |
| --- | --- |
| `bun install --frozen-lockfile` | Install all Bun workspace dependencies from `bun.lock`. |
| `bun run build` | Run `turbo run build` across workspace packages. |
| `bun run test` | Run `turbo run test`; currently includes Swift tests for the macOS package. |
| `bun run lint` | Run `turbo run lint`; currently SwiftLint for the macOS package. |
| `bun run --cwd apps/macos bench:media` | Run the headless release media-export benchmark and fixed performance gates. |
| `bun run app:build` | Build a signed local dev `.app` bundle. |
| `bun run app:build:mas` | Build a Mac App Store package path through the MAS script. |
| `bun run check:codec-licenses` | Validate third-party codec license ledger expectations. |
| `bun run check:distribution` | Validate distribution build separation expectations. |

Turborepo runs matching scripts inside workspace packages. The macOS `app:build`, MAS build, and distribution checks are intentionally uncached in `turbo.json` because they inspect local signing state and generated bundles.

## macOS App Workflow

The app target is `Luxel`, but day-to-day app testing should use the signed `.app` bundle:

```sh
bun run app:build
open "apps/macos/dist/Luxel Dev.app"
```

Local development builds must use the script defaults: `com.rawcontext.luxel.dev`,
`Luxel Dev`, `luxel-dev`, and `apps/macos/dist/Luxel Dev.app`. Do not override
`APP_BUNDLE_IDENTIFIER`, `APP_DISPLAY_NAME`, `APP_URL_SCHEME`, or `APP_PATH` to
production values, do not use the Mac App Store packaging script for local runs, and
do not replace or launch `/Applications/Luxel.app`. That path is reserved for the
TestFlight or App Store build with bundle identifier `com.rawcontext.luxel`.
The local build also rewrites every copied `InfoPlist.strings` name to `Luxel Dev`,
so macOS menus, notifications, accessibility surfaces, and permission rows remain
visibly distinct from production in every supported locale. Its TCC permissions are
stored separately under `com.rawcontext.luxel.dev`.

Do not launch this binary directly:

```text
apps/macos/.build/arm64-apple-macosx/debug/Luxel
```

Direct SwiftPM executable launches can change the code identity macOS sees for Screen Recording, Microphone, Camera, and related TCC permissions. That causes repeated permission prompts and invalid debugging results.

`apps/macos/Scripts/build-luxel-app.sh`:

- Builds `Luxel`.
- Creates `apps/macos/dist/Luxel Dev.app` by default.
- Copies `Info.plist`, the app icon, and third-party licenses.
- Signs the bundle with the `Apple Development:` identity for team `U65DCW9TAK` unless `SIGN_IDENTITY` or `APPLE_TEAM_IDENTIFIER` is set.
- Rejects ad-hoc signing.
- Emits the final app path on success.

If signing fails, fix signing. Do not fall back to an unsigned app.

Supported local-development overrides:

```sh
SIGN_IDENTITY="Apple Development: Your Name (CERTIFICATE_ID)" bun run app:build
APPLE_TEAM_IDENTIFIER="TEAMID" bun run app:build
CONFIGURATION=debug bun run app:build
```

## Swift Package Layout

The Swift package exports these products:

| Product | Type | Purpose |
| --- | --- | --- |
| `LuxelCore` | Library | Domain models, application services, ports, and infrastructure adapters. |
| `LuxelCodecWebM` | Library | VP9/WebM export through vendored libvpx/libopus artifacts and Swift muxing. |
| `LuxelCodecAV1` | Library | AV1 MP4 export through vendored SVT-AV1 artifacts and AVAssetWriter muxing. |
| `Luxel` | Executable | Menu bar app, editor window, settings, panels, shortcuts, app composition. |

Test targets:

| Target | Purpose |
| --- | --- |
| `LuxelCoreTests` | Domain, use case, infrastructure, export, recording, automation, and settings coverage. |
| `LuxelCodecWebMTests` | WebM codec stack and muxing coverage using media fixtures. |
| `LuxelCodecAV1Tests` | SVT-AV1 encode, MP4 muxing, AAC audio, and ffprobe-gated validation. |
| `LuxelAppTests` | Presentation/editor model behavior that depends on app-facing models. |

## Architecture

Luxel follows a pragmatic Clean Architecture / DDD split. Keep the dependency direction clear:

```text
Infrastructure -> Application -> Domain
Presentation   -> Application -> Domain
LuxelApp       -> LuxelCore + LuxelPresentation + adapters
```

Use these boundaries when adding or changing behavior:

- `LuxelCore/Domain`: Pure value objects, entities, policy, and algorithms. Avoid AppKit, SwiftUI, AVFoundation, ScreenCaptureKit, file system calls, clocks, and network concerns here.
- `LuxelCore/Application/Ports`: Protocols for external capabilities such as capture, export, persistence, permissions, file actions, telemetry, and devices.
- `LuxelCore/Application/UseCases`: Orchestration services that apply domain rules through ports.
- `LuxelCore/Infrastructure`: Apple framework and file-system adapters implementing ports.
- `LuxelPresentation`: UI-facing editor models, commands, views, and reusable presentation support.
- `LuxelApp`: App composition, SwiftUI/AppKit shell, menu bar, panels, settings, shortcuts, and concrete dependency wiring.
- `LuxelCodecWebM`: Isolated native codec integration for WebM VP9.
- `LuxelCodecAV1`: Isolated native codec integration for MP4 AV1.

When a feature crosses these layers, test the lower layers first. Keep UI state out of domain models and keep framework objects behind ports.

## Product Constraints

These constraints are part of the product shape, not incidental implementation details:

- Native macOS first: Swift, SwiftUI, AppKit where needed, ScreenCaptureKit, AVFoundation, ImageIO, VideoToolbox, ServiceManagement, and related Apple frameworks.
- Menu-bar-first app with optional editor and settings windows.
- macOS 26 minimum in `Info.plist` and `Package.swift`.
- App runtime must not depend on Electron, JavaScript plugin compatibility, npm packages, or `ffmpeg` shell-outs.
- WebM VP9 ships through the native `LuxelCodecWebM` adapter.
- MP4 AV1 ships through the native `LuxelCodecAV1` adapter using bundled SVT-AV1.
- Mac App Store distribution is a goal, so new dependencies and entitlements need license and sandbox review.
- Vendored codec code must remain license-compatible with the project and distribution channels.

## Capture And Export

Capture-related domain and use-case code lives under:

```text
apps/macos/Sources/LuxelCore/Domain/CaptureSelection
apps/macos/Sources/LuxelCore/Domain/Recording
apps/macos/Sources/LuxelCore/Application/UseCases/Capture
apps/macos/Sources/LuxelCore/Application/UseCases/Recording
apps/macos/Sources/LuxelCore/Infrastructure/Capture
```

The main capture adapter is `ScreenCaptureKitRecorder`. Capture targets come from `ScreenCaptureKitCaptureTargetCatalog`, with caching and menu filtering handled in application services.

Export-related code lives under:

```text
apps/macos/Sources/LuxelCore/Domain/Export
apps/macos/Sources/LuxelCore/Application/UseCases/Export
apps/macos/Sources/LuxelCore/Infrastructure/Media
apps/macos/Sources/LuxelCodecWebM
apps/macos/Sources/LuxelCodecAV1
```

Current export format groups:

- Apple-native video/animation: `mp4`, `hevc`, `prores422`, `prores4444`, `gif`, `apng`
- External native codec formats: `webm`, `av1`
- Audio-only formats: `m4a`, `alac`, `wav`, `caf`, `flac`

The UI and availability logic should reflect registered codec adapters, not just enum cases.

## CLI And Automation

The standalone Rust CLI is maintained in [rawcontext/luxel-cli](https://github.com/rawcontext/luxel-cli), and its executable is named `luxel`. It pairs with the app, sends an authenticated request over the `luxel://cli` bootstrap route, and waits on a short-lived loopback callback. The sandboxed app performs every recording, conversion, export, and transcription operation.

Install or build the CLI from its repository, then pair it explicitly:

```sh
luxel pair
luxel doctor
```

Luxel Settings > Command Line manages paired clients and the folders available to CLI requests. The complete public command and option reference is maintained on the website at [luxel.media/docs#cli](https://luxel.media/docs#cli). The original URL automation routes remain available for Shortcuts and launchers, but they are separate from the paired CLI trust channel.

The app also parses `luxel://` URLs:

```text
luxel://record?target=display&display=main&fps=display&countdown=3
luxel://record?target=activeWindow&preset=Default
luxel://toggle
luxel://stop
luxel://latest?reveal=true
luxel://preferences
```

Callbacks use `x-success` and `x-error` query parameters. Successful file results append `filePath`; recording starts append `recordingID`; failures append `errorMessage`.

## Web App

The website lives in `apps/web` and uses Astro.

```sh
cd apps/web
bun run dev
bun run build
bun run preview
```

Astro's default dev server port is `4321` unless overridden. The current site has a landing page at `src/pages/index.astro`, user docs at `src/pages/docs.astro`, and shared CSS in `src/styles/global.css`.

## Testing

Run all configured tests through Turbo:

```sh
bun run test
```

Run Swift tests directly when you need SwiftPM flags or narrower iteration:

```sh
cd apps/macos
swift test
swift test --filter LuxelCoreTests/AutomationServiceTests
```

## Linting And Hooks

Run linting:

```sh
bun run lint
```

The SwiftLint config is intentionally minimal and excludes `.build` directories.

The pre-commit config runs SwiftLint through:

```text
apps/macos/Scripts/swiftlint-precommit.sh
```

## Release And Distribution

Releases run through GitHub Actions, not local Fastlane commands. The workflow is defined in `.github/workflows/testflight.yml`.

The TestFlight workflow runs on `macos-26` and starts from either:

- A pushed tag matching `v*`.
- A manual `workflow_dispatch` run with optional `marketing_version`, `build_number`, and TestFlight changelog inputs.

CI checks out the repository, reads the Ruby version from `.tool-versions`, installs Bundler dependencies for `apps/macos`, verifies Xcode, then runs the Fastlane TestFlight lane inside CI. Release signing and App Store Connect credentials come from GitHub repository secrets described in [docs/testflight-ci.md](docs/testflight-ci.md).
