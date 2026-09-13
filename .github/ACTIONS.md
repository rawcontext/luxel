# GitHub Actions

All jobs use GitHub-hosted Apple Silicon runners (`macos-26`). No self-hosted runner is registered for this repository. Xcode 26.6 and the Ruby version in `.tool-versions` are selected explicitly; Ruby and Bundler are installed with a commit-pinned `ruby/setup-ruby` action.

Every job checks the repository identity, the original actor's immutable account ID, the user initiating a rerun, the event, and the ref. GitHub evaluates these job conditions before allocating a runner. Only `ccheney` can run these workflows:

- Manual runs use `master`.
- Tests run after `ccheney` merges a pull request into `master`. TestFlight uploads only when `ccheney` pushes a `v<major>.<minor>[.<patch>]` tag whose version matches the tagged commit's `Info.plist`.
- App Store Feedback retains its owner-associated daily schedule on `master`.
- CLI packaging accepts manual runs from `master`; owner-created `cli-v<version>` tags publish CLI releases. The version must match `apps/cli/Cargo.toml`.

The TestFlight workflow listens for owner pushes to `master` and `v*` tags. A read-only verification job
checks GitHub's pull-request API for a merged PR whose exact merge commit matches
`github.sha`, whose target is this repository's `master`, and whose merger is
`ccheney`. Branch pushes run unit tests; tag pushes additionally require a successful
`Unit tests after merge` job for that exact SHA before uploading to TestFlight.
Direct pushes, unmerged PRs, and contributor events cannot pass that gate.
Every checkout uses the event's exact SHA. The marketing version comes from the
validated tag; build numbers use UTC timestamps.

App Store review submission remains a separate manual workflow restricted to `ccheney` on `master`. No workflow subscribes to pull-request opening/update events, issue comments, or fork events.

Unit tests run only after an owner merge into `master`. The TestFlight workflow
tests the exact merge commit (Swift, CLI, website, and automation scripts).
Tag pushes, manual validation, scheduled feedback sync, and CLI packaging do not
run unit tests. App Store review submission remains separate from the tag-driven
TestFlight upload.

Bazel builds and tests the Swift app, Rust CLI, TypeScript website, metadata,
and automation checks. Repository archive caches and the content-addressed action
cache persist between jobs and runs. The action cache includes compilation,
unchanged test results, and lint results; changes to declared inputs invalidate
only the affected work. CI saves completed actions even when a later check fails.
Unpacked repository trees and output bases are not uploaded as caches.

Signing, credential preparation, and publication remain outside Bazel's cacheable
build actions. Only unsigned app bundles and declared build/test outputs enter
the action cache. The trusted `push` trigger grants normal cache access; merge
verification must succeed before test or publishing jobs can use these caches.

## macOS release runbook

A release requires both a pushed Git tag and a published GitHub Release. Pushing
the tag triggers TestFlight but does not create an entry on GitHub's Releases page.

1. Merge the release preparation PR into `master` and wait for its merge tests to
   pass. Record that exact merge SHA and verify its `Info.plist` marketing version.
2. Set `RELEASE_VERSION` to that version and `RELEASE_SHA` to the verified merge
   SHA, then create and push the annotated tag:

   ```sh
   : "${RELEASE_VERSION:?Set the release version}"
   : "${RELEASE_SHA:?Set the tested merge SHA}"
   RELEASE_TAG="v${RELEASE_VERSION}"
   git tag -a "$RELEASE_TAG" "$RELEASE_SHA" -m "Luxel ${RELEASE_VERSION}"
   git push origin "refs/tags/${RELEASE_TAG}"
   git ls-remote --tags origin "refs/tags/${RELEASE_TAG}*"
   ```

   Confirm the remote tag's peeled `^{}` SHA equals `RELEASE_SHA`. An existing
   release tag must not be moved to newer code.
3. Wait for the tag's **Build and Upload to TestFlight** job to succeed, and
   confirm its source SHA and uploaded version/build number. If the tag was
   pushed before merge tests finished, rerun the tag workflow after they pass.
4. Write concise release notes from the tagged version's checked-in What's New
   text in `app-store/listing-metadata.md`. Set `RELEASE_NOTES` to that Markdown
   file, then publish the matching GitHub Release:

   ```sh
   : "${RELEASE_NOTES:?Set the release notes file}"
   gh release create "$RELEASE_TAG" --repo rawcontext/luxel --verify-tag \
     --title "Luxel ${RELEASE_VERSION}" --notes-file "$RELEASE_NOTES" --latest
   ```

   `--verify-tag` prevents GitHub from silently creating a tag at the current
   default-branch head. For a historical release older than the current release,
   use `--latest=false` instead. If the GitHub Release already exists, verify it
   rather than creating a duplicate.
5. Read back the published release and confirm it appears on the
   [Releases page](https://github.com/rawcontext/luxel/releases):

   ```sh
   gh release view "$RELEASE_TAG" --repo rawcontext/luxel \
     --json url,tagName,name,isDraft,body
   ```

   The release must have the intended tag, title and notes, with `isDraft: false`.
   Report its release URL when handing off; a tag URL alone is not completion.

Historical tags use the workflow stored at their source commits. When restoring
a missing tag for an already-uploaded build, verify the original successful
upload and its source SHA, then create the GitHub Release without moving the tag
or uploading another binary. App Store review submission remains a separate step.

## Branch access

The repository is public in the `rawcontext` organization. GitHub Free enforces
the following active rulesets for `master` and the default branch:

- [Owner-only master updates](rulesets/master-owner-updates.json) permits updates and PR merges only by `ccheney` (user ID `302437`). Normal owner pushes remain allowed.
- [Protect master history](rulesets/master-history.json) blocks deletion and force pushes for everyone, including the owner.

The definitions are checked in under `.github/rulesets/`. `CODEOWNERS` routes reviews to `ccheney`, and repository auto-merge is disabled. Contributors can open pull requests from forks once the repository is public; opening a pull request does not grant write or merge access.

Keep outside contributors as fork-based contributors. Accepting their pull requests does not require granting collaborator write access.

## Public repository controls

Workflow runs from **all external contributors** require approval. The default
workflow token is read-only, and workflows cannot approve pull requests. No
self-hosted runners are registered. Only `ccheney` currently has repository write
access.

After a repository transfer or visibility change, verify the bypass list as well
as rule enforcement: GitHub removed the owner bypass during this repository's
transfer. Keep Actions disabled while restoring controls:

```sh
gh api --method PUT repos/rawcontext/luxel/actions/permissions -F enabled=false
```

Restore the two definitions from `.github/rulesets/` and verify that they are
active. The updates rule must allow only user `302437` to bypass it; the history
rule must have no bypass actors. Then verify the fork policy before re-enabling
Actions:

```sh
gh api --method PUT repos/rawcontext/luxel/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
gh api repos/rawcontext/luxel/actions/permissions/fork-pr-contributor-approval
gh api --method PUT repos/rawcontext/luxel/actions/permissions -F enabled=true
```

Do not approve external-contributor workflows. A pull request can change or add workflow files, so the checks in the current workflows do not replace GitHub's fork-approval policy. Fork owners control Actions in their own repositories; those runs cannot access a runner or credentials registered to this repository.

See [GitHub's fork workflow approval guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#controlling-changes-from-forks-to-workflows-in-public-repositories).

## Validation

```sh
ruby .github/scripts/workflow_trust_test.rb
actionlint
gh workflow run validate-automation.yml --ref master
```

The manual validation workflow checks the hosted runner, Ruby/Fastlane setup,
and CLI linting. It does not run unit tests or require release credentials.
