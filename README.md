<h1>
  Luxel
  <a href="https://apps.apple.com/us/app/luxel/id6800438206?mt=12">
    <img align="right" src="apps/web/public/app-store/mac-app-store-badge.svg" alt="Download on the Mac App Store" width="156" />
  </a>
</h1>

A native macOS menu bar recorder with screen and audio capture, replay buffer, local transcription, and video export.

[User docs](https://luxel.media/docs) · [Support](https://luxel.media/support) · [Standalone CLI](https://github.com/rawcontext/luxel-cli)

## Run locally

Requires an Apple silicon Mac running macOS 26+, Xcode with Swift 6.2 or newer, [Bun](https://bun.sh/docs/installation), and an Apple Development signing certificate installed through Xcode.

```sh
git clone https://github.com/rawcontext/luxel.git
cd luxel
bun install --frozen-lockfile
```

Replace `YOUR_TEAM_ID` with your Apple Developer team ID, then build and open the app:

```sh
APPLE_TEAM_IDENTIFIER=YOUR_TEAM_ID bun run --cwd apps/macos app:build
open "apps/macos/dist/Luxel Dev.app"
```

The development app is named **Luxel Dev** and runs from the menu bar. Grant Screen Recording, Microphone, and Camera access when prompted for the features you use.

Use the signed `Luxel Dev.app` bundle for local runs. Launching the raw Swift executable can cause repeated macOS permission prompts.

## Check changes

With Node.js and SwiftLint installed, run from the repository root:

```sh
bun run test
bun run lint
```

For a focused Swift test run:

```sh
cd apps/macos
swift test --filter LocalizationTests
```

## Website

With Node.js installed, run the website locally from the repository root:

```sh
bun run --cwd apps/web dev
```

See [AGENTS.md](AGENTS.md) for contribution guidance.
