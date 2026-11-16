#!/usr/bin/bash

# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SOCKET="/var/run/clamd.scan/clamd.sock"
SCAN_CONF="/etc/clamd.d/scan.conf"
stub_dir=$(mktemp -d)
exit_stub="${stub_dir}/clamd-exit"
hang_stub="${stub_dir}/clamd-hang"

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

# The -c path is the mktemp copy from this start-clamd.sh run. Matching only
# /usr/sbin/clamd would also select a daemon already running in the container,
# which the test then kills.
find_started_clamd() {
    local proc_dir proc_cmd
    clamd_pid=""
    cmdline=""
    for proc_dir in /proc/[0-9]*; do
        proc_cmd=$(tr '\0' ' ' < "${proc_dir}/cmdline" 2>/dev/null || true)
        if [[ "${proc_cmd}" == /usr/sbin/clamd\ * && "${proc_cmd}" == *"-c /tmp/clamd-scan."* ]]; then
            clamd_pid=${proc_dir#/proc/}
            cmdline=${proc_cmd}
            return 0
        fi
    done
    return 1
}

echo "----------- Checking MAX_THREADS -----------"
for invalid_threads in '8;id' '0' '-1'; do
    capture_start env "MAX_THREADS=${invalid_threads}" /start-clamd.sh
    require_rc 1
    require_output "MAX_THREADS must be a positive integer"
    reject_output "Starting clamd ..."
done

echo "----------- Checking CLAMD_START_TIMEOUT -----------"
for invalid_timeout in 'abc' '2s' '08' '-1'; do
    capture_start env "CLAMD_START_TIMEOUT=${invalid_timeout}" /start-clamd.sh
    require_rc 1
    require_output "CLAMD_START_TIMEOUT must be a number"
    reject_output "Starting clamd ..."
done

echo "----------- Checking clamd startup failure -----------"
prepare_run
cat > "${exit_stub}" <<'EOF'
#!/usr/bin/bash
echo simulated-clamd-exit >&2
exit 1
EOF
chmod 755 "${exit_stub}"
capture_start env "CLAMD_BIN=${exit_stub}" /start-clamd.sh
require_rc 1
require_output "Failed to start clamd: process exited"
require_output "simulated-clamd-exit"
reject_output "clamd is ready!"

echo "----------- Checking stale clamd socket -----------"
python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "${SOCKET}"
[[ -S "${SOCKET}" ]]
capture_start env "CLAMD_BIN=${exit_stub}" /start-clamd.sh
require_rc 1
require_output "Failed to start clamd: process exited"
reject_output "clamd is ready!"

echo "----------- Checking clamd startup timeout -----------"
prepare_run
pidfile=$(mktemp)
cat > "${hang_stub}" <<EOF
#!/usr/bin/bash
echo \$\$ > '${pidfile}'
exec sleep 30
EOF
chmod 755 "${hang_stub}"
capture_start env "CLAMD_BIN=${hang_stub}" CLAMD_START_TIMEOUT=2 /start-clamd.sh
require_rc 1
require_output "Failed to start clamd: timed out after 2s waiting for clamd to answer on ${SOCKET}"
reject_output "clamd is ready!"
if [[ ! -s "${pidfile}" ]]; then
    echo "timeout stand-in did not record its pid" >&2
    exit 1
fi
hung_pid=$(cat "${pidfile}")
if [[ -d "/proc/${hung_pid}" ]]; then
    hung_state=$(awk '{print $3}' "/proc/${hung_pid}/stat")
    if [[ "${hung_state}" != "Z" ]]; then
        echo "timed out clamd is still running (state ${hung_state})" >&2
        kill "${hung_pid}" 2>/dev/null || true
        exit 1
    fi
fi
rm -f "${pidfile}"

echo "----------- Checking clamd startup -----------"
prepare_run
conf_before=$(sha256sum "${SCAN_CONF}")
capture_start env MAX_THREADS=3 /start-clamd.sh /usr/bin/echo clamd-exec-ok
require_rc 0
require_output "Starting clamd ..."
require_output "clamd is ready!"
require_output "clamd-exec-ok"
clamdscan --ping 1 >/dev/null
[[ "${conf_before}" == "$(sha256sum "${SCAN_CONF}")" ]]

clamd_pid=""
if ! find_started_clamd; then
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

# The cases above run as root, which can already rewrite scan.conf. This is
# the entrypoint user the /tmp copy exists for.
echo "----------- Checking clamd startup as clamav -----------"
prepare_run
capture_start runuser -u clamav -- env MAX_THREADS=3 /start-clamd.sh /usr/bin/echo clamd-exec-ok
require_rc 0
require_output "clamd is ready!"
require_output "clamd-exec-ok"
clamdscan --ping 1 >/dev/null
[[ "$(stat -c %U "${SOCKET}")" == clamav ]]
[[ "${conf_before}" == "$(sha256sum "${SCAN_CONF}")" ]]

clamd_pid=""
cmdline=""
if ! find_started_clamd; then
    echo "clamd did not survive a start as clamav" >&2
    exit 1
fi
clamav_uid=$(id -u clamav)
if [[ "$(awk '/^Uid:/{print $2}' "/proc/${clamd_pid}/status")" != "${clamav_uid}" ]]; then
    echo "clamd is not running as clamav" >&2
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
if [[ "${runtime_conf}" != /tmp/clamd-scan.* ]] || ! grep -qx 'MaxThreads 3' "${runtime_conf}"; then
    echo "clamav runtime config was not edited under /tmp: ${runtime_conf}" >&2
    exit 1
fi

kill "${clamd_pid}" 2>/dev/null || true
rm -f "${SOCKET}" "${runtime_conf}"
echo PASS
