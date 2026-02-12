FROM quay.io/konflux-ci/konflux-test:v1.4.47@sha256:baa60a08e86ab24476750bc010c29318e62ab4c921f5408f83f176dc10fcc079 as konflux-test
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7-1770267347

ENV POLICY_PATH="/project"

COPY RPM-GPG-KEY-EPEL-9 /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9

RUN microdnf -y --setopt=tsflags=nodocs --setopt=install_weak_deps=0 install \
    clamav \
    clamd \
    clamav-server \
    clamav-update \
    jq \
    skopeo \
    tar \
    && microdnf clean all

RUN groupadd -r clamav && useradd -r -g clamav clamav

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
COPY test/selftest.sh /selftest.sh
COPY --from=konflux-test /utils.sh /utils.sh
COPY --from=konflux-test /usr/local/bin/ec /usr/local/bin/ec

COPY clamav-db /var/lib/clamav/
RUN chown -R clamav:clamav /var/lib/clamav

COPY /whitelist.ign2 /var/lib/clamav/whitelist.ign2
COPY --from=konflux-test project $POLICY_PATH

COPY openshift-client-linux.tar.gz /tmp/oc.tar.gz

RUN tar -xzvf /tmp/oc.tar.gz -C /usr/bin oc && \
    rm /tmp/oc.tar.gz && \
    chmod +x /usr/bin/oc

ENTRYPOINT ["/start-clamd.sh"]
