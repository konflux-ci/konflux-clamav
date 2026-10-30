#!/usr/bin/env bash
set -e

CONF_FILE="/etc/clamd.d/scan.conf"
MAX_THREADS="${MAX_THREADS:-8}"
SOCKET="/var/run/clamd.scan/clamd.sock"
LOG_FILE="/var/log/clamav/clamd.log"
STARTUP_LOG="/var/log/clamav/startup.log"
# The socket appears only after the database is loaded. A dead clamd
# process fails the loop immediately; this bound is only for a slow load.
TIMEOUT=120
elapsed=0

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
  exit 1
}

# Foreground keeps this pid as clamd so a startup crash fails the wait.
# setsid detaches it from this shell, which returns to the clamav-scan task.
echo "Starting clamd ..."
setsid /usr/sbin/clamd -c "${runtime_conf}" --foreground=true >"${STARTUP_LOG}" 2>&1 &
clamd_pid=$!

while [ ! -S "$SOCKET" ]; do
  if ! kill -0 "$clamd_pid" 2>/dev/null; then
    fail_start "process exited"
  fi
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    fail_start "timed out after ${TIMEOUT}s waiting for ${SOCKET}"
  fi
done

echo "clamd is ready!"

# Run the user-provided command (if any)
if [ $# -gt 0 ]; then
  exec "$@"
fi
