#!/usr/bin/bash

# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SOCKET="/var/run/clamd.scan/clamd.sock"
SCAN_CONF="/etc/clamd.d/scan.conf"
CLAMD_BIN="/usr/sbin/clamd"
clamd_backup=$(mktemp)
cp -a "${CLAMD_BIN}" "${clamd_backup}"

restore_clamd() {
    local backup_sum current_sum
    backup_sum=$(sha256sum < "${clamd_backup}")
    current_sum=$(sha256sum < "${CLAMD_BIN}")
    if [[ "${backup_sum}" == "${current_sum}" ]]; then
        return 0
    fi
    cp -a "${clamd_backup}" "${CLAMD_BIN}"
    chmod 755 "${CLAMD_BIN}"
}
trap restore_clamd EXIT

prepare_run() {
    rm -f "${SOCKET}" /var/log/clamav/startup.log /var/log/clamav/clamd.log
}

capture_start() {
    set +e
    start_output=$( "$@" 2>&1 )
    start_rc=$?
    set -e
}

require_rc() {
    local expected="$1"
    if [[ "${start_rc}" -ne "${expected}" ]]; then
        echo "expected exit ${expected}, got ${start_rc}" >&2
        printf '%s\n' "${start_output}" >&2
        exit 1
    fi
}

require_output() {
    local pattern="$1"
    if ! grep -F -- "${pattern}" <<< "${start_output}" >/dev/null; then
        echo "missing output: ${pattern}" >&2
        printf '%s\n' "${start_output}" >&2
        exit 1
    fi
}

reject_output() {
    local pattern="$1"
    if grep -F -- "${pattern}" <<< "${start_output}" >/dev/null; then
        echo "unexpected output: ${pattern}" >&2
        printf '%s\n' "${start_output}" >&2
        exit 1
    fi
}

echo "----------- Checking clamd startup failure -----------"
prepare_run
cat > "${CLAMD_BIN}" <<'EOF'
#!/usr/bin/bash
echo simulated-clamd-exit >&2
exit 1
EOF
chmod 755 "${CLAMD_BIN}"
capture_start /start-clamd.sh
require_rc 1
require_output "Failed to start clamd: process exited"
require_output "simulated-clamd-exit"
reject_output "clamd is ready!"

echo "----------- Checking clamd startup timeout -----------"
prepare_run
pidfile=$(mktemp)
cat > "${CLAMD_BIN}" <<EOF
#!/usr/bin/bash
echo \$\$ > '${pidfile}'
exec sleep 30
EOF
chmod 755 "${CLAMD_BIN}"
capture_start env CLAMD_START_TIMEOUT=2 /start-clamd.sh
require_rc 1
require_output "Failed to start clamd: timed out after 2s waiting for ${SOCKET}"
reject_output "clamd is ready!"
if [[ -s "${pidfile}" ]]; then
    kill "$(cat "${pidfile}")" 2>/dev/null || true
fi
rm -f "${pidfile}"

echo "----------- Checking clamd startup -----------"
restore_clamd
prepare_run
conf_before=$(sha256sum "${SCAN_CONF}")
capture_start env MAX_THREADS=3 /start-clamd.sh /usr/bin/echo clamd-exec-ok
require_rc 0
require_output "Starting clamd ..."
require_output "clamd is ready!"
require_output "clamd-exec-ok"
[[ -S "${SOCKET}" ]]
[[ "${conf_before}" == "$(sha256sum "${SCAN_CONF}")" ]]

clamd_pid=""
for proc_dir in /proc/[0-9]*; do
    cmdline=$(tr '\0' ' ' < "${proc_dir}/cmdline" 2>/dev/null || true)
    if [[ "${cmdline}" == /usr/sbin/clamd\ * ]]; then
        clamd_pid=${proc_dir#/proc/}
        break
    fi
done
if [[ -z "${clamd_pid}" ]]; then
    echo "clamd did not survive start-clamd.sh" >&2
    exit 1
fi
kill -0 "${clamd_pid}"
session=$(awk '{print $6}' "/proc/${clamd_pid}/stat")
if [[ "${session}" != "${clamd_pid}" ]]; then
    echo "clamd pid ${clamd_pid} is not a session leader (sid ${session})" >&2
    exit 1
fi
if [[ "${cmdline}" != *"--foreground=true"* ]]; then
    echo "clamd was not started in the foreground: ${cmdline}" >&2
    exit 1
fi

runtime_conf=""
previous=""
while IFS= read -r -d '' arg; do
    if [[ "${previous}" == "-c" ]]; then
        runtime_conf="${arg}"
    fi
    previous="${arg}"
done < "/proc/${clamd_pid}/cmdline"
if [[ "${runtime_conf}" != /tmp/clamd-scan.* ]]; then
    echo "clamd config was not a /tmp copy: ${runtime_conf}" >&2
    exit 1
fi
if ! grep -qx 'MaxThreads 3' "${runtime_conf}"; then
    echo "runtime config does not set MaxThreads 3" >&2
    cat "${runtime_conf}" >&2
    exit 1
fi

kill "${clamd_pid}" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "${clamd_pid}" 2>/dev/null; then
        break
    fi
    sleep 0.2
done
rm -f "${SOCKET}" "${runtime_conf}"
echo PASS
