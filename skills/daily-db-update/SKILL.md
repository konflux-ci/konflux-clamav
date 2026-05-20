---
name: daily-db-update
description: Use when ClamAV signatures in the published image are stale, when fetch-db-data or freshclam fails on push builds, or when verifying that main-branch builds still run on schedule.
---

# Daily Virus Definition Update

## Overview

This repository builds an image that embeds current ClamAV signature databases for use in Konflux malware scanning. Signatures are not vendored in git: each build runs `freshclam` in `fetch-db-and-tools.sh`, writes `clamav-db/`, and the Dockerfile copies that tree to `/var/lib/clamav/`.

Production freshness depends on **push builds to `main`**, not short-lived PR tags.

## When to Use

- Scans report outdated signatures
- `fetch-db-data` failed on a push pipeline
- Confirming whether scheduled builds still run
- Manually forcing a new image with current definitions

## Scheduled refresh

README and AGENTS.md describe a daily rebuild. There is **no** GitHub Actions workflow in this repo that commits to `main` on a cron. Scheduling is configured in Konflux/App Studio for application `konflux-clamav`, component `clamav-db-hermetic`.

To verify scheduling:

1. Konflux UI — recent `clamav-db-hermetic-on-push` PipelineRuns on `main`
2. Quay — new digests on `quay.io/redhat-user-workloads/rhtap-integration-tenant/clamav-db-hermetic`
3. Git history on `main` — commits that triggered pushes (may include automation outside this repo)

## Push pipeline flow

```
push to main
  └─ .tekton/clamav-hermetic-push.yaml
       ├─ fetch-db-data (network on)
       │    └─ fetch-db-and-tools.sh
       │         ├─ freshclam → clamav-db/
       │         ├─ RPM-GPG-KEY-EPEL-9
       │         └─ openshift-client-linux-*.tar.gz
       ├─ prefetch-dependencies
       ├─ build-images (x86_64, arm64)
       ├─ build-image-index
       ├─ security scans
       └─ apply-tags, push-dockerfile
            └─ image tag: clamav-db-hermetic:{{revision}}
```

Integration test `clamav-self-test.yaml` runs afterward; it checks binaries and clamscan output shape, not that signatures match a particular date.

## fetch-db-data

| | |
|---|---|
| Task | `run-script-oci-ta` |
| Script | `fetch-db-and-tools.sh` |
| Runner | `ubi9/ubi:latest` |
| Network | Required (`HERMETIC=false`) |
| Mirror | `database.clamav.net` (written into `/tmp/freshclam.conf` at runtime) |

Approximate download sizes: `main.cvd` ~170 MB, `daily.cvd` ~65 MB, `bytecode.cvd` under 1 MB.

## Push vs pull request images

| | Push (`main`) | Pull request |
|---|---------------|--------------|
| Tag | `{{revision}}` | `on-pr-{{revision}}` |
| Expiry | None in pipeline | 5 days |
| Use for fresh DB | Yes | No — PR tags are for validation only |

## Manual rebuild

1. Start a component build for `clamav-db-hermetic` on `main` in Konflux/App Studio, or
2. Push to `main` (subject to branch protection), then
3. Confirm a successful push PipelineRun and a new tag on Quay.

Tenants reference this image by digest or tag in their own Konflux configuration. Publishing a new image here does not update every consumer until they point at the new digest.

## After a successful push

1. `fetch-db-data` logs show freshclam completing without error
2. Security scan tasks finished (unless intentionally skipped)
3. Integration `clamav-self-test` passed
4. Optional: run the image and list `/var/lib/clamav/*.cvd` 

## Important notes

- Green PR builds do not refresh production — PR tags expire and are not the delivery path for daily definitions.
- Intermittent freshclam failures are usually mirror or network issues; retry the pipeline.
- New signatures can surface detections that are false positives for your workloads — add entries to `whitelist.ign2` only with maintainer agreement and a tracked justification.
- `selftest.sh` passing does not prove signatures are current; it only proves tooling works.

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Stale signatures in CI | No recent push build | Run push pipeline on `main` |
| freshclam failure | CDN or network | Task logs; retry |
| curl failures in fetch | oc or GPG download | Check `fetch-db-and-tools.sh` and mirror status |
| Downstream still stale | Old image digest pinned | Update consumer component image reference |
| Integration test failed | Broken image build | Inspect `/selftest.sh` in task logs |
| New false positive | DB update | Review `whitelist.ign2` with evidence |
