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

After the merge tests pass, create and push an annotated version tag on that merge
commit. A tag created before its merge tests finish fails verification; rerun the
tag workflow after the tests pass. An existing release tag must not be moved to a
newer commit. Tags pointing to older commits use the workflow stored at those
commits, so restored historical tags do not retroactively use the new trigger.

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
