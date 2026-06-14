# Third-Party Licenses

Luxel currently ships no third-party codec libraries.

Before any vendored codec library is distributed, this file must include the exact upstream license text and copyright notice from the vendored source tree. Distributed code must pass Luxel's Mac App Store license allowlist in `CodecLicensePolicy`; development-only validators and analyzers are tracked separately and are not part of the shipped app bundle.

When a codec library is bundled, add one entry per shipped dependency using a `## Dependency: <dependency-id>` heading, followed by `Name`, `License`, `Copyright`, and `License Text` fields. The release gate parses this file and validates it against the bundled codec dependency manifest.
