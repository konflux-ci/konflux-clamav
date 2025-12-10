FROM quay.io/konflux-ci/konflux-test:v1.4.42@sha256:32112ba0f1b8a3944f4905be40308713c32beb6c059c42ef0bc2b5fe7947ff2f as konflux-test
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7-1764794109

ENV POLICY_PATH="/project"

# -------------------------------------------------------------------------
# HERMETIC INSTALLATION START (Replaces network install)
# -------------------------------------------------------------------------
# 1. Copy the RPMs directory (created by prefetch-dependencies task)
COPY rpm /tmp/rpm

# 2. Copy the GPG Key (defined in artifacts.lock.yaml)
COPY artifacts/RPM-GPG-KEY-EPEL-9 /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9

# 3. Install packages offline
# --disablerepo=* ensures we DO NOT try to reach the internet
# /tmp/rpm/*.rpm tells microdnf to use ONLY the files we just copied in
RUN microdnf install -y --disablerepo=* /tmp/rpm/*.rpm && \
    microdnf clean all && \
    rm -rf /tmp/rpm
# -------------------------------------------------------------------------
# HERMETIC INSTALLATION END
# -------------------------------------------------------------------------

# Add clamav user and group
RUN groupadd -r clamav && useradd -r -g clamav clamav

# Create necessary directories
RUN mkdir -p /var/run/clamd.scan /var/log/clamav && \
    chmod -R 0777 /var/run/clamd.scan /var/log/clamav

# Update ClamD configuration
RUN sed -i 's|^#LogFile .*|LogFile /var/log/clamav/clamd.log|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#LocalSocket .*|LocalSocket /var/run/clamd.scan/clamd.sock|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#FixStaleSocket .*|FixStaleSocket yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxThreads .*|MaxThreads 8|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxDirectoryRecursion .*|MaxDirectoryRecursion 20000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#ConcurrentDatabaseReload .*|ConcurrentDatabaseReload yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertEncrypted .*|AlertEncrypted yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertEncryptedArchive .*|AlertEncryptedArchive yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertEncryptedDoc .*|AlertEncryptedDoc yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertOLE2Macros .*|AlertOLE2Macros yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertPhishingSSLMismatch .*|AlertPhishingSSLMismatch yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertPhishingCloak .*|AlertPhishingCloak yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertPartitionIntersection .*|AlertPartitionIntersection yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxScanTime .*|MaxScanTime 0|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxScanSize .*|MaxScanSize 4095M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxFileSize .*|MaxFileSize 2000M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxRecursion .*|MaxRecursion 1000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxFiles .*|MaxFiles 0|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxEmbeddedPE .*|MaxEmbeddedPE 4095M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxHTMLNormalize .*|MaxHTMLNormalize 10M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxHTMLNoTags .*|MaxHTMLNoTags 4095M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxScriptNormalize .*|MaxScriptNormalize 5M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxZipTypeRcg .*|MaxZipTypeRcg 4095M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxPartitions .*|MaxPartitions 50000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxIconsPE .*|MaxIconsPE 100000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#MaxRecHWP3 .*|MaxRecHWP3 20000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#PCREMatchLimit .*|PCREMatchLimit 100000000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#PCRERecMatchLimit .*|PCRERecMatchLimit 2000000|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#PCREMaxFileSize .*|PCREMaxFileSize 4095M|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#AlertExceedsMax .*|AlertExceedsMax yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#Bytecode .*|Bytecode yes|' /etc/clamd.d/scan.conf && \
    sed -i 's|^#BytecodeSecurity .*|BytecodeSecurity TrustSigned|' /etc/clamd.d/scan.conf

COPY /start-clamd.sh /start-clamd.sh

# Copies your code file from your action repository to the filesystem path `/` of the container
COPY test/selftest.sh /selftest.sh

# Use utils.sh by copying it from the image
COPY --from=konflux-test /utils.sh /utils.sh

COPY --from=konflux-test /usr/local/bin/ec /usr/local/bin/ec

# -------------------------------------------------------------------------
# DATABASE INSTALLATION (From fetch-db-data task)
# -------------------------------------------------------------------------
# Copy the DB files we downloaded in the pipeline
COPY clamav-db /var/lib/clamav/

# Ensure the clamav user owns them
RUN chown -R clamav:clamav /var/lib/clamav

COPY /whitelist.ign2 /var/lib/clamav/whitelist.ign2

COPY --from=konflux-test project $POLICY_PATH

# Download and install oc (Note: If this fails, you might need to prefetch 'oc' too!)
# For now, if the build is hermetic, this curl command will likely fail next.
RUN ARCH="$(uname -m)" && \
    curl -fsSL https://mirror.openshift.com/pub/openshift-v4/"$ARCH"/clients/ocp/stable/openshift-client-linux.tar.gz --output oc.tar.gz && \
    cp oc.tar.gz /usr/bin/oc && \
    tar -xzvf oc.tar.gz -C /usr/bin && \
    rm oc.tar.gz

ENTRYPOINT ["/start-clamd.sh"]
