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

# Download OpenShift Client
curl -L -o /var/workdir/source/openshift-client-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
