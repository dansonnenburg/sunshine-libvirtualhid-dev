# Private-fork CI budget

Routine pull requests run **PR Checks**: one Ubuntu 24.04 job, ten-minute timeout,
read-only repository permissions, cached Node dependencies, web build, whitespace
checks and clang-format 18 checks on changed C/C++ files. This is deliberately NOT
a claim that native builds or native unit tests have passed. Superseded PR runs
are cancelled. Workflows use `pull_request`, never privileged `pull_request_target`.

The original multi-platform **CI** remains available through Actions → CI → Run
workflow and version tags (`v*`). It is no longer launched by every dependency PR.
Native Windows checkout enables Git long-path support before recursive submodules.

Homebrew formula validation, Copr publishing and Pages deployment are upstream-only:
they depend on public source access, upstream credentials or upstream infrastructure.
Private-fork CodeQL is opt-in via `ENABLE_CODEQL=true`, only after code-scanning
entitlement/setup is available. Artifact/screenshot comment jobs require upstream
ownership AND successful source CI, so failed builds cannot fan out into publishers.
The fork's release artifact upload paths inside native build jobs remain available.

Submodule version updates are grouped into one weekly Monday PR. GitHub vulnerability
alerts and the independent Hermes security monitor remain enabled daily. Security
alerts are not silenced to save minutes. Hermes retains existing security PRs instead
of creating a new dated PR daily; failed checks remain blockers, never successes.

## Verification and remaining limitations

Validated locally: workflow actionlint, workflow policy regressions, Node install and
web production build. Hosted execution is currently blocked by account usage/billing;
Windows and the complete native packaging matrix are not execution-verified by this
change. Historical Flatpak/Arch packaging failures still require a targeted manual
run and diagnosis; do not label the full native matrix green based on the web check.

## Rollback

Revert the CI-budget commit on the default branch; no force-push is necessary.
The change is limited to `.github/` plus this document. Closed duplicate security PRs
retain their branches and can be reopened; unique vulnerability PRs are preserved.
