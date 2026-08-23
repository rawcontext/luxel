fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac build_testflight_pkg

```sh
[bundle exec] fastlane mac build_testflight_pkg
```

Build a Mac App Store package for Luxel

### mac release_testflight

```sh
[bundle exec] fastlane mac release_testflight
```

Build Luxel and upload the signed macOS package to TestFlight

### mac sync_app_store_metadata

```sh
[bundle exec] fastlane mac sync_app_store_metadata
```

Upload localized metadata to an editable App Store Connect version

### mac sync_app_store_screenshots

```sh
[bundle exec] fastlane mac sync_app_store_screenshots
```

Upload localized screenshots to an editable App Store Connect version

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
