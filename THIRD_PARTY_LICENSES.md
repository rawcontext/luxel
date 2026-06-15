# Third-Party Licenses

Luxel currently ships no third-party codec libraries.

## Swift Argument Parser

Luxel includes Swift Argument Parser in the bundled command-line helper.

License: Apache License 2.0 with Runtime Library Exception

Notice: The upstream package ships `LICENSE.txt` and no separate NOTICE file.

License text: https://github.com/apple/swift-argument-parser/blob/main/LICENSE.txt

## Firebase Apple SDK

Luxel includes Firebase Core and Firebase Crashlytics in the macOS app to report crashes and recorded non-fatal errors.

License: Apache-2.0

Notice: The upstream package ships a `LICENSE` file and no separate NOTICE file.

License text: https://github.com/firebase/firebase-ios-sdk/blob/12.14.0/LICENSE

Before any vendored codec library is distributed, this file must include the exact upstream license text and copyright notice from the vendored source tree. Distributed code must pass Luxel's Mac App Store license allowlist in `CodecLicensePolicy`; development-only validators and analyzers are tracked separately and are not part of the shipped app bundle.

When a codec library is bundled, add one entry per shipped dependency using a `## Dependency: <dependency-id>` heading, followed by `Name`, `License`, `Copyright`, and `License Text` fields. The release gate parses this file and validates it against the bundled codec dependency manifest.
