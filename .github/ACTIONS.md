# GitHub Actions

All jobs use GitHub-hosted Apple Silicon runners (`macos-26`). No self-hosted runner is registered for this repository. Xcode 26.6 and the Ruby version in `.tool-versions` are selected explicitly; Ruby and Bundler are installed with a commit-pinned `ruby/setup-ruby` action.

Every job checks the repository identity, the original actor's immutable account ID, the user initiating a rerun, the event, and the ref. GitHub evaluates these job conditions before allocating a runner. Only `ccheney` can run these workflows:

- Manual runs use `master`.
- TestFlight uploads automatically after `ccheney` merges a pull request into `master`. It checks the merger, original actor, rerun actor, target repository, target branch, and merged state before allocating a runner. Tag pushes and manual dispatches cannot trigger TestFlight uploads.
- App Store Feedback retains its owner-associated daily schedule on `master`.
- CLI packaging accepts manual runs from `master`; owner-created `cli-v<version>` tags publish CLI releases. The version must match `apps/cli/Cargo.toml`.

TestFlight uses `pull_request_target` only for the `closed` event so signing credentials are available after an owner-approved merge from a fork. Its job requires `merged == true` and checks out only GitHub's `merge_commit_sha`, never the contributor's head branch or head SHA. Opening, updating, or closing an unmerged pull request cannot start the publishing job. The marketing version comes from the merged `Info.plist`, and build numbers use UTC timestamps.

App Store review submission remains a separate manual workflow restricted to `ccheney` on `master`. No workflow subscribes to pull-request opening/update events, issue comments, or fork events.

Unit tests run only after an owner merge into `master`. The TestFlight workflow
tests the exact merge commit (Swift, CLI, website, and automation scripts), then
uploads only if that test job succeeds. Manual validation, scheduled feedback
sync, and CLI packaging do not run unit tests.

## Branch access

The repository is currently private in the `rawcontext` organization on GitHub Free. Branch rulesets are not enforced in that configuration. Once the repository is public, restore these rulesets for `master` and the default branch:

- [Owner-only master updates](rulesets/master-owner-updates.json) permits updates and PR merges only by `ccheney` (user ID `302437`). Normal owner pushes remain allowed.
- [Protect master history](rulesets/master-history.json) blocks deletion and force pushes for everyone, including the owner.

The definitions are checked in under `.github/rulesets/`. `CODEOWNERS` routes reviews to `ccheney`, and repository auto-merge is disabled. Contributors can open pull requests from forks once the repository is public; opening a pull request does not grant write or merge access.

Keep outside contributors as fork-based contributors. Accepting their pull requests does not require granting collaborator write access.

## Before making the repository public

Private-repository fork workflows are disabled, with no write tokens or secrets passed to forks. GitHub does not expose the public fork-approval policy while a repository is private. Keep Actions disabled during the visibility change, then require approval for **all external contributors** before re-enabling Actions.

Before changing visibility:

```sh
gh api --method PUT repos/rawcontext/luxel/actions/permissions -F enabled=false
```

After the repository is public, restore or create the two rulesets from `.github/rulesets/` and verify that they are active. Then configure the fork-approval policy before re-enabling Actions:

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
