# Third-Party License Maintenance

Before distributing an additional third-party library or model, add its exact
upstream license text, copyright notice, source, and required attribution to
`THIRD_PARTY_LICENSES.md`. The shipped acknowledgments file must contain only
customer-facing legal notices and attribution.

Vendored codecs must also pass `CodecLicensePolicy`. Add one structured entry
per codec using a `## Dependency: <dependency-id>` heading followed by `Name`,
`License`, `Copyright`, and `License Text` fields so the release gate can
validate the ledger against the codec dependency manifest.

When a Swift package is added or updated, inspect its target graph and bundled
source for transitive license notices. Update the acknowledgments inventory and
its regression test in the same change.
