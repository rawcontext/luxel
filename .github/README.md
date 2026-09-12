# GitHub Actions

All jobs use GitHub-hosted Apple Silicon runners (`macos-26`). No self-hosted runner is registered for this repository. Xcode 26.6 and the Ruby version in `.tool-versions` are selected explicitly; Ruby and Bundler are installed with a commit-pinned `ruby/setup-ruby` action.

Every job checks the repository identity, the original actor's immutable account ID, the user initiating a rerun, the event, and the ref. GitHub evaluates these job conditions before allocating a runner. Only `ccheney` can run these workflows:

- Manual runs use `master`.
- TestFlight also accepts owner-created `v*` tags and manual runs on those tags.
- App Store Feedback retains its owner-associated daily schedule on `master`.

The workflows do not subscribe to pull requests, pull-request target events, issue comments, or fork events. Checkout uses the trusted event ref, never a pull-request head supplied as an input.

## Before making the repository public

Private-repository fork workflows are disabled, with no write tokens or secrets passed to forks. GitHub does not expose the public fork-approval policy while a repository is private. After changing visibility, require approval for **all external contributors** before approving any workflow runs:

```sh
gh api --method PUT repos/ccheney/luxel/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
gh api repos/ccheney/luxel/actions/permissions/fork-pr-contributor-approval
```

Do not approve external-contributor workflows. A pull request can change or add workflow files, so the checks in the current workflows do not replace GitHub's fork-approval policy. Fork owners control Actions in their own repositories; those runs cannot access a runner or credentials registered to this repository.

See [GitHub's fork workflow approval guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#controlling-changes-from-forks-to-workflows-in-public-repositories).

## Validation

```sh
ruby .github/scripts/workflow_trust_test.rb
actionlint
gh workflow run validate-automation.yml --ref master
```

The manual validation workflow checks the hosted runner, Ruby/Fastlane setup, workflow trust policy, App Store sync tests, and macOS package tests. It does not require release credentials.
