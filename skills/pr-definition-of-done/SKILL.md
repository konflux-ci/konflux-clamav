---
name: pr-definition-of-done
description: Use before opening or updating a konflux-clamav pull request, or when GitHub Actions or Konflux pipeline checks fail. Covers commits, formatting, lockfiles, and expected CI outcomes.
---

# PR Definition of Done

## Overview

A pull request to `main` runs GitHub Actions and a Konflux hermetic build for component `clamav-db-hermetic`. Merging triggers the push pipeline, which publishes a durable image tag with refreshed virus definitions.

## When to Use

- Before pushing or marking a PR ready for review
- Mapping a failed check to a required fix
- Reviewing someone else's change

## Pre-push checklist

### Commits

- [ ] `type(JIRA-ID): description` (e.g. `fix(STONEINTG-1288): extend whitelist for foo`)
- [ ] Type is one of: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`
- [ ] `git commit -s` (DCO sign-off)
- [ ] Title and body lines under 72 characters
- [ ] `Assisted-by: <tool>` if an AI tool helped
- [ ] Branch from `main`; merge via PR (do not push directly to `main`)

### Edits in this repository

- [ ] No drive-by whitespace or unrelated file changes
- [ ] No spaces or tabs on empty lines
- [ ] Exactly one newline at EOF (no extra blank lines after the last line)
- [ ] No secrets, keys, or credentials

### Image and build inputs

- [ ] Dockerfile changes stay minimal; touch the `clamd` `sed` block only when scan behavior requires it
- [ ] RPM changes: `rpms.in.yaml`, `rpms.lock.yaml`, and Dockerfile `microdnf` list updated together
- [ ] Prefetch changes: `fetch-db-and-tools.sh` outputs still match Dockerfile `COPY` paths
- [ ] Multi-arch: oc tarball names and `TARGETARCH` stay aligned

### Dependencies and Tekton

- [ ] After editing `rpms.in.yaml`, `rpms.lock.yaml` is regenerated (`rpm-lockfile-prototype` or MintMaker lockfile PR)
- [ ] Tekton bundle digest bumps via MintMaker `chore(deps): update konflux references`, not ad hoc SHA edits

### Pull request text

- [ ] Title under 72 characters, describes the change
- [ ] Description explains why (understandable without private Jira-only context)
- [ ] Testing section states what was run (Konflux pipeline, local attempts, etc.)
- [ ] Related tickets or issues linked when they exist

### Konflux on forks

- [ ] Comment `/ok-to-test` if the Tekton pipeline did not start on a fork or bot PR

## CI that runs on pull requests

### GitHub Actions

| Workflow | Path | Purpose |
|----------|------|---------|
| Agentready | `.github/workflows/agentready.yaml` | Repo readiness per `.agentready/config/.agentready-config.yaml` |

There is no `make test`, unit test workflow, or Dockerfile hadolint job in this repository.

### Konflux Tekton

Defined in `.tekton/clamav-hermetic-pull-request.yaml`:

| Stage | Work |
|-------|------|
| Prefetch | `fetch-db-data` → `prefetch-dependencies` |
| Build | `build-images` (x86_64, arm64) → `build-image-index` |
| Scans | Clair, ClamAV, SAST tasks, RPM signature, preflight, deprecated base |
| Metadata | `apply-tags`, `push-dockerfile` |

PR images are tagged `on-pr-{{revision}}` and expire after five days.

### Integration test

`integration-tests/clamav-self-test.yaml` exercises `/selftest.sh` inside the built image after the component build succeeds in Konflux integration testing.

## Reviewers

See `.github/CODEOWNERS` for automatic review requests.

## Downstream impact

Consumers use this image from the [clamav-scan](https://github.com/konflux-ci/konflux-test-tasks/tree/main/task/clamav-scan) Tekton task. Changes to entrypoint (`/start-clamd.sh`), socket path (`/var/run/clamd.scan/clamd.sock`), or database layout under `/var/lib/clamav/` can break existing pipelines.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| `rpms.in.yaml` without lock refresh | Regenerate with `rpm-lockfile-prototype` or merge MintMaker lockfile PR |
| Only one oc tarball in fetch script | Download every arch in `fetch-db-and-tools.sh` |
| SBOM/Conforma failure | `ADDITIONAL_BASE_IMAGES` includes `SCRIPT_RUNNER_IMAGE_REFERENCE` in `.tekton/` |
| Unsigned commit | `git commit -s` |
| Pipeline never started | `/ok-to-test` |
| Local `docker build` assumed equal to CI | Reproduce `fetch-db-data` + Hermeto prefetch or rely on Konflux PR build |
