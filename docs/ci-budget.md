# Fork CI policy

This repository is a **public** fork of LizardByte/Sunshine. Public repositories get
unlimited GitHub Actions minutes on standard runners, so CI is scoped for fast,
relevant feedback rather than to ration billed minutes.

## Pull requests

Every pull request runs **PR Checks**:

- `web-and-format`: one Ubuntu 24.04 job, ten-minute timeout, read-only repository
  permissions, cached Node dependencies, web production build, whitespace checks and
  clang-format 18 checks on changed C/C++ files.
- `build-windows`: the full native Windows build and unit tests, reusing the upstream
  `ci-windows.yml` definition (AMD64 and ARM64). This compiles and tests the fork's
  only native change, the Windows libvirtualhid-dev gamepad backend, before merge.
  Code signing is skipped (`publish_release` is false and no Azure inputs are passed).

Superseded PR runs are cancelled. Workflows use `pull_request`, never the privileged
`pull_request_target`.

## Releases and the full matrix

The multi-platform **CI** workflow runs on version tags (`v*`) and via
Actions -> CI -> Run workflow. It is intentionally not launched by routine dependency
PRs; the native Windows leg above already covers the fork's compiled surface on PRs.

Homebrew formula validation, Copr publishing and Pages deployment stay upstream-only:
they depend on upstream credentials or upstream infrastructure and are guarded by
`github.repository_owner == 'LizardByte'`. Artifact/screenshot comment jobs require
upstream ownership AND successful source CI, so a failed build cannot fan out into a
publisher.

## Code scanning

CodeQL is enabled on this fork via the `ENABLE_CODEQL` repository variable
(`vars.ENABLE_CODEQL == 'true'` in `_codeql.yml`). Public repositories get CodeQL at
no cost. To disable it again, delete the variable (`gh variable delete ENABLE_CODEQL`).

## Dependencies and security

Renovate is disabled on this fork (`renovate.json` sets `"enabled": false`) so it does
not recreate upstream's high-volume update PRs. Submodule version updates are grouped
into one weekly Monday Dependabot PR. GitHub vulnerability alerts remain enabled and
are not silenced to save minutes.

## Rollback

Revert the relevant commit on the default branch; no force-push is necessary. The CI
policy lives entirely in `.github/` plus this document.
