---
name: hermetic-build-deps
description: Use when changing RPMs, lockfiles, prefetch artifacts, or multi-arch inputs for the konflux-clamav hermetic image build. Covers rpms.in.yaml, rpm-lockfile-prototype, Hermeto prefetch, fetch-db-and-tools.sh, and Dockerfile COPY paths.
---

# Hermetic Build Dependencies

## Overview

`build-images` runs with `HERMETIC: "true"` — no network during the image build. Everything the Dockerfile needs must already be in the source artifact chain or in Hermeto output from `prefetch-dependencies`.

Two independent prefetch paths feed the build:

1. **`fetch-db-data`** — `fetch-db-and-tools.sh` (network allowed)
2. **RPM prefetch (Hermeto)** — packages listed in `rpms.in.yaml`, resolved in `rpms.lock.yaml`, fetched by `prefetch-dependencies`
3. **Generic prefetch** — artifacts.lock.yaml has artifacts: []; generic prefetch is still enabled in prefetch-input, but virus DB, GPG key, and oc tarballs come from fetch-db-data, not this file.

## When to Use

- Adding or updating packages in the image
- `prefetch-dependencies` checksum or resolution errors
- Missing or wrong-arch `oc` in the built image
- Missing `clamav-db/` in the image
- Deciding what belongs in lockfiles vs the fetch script

## Files

| File | Role |
|------|------|
| `rpms.in.yaml` | Package list, `ubi.repo` / `epel.repo`, arches `x86_64` and `aarch64` |
| `rpms.lock.yaml` | Generated from `rpms.in.yaml` (`lockfileVendor: redhat`); refresh via MintMaker or `rpm-lockfile-prototype` |
| `artifacts.lock.yaml` | Generic Hermeto artifacts (`artifacts: []` no pinned entries) |
| `ubi.repo`, `epel.repo` | Repo definitions referenced by `contentOrigin.repofiles` |
| `fetch-db-and-tools.sh` | Builds `clamav-db/`, GPG key, oc tarballs (not committed) |

Pipeline parameter:

```yaml
prefetch-input: '[{"type": "rpm", "path": "."}, {"type": "generic", "path": "."}]'
```

## Data flow

```
fetch-db-data
  clamav-db/                              (freshclam)
  RPM-GPG-KEY-EPEL-9
  openshift-client-linux-<arch>.tar.gz    (four arches)

prefetch-dependencies (Hermeto)
  rpm     ← rpms.in.yaml + rpms.lock.yaml
  generic ← artifacts.lock.yaml

build-images (hermetic Dockerfile)
  COPY clamav-db, GPG key, oc tarball for TARGETARCH
  microdnf install clamav, clamd, jq, skopeo, tar, …  (from prefetched RPM set)
  COPY --from=konflux-test utils.sh, ec, policy tree
```

## Dockerfile expectations

| Input | Origin |
|-------|--------|
| `clamav-db/` → `/var/lib/clamav/` | `fetch-db-and-tools.sh` |
| `RPM-GPG-KEY-EPEL-9` | `fetch-db-and-tools.sh` |
| `openshift-client-linux-${TARGETARCH}.tar.gz` | `fetch-db-and-tools.sh` |
| `whitelist.ign2` | Git |
| `start-clamd.sh`, `test/selftest.sh` | Git |
| ClamAV RPMs in `RUN microdnf install` | Must match `rpms.in.yaml` |

If you add a package to `rpms.in.yaml`, refresh `rpms.lock.yaml` and add it to the Dockerfile install list when it is part of the runtime image.

## OpenShift client (multi-arch)

`fetch-db-and-tools.sh` downloads one tarball per Docker architecture name:

```bash
declare -A OC_ARCH_MAP=(
    [amd64]="x86_64"
    [arm64]="aarch64"
    [ppc64le]="ppc64le"
    [s390x]="s390x"
)
```

The build matrix today is amd64 and arm64 only, but all four tarballs must exist so `COPY openshift-client-linux-${TARGETARCH}.tar.gz` never points at a missing file.

The fetch task typically runs on an x86_64 runner. arm64 images still require the arm64 tarball in the shared source artifact.

## Virus database

- Not stored in git; created under `clamav-db/` during `fetch-db-data`
- Typical files: `main.cvd`, `daily.cvd`, `bytecode.cvd`
- Installed in the image at `/var/lib/clamav/`
- False-positive signatures: `whitelist.ign2` in git

## RPM lock files (rpms.in.yaml → rpms.lock.yaml)

You maintain `rpms.in.yaml`; **do not** hand-edit `rpms.lock.yaml`. Regenerate the lock with **`rpm-lockfile-prototype`** (Konflux/Hermeto standard). The pipeline’s `prefetch-dependencies` task then uses Hermeto to download the pinned RPMs for offline install.

**This repository:**

- `packages:` lists top-level RPMs only (transitives are resolved by the tool)
- `contentOrigin.repofiles`: `./ubi.repo`, `./epel.repo`
- `arches:` `x86_64`, `aarch64` — required for the multi-arch build matrix
- Lock output: `lockfileVersion: 1`, `lockfileVendor: redhat`

**Regenerate locally** (use the same UBI image as the final `FROM` line in `Dockerfile`):

```bash
rpm-lockfile-prototype --image registry.access.redhat.com/ubi9/ubi-minimal:<tag> rpms.in.yaml
```

Commit the updated `rpms.lock.yaml`. In practice, MintMaker often opens `chore(deps): refresh rpm lockfiles` PRs after `rpms.in.yaml` changes — merging those is fine.

Docs: [Konflux — prefetching RPM dependencies](https://konflux.pages.redhat.com/docs/users/building/prefetching-dependencies.html#enabling-prefetch-builds-for-rpm)

## Adding an RPM

1. Add the package name to `packages:` in `rpms.in.yaml` (not every transitive dep)
2. Regenerate `rpms.lock.yaml` with `rpm-lockfile-prototype` (see above) or merge a MintMaker lockfile PR
3. Add the package to the Dockerfile `microdnf install` line if it belongs in the final image
4. Open a PR and run the Konflux pipeline — local `docker build` alone does not run `fetch-db-data` or Hermeto prefetch

## Important notes

- **Do not use `cachi2 fetch-deps` to refresh `rpms.lock.yaml`** — that is not the Konflux workflow for RPM locks; use `rpm-lockfile-prototype`.
- **Two ClamAV installs:** the fetch script installs `clamav` and `clamav-update` temporarily to run `freshclam`; the image installs the production set via hermetic RPM prefetch. Version skew between them can cause confusing failures.
- **Multi-arch:** both `x86_64` and `aarch64` must appear in `rpms.in.yaml` `arches` or the prefetch/build matrix fails.
- **Empty `artifacts.lock.yaml`:** generic prefetch is enabled but most non-RPM inputs come from the fetch script, not the lock file.
- **EPEL during fetch only:** `rpm -ivh epel-release` in `fetch-db-and-tools.sh` uses the network in `fetch-db-data`; the image imports `RPM-GPG-KEY-EPEL-9` from the build context.
- **Lock file edits:** prefer MintMaker or `rpm-lockfile-prototype` over hand-editing `rpms.lock.yaml`.

## Common failures

| Problem | Fix |
|---------|-----|
| Checksum mismatch in prefetch | Regenerate `rpms.lock.yaml` with `rpm-lockfile-prototype` |
| Package not found | Fix name or repos in `rpms.in.yaml` / `ubi.repo` / `epel.repo` |
| No virus DB in image | Fix `fetch-db-data` / `COPY clamav-db` |
| Broken `oc` on arm64 | Ensure `openshift-client-linux-arm64.tar.gz` is in the source artifact |
| Network error during hermetic build | Missing prefetch input — nothing may be downloaded at build time |
