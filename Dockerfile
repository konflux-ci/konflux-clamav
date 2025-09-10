FROM quay.io/konflux-ci/konflux-test:v1.4.38@sha256:c306aa4b764fcade1cbea8b8f7b6166e3a1289f56e03be99f669b9aaf7a92363 as konflux-test
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6-1754000177


ENV POLICY_PATH="/project"
# Install required packages
RUN rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    microdnf -y --setopt=tsflags=nodocs install \
    clamav \
    clamd \
    clamav-server \
    clamav-update \
    jq \
    tar \
    skopeo \
    findutils \
    && microdnf clean all

# Add clamav user and group
RUN groupadd -r clamav && useradd -r -g clamav clamav

# Create necessary directories
RUN mkdir -p /var/run/clamd.scan /var/log/clamav && \
    chmod -R 0777 /var/run/clamd.scan /var/log/clamav

# Update ClamD configuration based on https://github.com/konflux-ci/build-definitions/blob/main/task/clamav-scan/0.2/clamav-scan.yaml#L103
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

# Update ClamAV virus definitions
RUN freshclam

COPY /whitelist.ign2 /var/lib/clamav/whitelist.ign2

COPY --from=konflux-test project $POLICY_PATH


# Download and install oc
RUN ARCH="$(uname -m)" && \
    curl -fsSL https://mirror.openshift.com/pub/openshift-v4/"$ARCH"/clients/ocp/stable/openshift-client-linux.tar.gz --output oc.tar.gz && \
    cp oc.tar.gz /usr/bin/oc && \
    tar -xzvf oc.tar.gz -C /usr/bin && \
    rm oc.tar.gz

ENTRYPOINT ["/start-clamd.sh"]
