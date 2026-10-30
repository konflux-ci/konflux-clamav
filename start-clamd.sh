#!/usr/bin/env bash
set -e

CONF_FILE="/etc/clamd.d/scan.conf"
MAX_THREADS="${MAX_THREADS:-8}"
SOCKET="/var/run/clamd.scan/clamd.sock"
LOG_FILE="/var/log/clamav/clamd.log"
STARTUP_LOG="/var/log/clamav/startup.log"
# The socket appears only after the database is loaded. A dead clamd
# process fails the loop immediately; this bound is only for a slow load.
# CLAMD_START_TIMEOUT lets the image self-test exercise the timeout path.
TIMEOUT="${CLAMD_START_TIMEOUT:-120}"
# CLAMD_BIN lets the image self-test substitute a stub without replacing the scanner.
CLAMD_BIN="${CLAMD_BIN:-/usr/sbin/clamd}"
elapsed=0

# Digits only. MAX_THREADS is inserted into a sed replacement. TIMEOUT is
# compared with -ge, which does not time out when the value is not a decimal
# integer (including leading-zero values such as 08).
[[ "${MAX_THREADS}" =~ ^[1-9][0-9]*$ ]] || { echo "MAX_THREADS must be a positive integer" >&2; exit 1; }
[[ "${TIMEOUT}" =~ ^(0|[1-9][0-9]*)$ ]] || { echo "CLAMD_START_TIMEOUT must be a number" >&2; exit 1; }

# sed -i writes a temporary file in the config directory. /etc/clamd.d is not
# writable by the image user (or by an arbitrary OpenShift uid), so edit a copy.
runtime_conf=$(mktemp /tmp/clamd-scan.XXXXXX)
cp "$CONF_FILE" "$runtime_conf"
if grep -q '^MaxThreads' "$runtime_conf"; then
  sed -i "s/^MaxThreads.*/MaxThreads $MAX_THREADS/" "$runtime_conf"
else
  echo "MaxThreads $MAX_THREADS" >> "$runtime_conf"
fi

fail_start() {
  echo "Failed to start clamd: $1" >&2
  if [ -s "$LOG_FILE" ]; then
    echo "----- ${LOG_FILE} -----" >&2
    cat "$LOG_FILE" >&2
  fi
  if [ -s "$STARTUP_LOG" ]; then
    echo "----- ${STARTUP_LOG} -----" >&2
    cat "$STARTUP_LOG" >&2
  fi
  # setsid put clamd in its own session, so exiting this script does not
  # deliver SIGHUP. Stop it when startup did not succeed.
  kill "$clamd_pid" 2>/dev/null || true
  exit 1
}

# A leftover socket inode is not a listening daemon, and FixStaleSocket only
# unlinks it once clamd starts. Remove it first, then wait until clamd answers.
rm -f "${SOCKET}"

# Foreground keeps this pid as clamd so a startup crash fails the wait.
# setsid detaches it from this shell, which returns to the clamav-scan task.
echo "Starting clamd ..."
setsid "${CLAMD_BIN}" -c "${runtime_conf}" --foreground=true >"${STARTUP_LOG}" 2>&1 &
clamd_pid=$!

while true; do
  # --ping 1 tries once and returns immediately when nothing is accepting.
  if clamdscan --ping 1 >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$clamd_pid" 2>/dev/null; then
    fail_start "process exited"
  fi
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    fail_start "timed out after ${TIMEOUT}s waiting for clamd to answer on ${SOCKET}"
  fi
done

echo "clamd is ready!"

# Run the user-provided command (if any)
if [ $# -gt 0 ]; then
  exec "$@"
fi
