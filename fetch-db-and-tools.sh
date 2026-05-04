#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Install EPEL repo
rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

# Install ClamAV ONLY
microdnf install -y clamav clamav-update

# Setup DB Directory
# In the pipeline, the source is mounted at /var/workdir/source
DB_DIR=/var/workdir/source/clamav-db
mkdir -p "$DB_DIR"
chmod 777 "$DB_DIR"

# Run Freshclam
echo "DatabaseDirectory $DB_DIR" > /tmp/freshclam.conf
echo "DatabaseMirror database.clamav.net" >> /tmp/freshclam.conf
freshclam --config-file=/tmp/freshclam.conf

# Download GPG Key
curl -L -o /var/workdir/source/RPM-GPG-KEY-EPEL-9 https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9

# OpenShift client tarball arch for mirror.openshift.com (must match the image platform).
# TARGET_PLATFORM is set by the Tekton pipeline (linux/arm64, linux/x86_64, ...). Do not
# infer from uname here: prefetch often runs on a different arch than the image being built.
oc_arch_from_target_platform() {
  case "$1" in
    linux/arm64 | linux/arm64/v8) echo aarch64 ;;
    linux/amd64 | linux/x86_64) echo amd64 ;;
    linux/ppc64le) echo ppc64le ;;
    linux/s390x) echo s390x ;;
    *)
      echo "ERROR: Unsupported TARGET_PLATFORM for oc download: $1" >&2
      return 1
      ;;
  esac
}

if [[ -z "${TARGET_PLATFORM:-}" ]]; then
  echo "ERROR: TARGET_PLATFORM must be set (e.g. linux/arm64). This script is intended for the Konflux prefetch step." >&2
  exit 1
fi
OC_ARCH=$(oc_arch_from_target_platform "${TARGET_PLATFORM}")

curl -L -o /var/workdir/source/openshift-client-linux.tar.gz \
    "https://mirror.openshift.com/pub/openshift-v4/${OC_ARCH}/clients/ocp/stable/openshift-client-linux.tar.gz"
