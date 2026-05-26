---
name: ci-pipeline-debugging
description: Use when a Konflux Tekton build fails for konflux-clamav, when tracing task order or OCI artifacts, or when post-build security scans or the clamav-self-test integration pipeline fail.
---

# CI Pipeline Debugging

## Overview

The component `clamav-db-hermetic` is built from two PipelineRuns in `.tekton/`. Both produce a multi-arch image (`linux/x86_64`, `linux/arm64`) with embedded virus definitions and a preconfigured `clamd`.

Only `fetch-db-data` runs with network access. It executes `fetch-db-and-tools.sh` (freshclam, EPEL GPG key, OpenShift client tarballs). Later tasks use Hermeto RPM/generic prefetch (`prefetch-dependencies`) and a hermetic `build-images` step.

## When to Use

- A Tekton task failed and you need its place in the pipeline
- `fetch-db-data`, `prefetch-dependencies`, or `build-images` failed
- A security scan after `build-image-index` failed
- Integration pipeline `konflux-clamav-self-test` failed after a successful build

## Task order

```
init
  └─ clone-repository
       └─ fetch-db-data          (HERMETIC=false)
            └─ prefetch-dependencies
                 └─ build-images          (matrix: x86_64, arm64)
                      └─ build-image-index
                           ├─ clair-scan, clamav-scan (per platform)
                           ├─ sast-snyk-check, sast-shell-check, sast-unicode-check
                           ├─ coverity-availability-check → sast-coverity-check
                           ├─ ecosystem-cert-preflight-checks
                           ├─ deprecated-base-image-check
                           ├─ rpms-signature-scan
                           ├─ apply-tags, push-dockerfile
                           └─ build-source-image (only if param build-source-image=true)
```

**OCI trusted artifacts:** `SOURCE_ARTIFACT` flows clone → fetch-db-data → prefetch → build. `CACHI2_ARTIFACT` flows prefetch → build.

## PR vs push

| | Pull request | Push to `main` |
|---|--------------|----------------|
| File | `.tekton/clamav-hermetic-pull-request.yaml` | `.tekton/clamav-hermetic-push.yaml` |
| Image tag | `clamav-db-hermetic:on-pr-{{revision}}` | `clamav-db-hermetic:{{revision}}` |
| Expires | 5 days | Not set on push |
| Cancel in-progress | yes | no |

Registry: `quay.io/redhat-user-workloads/rhtap-integration-tenant/clamav-db-hermetic`  
Service account: `build-pipeline-clamav-db-hermetic`

## fetch-db-data

Most prefetch failures show up here.

| | |
|---|---|
| Task | `run-script-oci-ta` |
| Script | `/var/workdir/source/fetch-db-and-tools.sh` |
| Runner | `registry.access.redhat.com/ubi9/ubi:latest` |
| `HERMETIC` | `"false"` |
| Adds to source tree | `clamav-db/`, `RPM-GPG-KEY-EPEL-9`, `openshift-client-linux-{amd64,arm64,ppc64le,s390x}.tar.gz` |

The script installs EPEL and `clamav-update` only to run `freshclam`; the final image installs ClamAV again during the hermetic build (see `hermetic-build-deps`).

Virus DB size is on the order of a few hundred MB (`main.cvd`, `daily.cvd`, `bytecode.cvd`). Default task resources are usually enough unless logs show OOM.

## build-image-index

**`build-image-index`** combines per-platform **`build-images`** results into the published multi-arch image. Downstream tasks (scans, tags, chains) use its `IMAGE_URL` and `IMAGE_DIGEST`.

Each **`build-images`** run uses `buildah-remote-oci-ta` (one per platform):

| | |
|---|---|
| Task | `buildah-remote-oci-ta` (one run per platform) |
| `HERMETIC` | `"true"` |
| `ADDITIONAL_BASE_IMAGES` | Must include `$(tasks.fetch-db-data.results.SCRIPT_RUNNER_IMAGE_REFERENCE)` for SBOM/Conforma |

The Dockerfile selects the OpenShift client with `ARG TARGETARCH` and `COPY openshift-client-linux-${TARGETARCH}.tar.gz`. The fetch script must place every tarball the Dockerfile can reference, even though only amd64 and arm64 are built today.

## Security scans

Runs when `skip-checks` is not `"true"`, after `build-image-index`. Standard Konflux catalog tasks: Clair, ClamAV, Snyk SAST, shell/unicode checks, optional Coverity, RPM signature scan, ecosystem preflight, deprecated base image check.

This repository **ships** the ClamAV scanner image; the `clamav-scan` task in the pipeline still scans the **artifact you just built**, like any other component.

## Integration test

`integration-tests/clamav-self-test.yaml` runs `/selftest.sh` in the built image:

- Verifies `clamdscan`, `clamscan`, and `freshclam` are present
- Checks clamscan output format with a tiny local signature file (not a full DB regression)

## Important notes

- **`fetch-db-data` runs on the pipeline runner**, often amd64, but must still download oc tarballs for arm64 (and the other arches listed in `fetch-db-and-tools.sh`). Do not key downloads off `uname -m` alone.
- **Tekton task bundles** in `.tekton/` use pinned `@sha256:` digests. Update them through MintMaker `chore(deps): update konflux references` PRs rather than editing SHAs by hand.
- **Fork and dependency-bot PRs** may need a comment `/ok-to-test` before the full Konflux pipeline runs.
- **PR builds** set `build-source-image` to `false` by default — do not expect a source image on every PR.
- **PR image tags expire in five days** — not suitable for production virus-definition consumption.

## Common failures

| Failure | What to check |
|---------|----------------|
| freshclam error | Task log, ClamAV mirror reachability, retry pipeline |
| curl / oc download | All four `openshift-client-linux-*.tar.gz` files in the source artifact |
| prefetch-dependencies | `rpms.lock.yaml` in sync with `rpms.in.yaml` (regen via `rpm-lockfile-prototype`) |
| build-images / wrong `oc` on arm64 | `OC_ARCH_MAP` in `fetch-db-and-tools.sh` and Dockerfile `TARGETARCH` |
| Conforma / SBOM | `ADDITIONAL_BASE_IMAGES` includes script runner reference |
| clamav-scan on built image | Scan logs; image content or policy, not “wrong repo” |
| rpms-signature-scan | RPM sources and signatures in `rpms.lock.yaml` |
| integration self-test | `/selftest.sh` output; confirm `clamav-db/` was copied into the image |
